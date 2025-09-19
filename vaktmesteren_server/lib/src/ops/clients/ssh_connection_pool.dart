import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:serverpod/serverpod.dart';
import '../models/ssh_connection.dart';
import '../models/ssh_config.dart';

/// SSH connection pool entry
class _SshPoolEntry {
  final SSHClient client;
  final DateTime lastUsed;
  final String connectionKey;
  bool inUse;

  _SshPoolEntry({
    required this.client,
    required this.lastUsed,
    required this.connectionKey,
    this.inUse = false,
  });
}

/// SSH connection pool manager
class SshConnectionPool {
  final Session session;
  final SshConfig config;
  final Map<String, List<_SshPoolEntry>> _pools = {};
  final Map<String, int> _connectionAttempts = {};
  final Map<String, DateTime> _lastConnectionFailure = {};
  late final Timer _cleanupTimer;

  SshConnectionPool(this.session, this.config) {
    // Start cleanup timer to remove stale connections
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupStaleConnections(),
    );
  }

  /// Get or create an SSH client for the connection
  Future<SSHClient> getClient(SshConnection connection) async {
    final key = _getConnectionKey(connection);

    // Check if we're in rate limiting period
    if (_isRateLimited(key)) {
      throw Exception('Connection rate limited for $key');
    }

    // Try to get an existing connection from pool
    var poolEntry = _getAvailableConnection(key);
    if (poolEntry != null) {
      poolEntry.inUse = true;
      if (config.logConnectionEvents) {
        session.log(
            '🔄 Reusing SSH connection to ${connection.connectionString}',
            level: LogLevel.debug);
      }
      return poolEntry.client;
    }

    // Create new connection if pool not full
    if (_getPoolSize(key) >= config.maxConnections) {
      throw Exception('SSH connection pool full for $key');
    }

    return await _createNewConnection(connection);
  }

  /// Release an SSH client back to the pool
  void releaseClient(SshConnection connection, SSHClient client) {
    final key = _getConnectionKey(connection);
    final entries = _pools[key] ?? [];

    for (final entry in entries) {
      if (entry.client == client) {
        entry.inUse = false;
        if (config.logConnectionEvents) {
          session.log(
              '↩️ Released SSH connection to ${connection.connectionString}',
              level: LogLevel.debug);
        }
        break;
      }
    }
  }

  /// Create a new SSH connection
  Future<SSHClient> _createNewConnection(SshConnection connection) async {
    final key = _getConnectionKey(connection);

    try {
      if (config.logConnectionEvents) {
        session.log(
            '🔗 Creating new SSH connection to ${connection.connectionString}',
            level: LogLevel.info);
      }

      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: config.connectionTimeout,
      );

      final client = SSHClient(
        socket,
        username: connection.username,
        onPasswordRequest:
            connection.password != null ? () => connection.password! : null,
        identities: connection.privateKeyPath != null
            ? SSHKeyPair.fromPem(
                await File(connection.privateKeyPath!).readAsString())
            : null,
      );

      // Store in pool
      final entry = _SshPoolEntry(
        client: client,
        lastUsed: DateTime.now(),
        connectionKey: key,
        inUse: true,
      );

      _pools.putIfAbsent(key, () => []).add(entry);
      _connectionAttempts[key] = 0; // Reset failure count on success

      if (config.logConnectionEvents) {
        session.log(
            '✅ SSH connection established to ${connection.connectionString}',
            level: LogLevel.info);
      }

      return client;
    } catch (e) {
      _recordConnectionFailure(key);
      if (config.logConnectionEvents) {
        session.log(
            '❌ SSH connection failed to ${connection.connectionString}: $e',
            level: LogLevel.error);
      }
      rethrow;
    }
  }

  /// Get available connection from pool
  _SshPoolEntry? _getAvailableConnection(String key) {
    final entries = _pools[key];
    if (entries == null) return null;

    for (final entry in entries) {
      if (!entry.inUse) {
        return entry;
      }
    }
    return null;
  }

  /// Get connection key for pooling
  String _getConnectionKey(SshConnection connection) {
    return '${connection.username}@${connection.host}:${connection.port}';
  }

  /// Get current pool size for a connection
  int _getPoolSize(String key) {
    return _pools[key]?.length ?? 0;
  }

  /// Record connection failure for rate limiting
  void _recordConnectionFailure(String key) {
    _connectionAttempts[key] = (_connectionAttempts[key] ?? 0) + 1;
    _lastConnectionFailure[key] = DateTime.now();
  }

  /// Check if connection is rate limited
  bool _isRateLimited(String key) {
    final attempts = _connectionAttempts[key] ?? 0;
    final lastFailure = _lastConnectionFailure[key];

    if (attempts < config.maxRetries) return false;
    if (lastFailure == null) return false;

    final timeSinceFailure = DateTime.now().difference(lastFailure);
    return timeSinceFailure < config.retryDelay;
  }

  /// Clean up stale connections
  void _cleanupStaleConnections() {
    final now = DateTime.now();
    const maxIdleTime = Duration(minutes: 10);

    for (final key in _pools.keys.toList()) {
      final entries = _pools[key]!;
      entries.removeWhere((entry) {
        final isStale =
            !entry.inUse && now.difference(entry.lastUsed) > maxIdleTime;
        if (isStale) {
          try {
            entry.client.close();
            if (config.logConnectionEvents) {
              session.log('🧹 Cleaned up stale SSH connection: $key',
                  level: LogLevel.debug);
            }
          } catch (e) {
            session.log('Error closing stale SSH connection: $e',
                level: LogLevel.warning);
          }
        }
        return isStale;
      });

      if (entries.isEmpty) {
        _pools.remove(key);
      }
    }
  }

  /// Get connection pool statistics
  Map<String, dynamic> getStats() {
    int totalConnections = 0;
    int activeConnections = 0;
    int idleConnections = 0;

    for (final entries in _pools.values) {
      totalConnections += entries.length;
      for (final entry in entries) {
        if (entry.inUse) {
          activeConnections++;
        } else {
          idleConnections++;
        }
      }
    }

    return {
      'totalConnections': totalConnections,
      'activeConnections': activeConnections,
      'idleConnections': idleConnections,
      'poolCount': _pools.length,
      'connectionAttempts': _connectionAttempts,
      'rateLimitedConnections': _lastConnectionFailure.length,
    };
  }

  /// Close all connections and cleanup
  void dispose() {
    _cleanupTimer.cancel();

    for (final entries in _pools.values) {
      for (final entry in entries) {
        try {
          entry.client.close();
        } catch (e) {
          session.log('Error closing SSH connection during dispose: $e',
              level: LogLevel.warning);
        }
      }
    }

    _pools.clear();
    _connectionAttempts.clear();
    _lastConnectionFailure.clear();

    if (config.logConnectionEvents) {
      session.log('🔐 SSH connection pool disposed', level: LogLevel.info);
    }
  }
}

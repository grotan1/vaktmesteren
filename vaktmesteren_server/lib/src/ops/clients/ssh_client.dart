import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:serverpod/serverpod.dart';
import '../models/ssh_connection.dart';
import '../models/ssh_config.dart';
import 'ssh_connection_pool.dart';

/// Result of an SSH command execution (or simulation)
class SshResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final bool wasSimulated;

  const SshResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
    this.wasSimulated = false,
  });

  bool get isSuccess => exitCode == 0;
  bool get isFailure => !isSuccess;

  @override
  String toString() =>
      'SshResult(exitCode=$exitCode, duration=${duration.inMilliseconds}ms, simulated=$wasSimulated)';
}

/// SSH client with real execution capabilities using dartssh2
class SshClient {
  final Session session;
  final bool logOnly;
  final SshConfig config;
  late final SshConnectionPool _connectionPool;
  final Map<String, int> _commandCounter = {};
  final Map<String, DateTime> _lastCommandTime = {};
  final Map<String, List<Duration>> _commandTimings = {};
  final Set<String> _enabledServices =
      {}; // Track enabled services for simulation

  SshClient(
    this.session, {
    this.logOnly = true,
    SshConfig? config,
  }) : config = config ?? const SshConfig() {
    _connectionPool = SshConnectionPool(session, this.config);
  }

  /// Execute a command on a remote server
  Future<SshResult> executeCommand(
    SshConnection connection,
    String command, {
    Duration? timeout,
  }) async {
    final startTime = DateTime.now();
    final actualTimeout = timeout ?? config.commandTimeout;
    final connectionKey = '${connection.host}:${connection.port}';

    // Input validation and sanitization
    if (command.trim().isEmpty) {
      throw ArgumentError('Command cannot be empty');
    }

    final sanitizedCommand = _sanitizeCommand(command);
    if (sanitizedCommand != command) {
      session.log('⚠️ Command was sanitized for security',
          level: LogLevel.warning);
    }

    try {
      if (config.logCommands) {
        session.log(
          '🔐 SSH ${logOnly ? 'SIMULATION' : 'EXECUTION'}: ${connection.connectionString}',
          level: LogLevel.info,
        );
        session.log('📝 Command: $sanitizedCommand', level: LogLevel.info);
      }

      if (logOnly) {
        return await _simulateExecution(
            sanitizedCommand, actualTimeout, startTime);
      } else {
        return await _executeReal(
            connection, sanitizedCommand, actualTimeout, startTime);
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      session.log(
        '❌ SSH ${logOnly ? 'SIMULATION' : 'EXECUTION'} failed: $e',
        level: LogLevel.error,
      );

      return SshResult(
        exitCode: 1,
        stdout: '',
        stderr: 'SSH execution failed: $e',
        duration: duration,
        wasSimulated: logOnly,
      );
    } finally {
      _lastCommandTime[connectionKey] = DateTime.now();
      _commandCounter[connectionKey] =
          (_commandCounter[connectionKey] ?? 0) + 1;
    }
  }

  /// Execute command using real SSH connection
  Future<SshResult> _executeReal(
    SshConnection connection,
    String command,
    Duration timeout,
    DateTime startTime,
  ) async {
    SSHClient? client;

    try {
      // Get SSH client from pool
      client = await _connectionPool.getClient(connection);

      // Execute command
      final sshSession = await client.execute(command).timeout(timeout);

      // Collect stdout and stderr
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final stdoutCompleter = Completer<void>();
      final stderrCompleter = Completer<void>();

      sshSession.stdout.cast<List<int>>().transform(utf8.decoder).listen(
            (data) => stdoutBuffer.write(data),
            onDone: () => stdoutCompleter.complete(),
            onError: (e) => stdoutCompleter.completeError(e),
          );

      sshSession.stderr.cast<List<int>>().transform(utf8.decoder).listen(
            (data) => stderrBuffer.write(data),
            onDone: () => stderrCompleter.complete(),
            onError: (e) => stderrCompleter.completeError(e),
          );

      // Wait for command completion
      final exitCode = sshSession.exitCode ?? 1;

      // Wait for stream completion with timeout
      try {
        await Future.wait([
          stdoutCompleter.future,
          stderrCompleter.future,
        ]).timeout(const Duration(seconds: 5));
      } catch (e) {
        session.log('Warning: Stream completion timeout: $e',
            level: LogLevel.warning);
      }

      final duration = DateTime.now().difference(startTime);
      _recordCommandTiming(connection, duration);

      final sshResult = SshResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        duration: duration,
        wasSimulated: false,
      );

      if (config.logCommands) {
        session.log(
          '✅ SSH EXECUTION completed: ${sshResult.exitCode == 0 ? 'SUCCESS' : 'FAILED'} (${duration.inMilliseconds}ms)',
          level: sshResult.isSuccess ? LogLevel.info : LogLevel.warning,
        );

        if (sshResult.stdout.isNotEmpty) {
          session.log('📤 stdout: ${sshResult.stdout.trim()}',
              level: LogLevel.debug);
        }

        if (sshResult.stderr.isNotEmpty) {
          session.log('📤 stderr: ${sshResult.stderr.trim()}',
              level: LogLevel.debug);
        }
      }

      return sshResult;
    } on TimeoutException {
      final duration = DateTime.now().difference(startTime);
      session.log(
        '⏰ SSH command timed out after ${duration.inSeconds}s',
        level: LogLevel.warning,
      );

      return SshResult(
        exitCode: 124, // Standard timeout exit code
        stdout: '',
        stderr: 'Command timed out after ${timeout.inSeconds} seconds',
        duration: duration,
        wasSimulated: false,
      );
    } finally {
      if (client != null) {
        _connectionPool.releaseClient(connection, client);
      }
    }
  }

  /// Simulate command execution (unchanged from original)
  Future<SshResult> _simulateExecution(
    String command,
    Duration timeout,
    DateTime startTime,
  ) async {
    // Simulate different execution times based on command type
    Duration simulatedDuration;

    if (command.contains('systemctl restart')) {
      simulatedDuration = const Duration(seconds: 3);
    } else if (command.contains('systemctl status')) {
      simulatedDuration = const Duration(milliseconds: 500);
    } else if (command.contains('echo')) {
      simulatedDuration = const Duration(milliseconds: 100);
    } else {
      simulatedDuration = const Duration(seconds: 1);
    }

    if (simulatedDuration > timeout) {
      simulatedDuration = timeout;
    }

    await Future.delayed(simulatedDuration);

    final duration = DateTime.now().difference(startTime);
    final result = _simulateCommandResult(command, duration);

    if (config.logCommands) {
      session.log(
        '✅ SSH SIMULATION completed: ${result.exitCode == 0 ? 'SUCCESS' : 'FAILED'} (${duration.inMilliseconds}ms)',
        level: result.isSuccess ? LogLevel.info : LogLevel.warning,
      );

      if (result.stdout.isNotEmpty) {
        session.log('📤 Simulated stdout: ${result.stdout}',
            level: LogLevel.debug);
      }

      if (result.stderr.isNotEmpty) {
        session.log('📤 Simulated stderr: ${result.stderr}',
            level: LogLevel.debug);
      }
    }

    return result;
  }

  /// Test SSH connection
  Future<bool> testConnection(SshConnection connection) async {
    if (config.logConnectionEvents) {
      session.log(
        '🔍 Testing SSH connection to ${connection.connectionString}',
        level: LogLevel.info,
      );
    }

    try {
      final result = await executeCommand(connection, 'echo "connection test"');

      if (result.isSuccess) {
        if (config.logConnectionEvents) {
          session.log(
            '✅ SSH connection test ${logOnly ? 'simulation ' : ''}successful',
            level: LogLevel.info,
          );
        }
        return true;
      } else {
        if (config.logConnectionEvents) {
          session.log(
            '❌ SSH connection test ${logOnly ? 'simulation ' : ''}failed: ${result.stderr}',
            level: LogLevel.warning,
          );
        }
        return false;
      }
    } catch (e) {
      if (config.logConnectionEvents) {
        session.log(
          '❌ SSH connection test ${logOnly ? 'simulation ' : ''}error: $e',
          level: LogLevel.error,
        );
      }
      return false;
    }
  }

  /// Sanitize command input to prevent injection attacks
  String _sanitizeCommand(String command) {
    // Remove dangerous characters and patterns
    var sanitized = command;

    // Remove null bytes
    sanitized = sanitized.replaceAll('\x00', '');

    // Remove control characters except newline and tab
    sanitized =
        sanitized.replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // Limit command length
    if (sanitized.length > 4096) {
      sanitized = sanitized.substring(0, 4096);
    }

    return sanitized.trim();
  }

  /// Record command timing for metrics
  void _recordCommandTiming(SshConnection connection, Duration duration) {
    final key = connection.connectionString;
    _commandTimings.putIfAbsent(key, () => []).add(duration);

    // Keep only last 100 timings per connection
    final timings = _commandTimings[key]!;
    if (timings.length > 100) {
      timings.removeRange(0, timings.length - 100);
    }
  }

  /// Generate realistic command results for simulation (unchanged)
  SshResult _simulateCommandResult(String command, Duration duration) {
    if (command.contains('systemctl restart')) {
      return SshResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    } else if (command.contains('systemctl is-active')) {
      // Simulate service being active after restart
      return SshResult(
        exitCode: 0,
        stdout: 'active',
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    } else if (command.contains('systemctl is-enabled')) {
      // Simulate checking if service is enabled
      // For testing purposes, let's simulate some services as disabled initially
      final serviceName = _extractServiceName(command);
      final isInitiallyDisabled =
          serviceName.contains('test') || serviceName.contains('ser2net');

      if (isInitiallyDisabled && !_enabledServices.contains(serviceName)) {
        return SshResult(
          exitCode: 1, // systemctl is-enabled returns 1 for disabled services
          stdout: 'disabled',
          stderr: '',
          duration: duration,
          wasSimulated: true,
        );
      } else {
        return SshResult(
          exitCode: 0,
          stdout: 'enabled',
          stderr: '',
          duration: duration,
          wasSimulated: true,
        );
      }
    } else if (command.contains('systemctl enable')) {
      // Simulate enabling a service
      final serviceName = _extractServiceName(command);

      // If service was already enabled, simulate "already enabled" scenario
      if (_enabledServices.contains(serviceName)) {
        return SshResult(
          exitCode: 1, // systemctl enable returns 1 if already enabled
          stdout: '',
          stderr:
              'The unit files have no installation config (unit file is masked, already enabled, or a static unit file).',
          duration: duration,
          wasSimulated: true,
        );
      } else {
        _enabledServices
            .add(serviceName); // Track enabled services for simulation
        return SshResult(
          exitCode: 0,
          stdout:
              'Created symlink /etc/systemd/system/multi-user.target.wants/$serviceName.service → /etc/systemd/system/$serviceName.service.',
          stderr: '',
          duration: duration,
          wasSimulated: true,
        );
      }
    } else if (command.contains('systemctl status')) {
      final serviceName = _extractServiceName(command);
      return SshResult(
        exitCode: 0,
        stdout: '● $serviceName.service - $serviceName\n'
            '   Loaded: loaded (/etc/systemd/system/$serviceName.service; enabled)\n'
            '   Active: active (running) since ${DateTime.now()}\n',
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    } else if (command.contains('echo')) {
      final text = command.replaceFirst('echo ', '').replaceAll('"', '');
      return SshResult(
        exitCode: 0,
        stdout: text,
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    } else {
      return SshResult(
        exitCode: 0,
        stdout: 'Command executed successfully (simulated)',
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    }
  }

  /// Extract service name from systemctl command (unchanged)
  String _extractServiceName(String command) {
    final parts = command.split(' ');
    for (int i = 0; i < parts.length - 1; i++) {
      if (parts[i] == 'systemctl' && i + 2 < parts.length) {
        return parts[i + 2];
      }
    }
    return 'unknown';
  }

  /// Get comprehensive connection statistics
  Map<String, dynamic> getConnectionStats() {
    final poolStats = _connectionPool.getStats();
    final commandStats = _getCommandStats();

    return {
      'logOnlyMode': logOnly,
      'sshEnabled': config.enabled,
      'pool': poolStats,
      'commands': commandStats,
      'config': {
        'maxConnections': config.maxConnections,
        'connectionTimeout': config.connectionTimeout.inSeconds,
        'commandTimeout': config.commandTimeout.inSeconds,
        'maxRetries': config.maxRetries,
        'verifyHostKeys': config.verifyHostKeys,
      },
    };
  }

  /// Get command execution statistics
  Map<String, dynamic> _getCommandStats() {
    int totalCommands = 0;
    final Map<String, int> commandsPerHost = {};
    final Map<String, double> avgTimingsPerHost = {};

    for (final entry in _commandCounter.entries) {
      final count = entry.value;
      totalCommands += count;
      commandsPerHost[entry.key] = count;
    }

    for (final entry in _commandTimings.entries) {
      final timings = entry.value;
      if (timings.isNotEmpty) {
        final avgMs =
            timings.map((d) => d.inMilliseconds).reduce((a, b) => a + b) /
                timings.length;
        avgTimingsPerHost[entry.key] = avgMs;
      }
    }

    return {
      'totalCommands': totalCommands,
      'commandsPerHost': commandsPerHost,
      'averageTimingsMs': avgTimingsPerHost,
      'recentCommandsCount': _commandCounter.entries
          .where((entry) =>
              _lastCommandTime[entry.key] != null &&
              DateTime.now()
                      .difference(_lastCommandTime[entry.key]!)
                      .inMinutes <
                  60)
          .fold(0, (sum, entry) => sum + entry.value),
    };
  }

  /// Close all connections and cleanup
  void dispose() {
    _connectionPool.dispose();
    _commandCounter.clear();
    _lastCommandTime.clear();
    _commandTimings.clear();

    session.log('🔐 SSH client disposed', level: LogLevel.info);
  }
}

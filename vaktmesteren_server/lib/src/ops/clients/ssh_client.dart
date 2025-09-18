import 'dart:async';
import 'package:serverpod/serverpod.dart';
import '../models/ssh_connection.dart';

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

/// SSH client that logs commands instead of executing them (for safe development)
class SshClient {
  final Session session;
  final bool logOnly;
  final Map<String, DateTime> _lastConnections = {};
  final Map<String, int> _connectionAttempts = {};

  SshClient(this.session, {this.logOnly = true});

  /// Execute a command on a remote server (or simulate it)
  Future<SshResult> executeCommand(
    SshConnection connection,
    String command, {
    Duration? timeout,
  }) async {
    final startTime = DateTime.now();
    final actualTimeout = timeout ?? connection.timeout;
    final connectionKey = '${connection.host}:${connection.port}';

    try {
      session.log(
        '🔐 SSH ${logOnly ? 'SIMULATION' : 'EXECUTION'}: ${connection.connectionString}',
        level: LogLevel.info,
      );

      session.log(
        '📝 Command: $command',
        level: LogLevel.info,
      );

      if (logOnly) {
        // Simulate execution with realistic timing
        await _simulateExecution(command, actualTimeout);

        final duration = DateTime.now().difference(startTime);
        final result = _simulateCommandResult(command, duration);

        session.log(
          '✅ SSH SIMULATION completed: ${result.exitCode == 0 ? 'SUCCESS' : 'FAILED'} (${duration.inMilliseconds}ms)',
          level: result.isSuccess ? LogLevel.info : LogLevel.warning,
        );

        if (result.stdout.isNotEmpty) {
          session.log('📤 Simulated stdout: ${result.stdout}',
              level: LogLevel.info);
        }

        if (result.stderr.isNotEmpty) {
          session.log('📤 Simulated stderr: ${result.stderr}',
              level: LogLevel.warning);
        }

        return result;
      } else {
        // TODO: Real SSH execution would go here
        throw UnsupportedError('Real SSH execution not implemented yet');
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
      _lastConnections[connectionKey] = DateTime.now();
    }
  }

  /// Test SSH connection (or simulate it)
  Future<bool> testConnection(SshConnection connection) async {
    session.log(
      '🔍 Testing SSH connection to ${connection.connectionString}',
      level: LogLevel.info,
    );

    try {
      final result = await executeCommand(connection, 'echo "connection test"');

      if (result.isSuccess) {
        session.log(
          '✅ SSH connection test ${logOnly ? 'simulation ' : ''}successful',
          level: LogLevel.info,
        );
        return true;
      } else {
        session.log(
          '❌ SSH connection test ${logOnly ? 'simulation ' : ''}failed: ${result.stderr}',
          level: LogLevel.warning,
        );
        return false;
      }
    } catch (e) {
      session.log(
        '❌ SSH connection test ${logOnly ? 'simulation ' : ''}error: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  /// Simulate command execution with realistic timing
  Future<void> _simulateExecution(String command, Duration timeout) async {
    // Simulate different execution times based on command type
    Duration simulatedDuration;

    if (command.contains('systemctl restart')) {
      // Service restarts typically take 2-10 seconds
      simulatedDuration = const Duration(seconds: 3);
    } else if (command.contains('systemctl status')) {
      // Status checks are usually quick
      simulatedDuration = const Duration(milliseconds: 500);
    } else if (command.contains('echo')) {
      // Echo commands are instant
      simulatedDuration = const Duration(milliseconds: 100);
    } else {
      // Default simulation time
      simulatedDuration = const Duration(seconds: 1);
    }

    // Don't exceed the timeout
    if (simulatedDuration > timeout) {
      simulatedDuration = timeout;
    }

    await Future.delayed(simulatedDuration);
  }

  /// Generate realistic command results for simulation
  SshResult _simulateCommandResult(String command, Duration duration) {
    // Simulate different outcomes based on command
    if (command.contains('systemctl restart')) {
      // Most restarts succeed
      return SshResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    } else if (command.contains('systemctl status')) {
      // Status commands usually succeed with output
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
      // Echo commands return the echoed text
      final text = command.replaceFirst('echo ', '').replaceAll('"', '');
      return SshResult(
        exitCode: 0,
        stdout: text,
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    } else {
      // Default success
      return SshResult(
        exitCode: 0,
        stdout: 'Command executed successfully (simulated)',
        stderr: '',
        duration: duration,
        wasSimulated: true,
      );
    }
  }

  /// Extract service name from systemctl command
  String _extractServiceName(String command) {
    final parts = command.split(' ');
    for (int i = 0; i < parts.length - 1; i++) {
      if (parts[i] == 'systemctl' && i + 2 < parts.length) {
        return parts[i + 2];
      }
    }
    return 'unknown';
  }

  /// Get connection statistics for monitoring
  Map<String, dynamic> getConnectionStats() {
    return {
      'totalConnections': _lastConnections.length,
      'recentConnections': _lastConnections.entries
          .where(
              (entry) => DateTime.now().difference(entry.value).inMinutes < 60)
          .length,
      'logOnlyMode': logOnly,
    };
  }

  /// Close all connections (cleanup)
  void dispose() {
    session.log('🔐 SSH client disposed', level: LogLevel.info);
    _lastConnections.clear();
    _connectionAttempts.clear();
  }
}

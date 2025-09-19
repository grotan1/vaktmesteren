import 'dart:async';
import 'package:serverpod/serverpod.dart';
import '../clients/ssh_client.dart';
import '../models/ssh_connection.dart';
import '../models/restart_rule.dart';
import '../../web/routes/log_viewer.dart';

/// Result of a service restart operation
class RestartResult {
  final bool success;
  final String serviceName;
  final String host;
  final Duration duration;
  final String message;
  final List<String> logs;
  final bool wasSimulated;

  const RestartResult({
    required this.success,
    required this.serviceName,
    required this.host,
    required this.duration,
    required this.message,
    this.logs = const [],
    this.wasSimulated = false,
  });

  @override
  String toString() =>
      'RestartResult($serviceName on $host: ${success ? 'SUCCESS' : 'FAILED'}, ${duration.inSeconds}s, simulated=$wasSimulated)';
}

/// Service for managing Linux systemd service restarts via SSH
class LinuxServiceRestartService {
  final Session session;
  final SshClient sshClient;
  final Map<String, List<DateTime>> _restartHistory = {};
  final Map<String, DateTime> _lastRestartAttempt = {};

  LinuxServiceRestartService(this.session, this.sshClient);

  /// Restart a service based on a restart rule
  Future<RestartResult> restartService(
    RestartRule rule,
    SshConnection connection,
    String icingaServiceName,
  ) async {
    final startTime = DateTime.now();
    final restartKey = '${connection.host}:${rule.systemdServiceName}';

    try {
      session.log(
        '🔄 Starting service restart: ${rule.systemdServiceName} on ${connection.host} (triggered by $icingaServiceName)',
        level: LogLevel.info,
      );

      // Broadcast restart start to WebSocket clients
      LogBroadcaster.broadcastLog(
          '🔄 ${sshClient.logOnly ? 'SIMULATING' : 'EXECUTING'} service restart: ${rule.systemdServiceName} on ${connection.host}');

      // Check restart limit (simple counter, not time-based)
      if (!_canRestart(rule, restartKey)) {
        final message =
            'Restart limit reached: ${rule.systemdServiceName} on ${connection.host} (max ${rule.maxRestarts} attempts)';
        session.log(message, level: LogLevel.warning);

        LogBroadcaster.broadcastLog('⏸️ $message');

        return RestartResult(
          success: false,
          serviceName: rule.systemdServiceName,
          host: connection.host,
          duration: DateTime.now().difference(startTime),
          message: message,
          wasSimulated: sshClient.logOnly,
        );
      }

      // Check cooldown period
      final lastRestart = _lastRestartAttempt[restartKey];
      if (lastRestart != null &&
          DateTime.now().difference(lastRestart) < rule.cooldownPeriod) {
        final message =
            'Restart in cooldown: ${rule.systemdServiceName} on ${connection.host} (${rule.cooldownPeriod.inMinutes}min cooldown)';
        session.log(message, level: LogLevel.warning);

        LogBroadcaster.broadcastLog('⏸️ $message');

        return RestartResult(
          success: false,
          serviceName: rule.systemdServiceName,
          host: connection.host,
          duration: DateTime.now().difference(startTime),
          message: message,
          wasSimulated: sshClient.logOnly,
        );
      }

      final logs = <String>[];

      // Run pre-checks
      if (rule.preChecks.isNotEmpty) {
        session.log('Running pre-restart checks...', level: LogLevel.info);
        for (final check in rule.preChecks) {
          final result = await sshClient.executeCommand(connection, check);
          logs.add('Pre-check: $check -> exit ${result.exitCode}');

          if (result.isFailure) {
            final message =
                'Pre-check failed: $check (exit ${result.exitCode})';
            session.log(message, level: LogLevel.error);

            LogBroadcaster.broadcastLog('❌ $message');

            return RestartResult(
              success: false,
              serviceName: rule.systemdServiceName,
              host: connection.host,
              duration: DateTime.now().difference(startTime),
              message: message,
              logs: logs,
              wasSimulated: sshClient.logOnly,
            );
          }
        }
      }

      // Execute the restart command
      session.log('Executing restart command: ${rule.restartCommand}',
          level: LogLevel.info);
      final restartResult =
          await sshClient.executeCommand(connection, rule.restartCommand);
      logs.add(
          'Restart: ${rule.restartCommand} -> exit ${restartResult.exitCode}');

      if (restartResult.isFailure) {
        final message =
            'Service restart failed: ${rule.systemdServiceName} (exit ${restartResult.exitCode})';
        session.log(message, level: LogLevel.error);

        LogBroadcaster.broadcastLog('❌ $message');

        return RestartResult(
          success: false,
          serviceName: rule.systemdServiceName,
          host: connection.host,
          duration: DateTime.now().difference(startTime),
          message: message,
          logs: logs,
          wasSimulated: sshClient.logOnly,
        );
      }

      // Wait a moment for service to start
      await Future.delayed(const Duration(seconds: 2));

      // Run post-checks
      if (rule.postChecks.isNotEmpty) {
        session.log('Running post-restart checks...', level: LogLevel.info);
        for (final check in rule.postChecks) {
          final result = await sshClient.executeCommand(connection, check);
          logs.add('Post-check: $check -> exit ${result.exitCode}');

          if (result.isFailure) {
            session.log('Post-check failed: $check (exit ${result.exitCode})',
                level: LogLevel.warning);
          }
        }
      }

      // Check service status
      final statusResult =
          await sshClient.executeCommand(connection, rule.statusCommand);
      logs.add(
          'Status: ${rule.statusCommand} -> exit ${statusResult.exitCode}');

      // Record successful restart
      _recordRestart(restartKey);

      final duration = DateTime.now().difference(startTime);
      final message =
          '${sshClient.logOnly ? 'Simulated' : 'Executed'} service restart: ${rule.systemdServiceName} on ${connection.host} (${duration.inSeconds}s)';

      session.log(message, level: LogLevel.info);

      // Broadcast success to WebSocket clients
      LogBroadcaster.broadcastLog('✅ $message');

      return RestartResult(
        success: true,
        serviceName: rule.systemdServiceName,
        host: connection.host,
        duration: duration,
        message: message,
        logs: logs,
        wasSimulated: sshClient.logOnly,
      );
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      final message =
          'Service restart error: ${rule.systemdServiceName} on ${connection.host}: $e';

      session.log('$message\nStack trace: $stackTrace', level: LogLevel.error);

      LogBroadcaster.broadcastLog('❌ $message');

      return RestartResult(
        success: false,
        serviceName: rule.systemdServiceName,
        host: connection.host,
        duration: duration,
        message: message,
        wasSimulated: sshClient.logOnly,
      );
    }
  }

  /// Check service status without restarting
  Future<Map<String, dynamic>> checkServiceStatus(
    String serviceName,
    SshConnection connection,
  ) async {
    try {
      session.log('Checking status: $serviceName on ${connection.host}',
          level: LogLevel.info);

      final statusCommand = 'sudo systemctl status $serviceName';
      final result = await sshClient.executeCommand(connection, statusCommand);

      return {
        'success': result.isSuccess,
        'serviceName': serviceName,
        'host': connection.host,
        'exitCode': result.exitCode,
        'output': result.stdout,
        'error': result.stderr,
        'wasSimulated': sshClient.logOnly,
      };
    } catch (e) {
      session.log('Error checking service status: $e', level: LogLevel.error);
      return {
        'success': false,
        'serviceName': serviceName,
        'host': connection.host,
        'error': e.toString(),
        'wasSimulated': sshClient.logOnly,
      };
    }
  }

  /// Check if restart is allowed based on simple counter limit
  bool _canRestart(RestartRule rule, String restartKey) {
    final history = _restartHistory[restartKey] ?? [];

    // Simple counter check - compare against maxRestarts limit
    return history.length < rule.maxRestarts;
  }

  /// Record a restart attempt
  void _recordRestart(String restartKey) {
    final now = DateTime.now();
    _lastRestartAttempt[restartKey] = now;

    final history = _restartHistory[restartKey] ?? [];
    history.add(now);
    _restartHistory[restartKey] = history;

    // Note: History is reset by resetRestartCounter when state changes from CRITICAL to OK
  }

  /// Reset restart counter when Icinga state changes from CRITICAL to OK
  void resetRestartCounter(String host, String serviceName) {
    final restartKey = '${host}_$serviceName';
    _restartHistory.remove(restartKey);
    _lastRestartAttempt.remove(restartKey);

    session.log(
      'Reset restart counter for $serviceName on $host (state changed from CRITICAL to OK)',
      level: LogLevel.info,
    );

    LogBroadcaster.broadcastLog(
        '🔄 Reset restart counter: $serviceName on $host (service recovered)');
  }

  /// Get restart statistics for monitoring
  Map<String, dynamic> getRestartStats() {
    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final oneDayAgo = now.subtract(const Duration(hours: 24));

    int restartsLastHour = 0;
    int restartsLastDay = 0;

    for (final history in _restartHistory.values) {
      restartsLastHour +=
          history.where((time) => time.isAfter(oneHourAgo)).length;
      restartsLastDay +=
          history.where((time) => time.isAfter(oneDayAgo)).length;
    }

    return {
      'restartsLastHour': restartsLastHour,
      'restartsLastDay': restartsLastDay,
      'totalServices': _restartHistory.length,
      'logOnlyMode': sshClient.logOnly,
    };
  }

  /// Clear restart history (for testing or maintenance)
  void clearHistory() {
    _restartHistory.clear();
    _lastRestartAttempt.clear();
    session.log('Service restart history cleared', level: LogLevel.info);
  }
}

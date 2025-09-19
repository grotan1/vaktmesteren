import 'dart:async';
import 'package:serverpod/serverpod.dart';
import '../clients/ssh_client.dart';
import '../models/ssh_connection.dart';
import '../models/restart_rule.dart';
import '../../web/routes/log_viewer.dart';

/// Information for pending restart retries
class PendingRetry {
  final RestartRule rule;
  final SshConnection connection;
  final String icingaServiceName;
  final DateTime scheduledTime;
  Timer? timer;

  PendingRetry({
    required this.rule,
    required this.connection,
    required this.icingaServiceName,
    required this.scheduledTime,
    this.timer,
  });
}

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
  final Map<String, PendingRetry> _pendingRetries = {};

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
        final cooldownRemaining =
            rule.cooldownPeriod - DateTime.now().difference(lastRestart);
        final message =
            'Restart in cooldown: ${rule.systemdServiceName} on ${connection.host} (${rule.cooldownPeriod.inMinutes}min cooldown)';
        session.log(message, level: LogLevel.warning);

        LogBroadcaster.broadcastLog('⏸️ $message');

        // Schedule automatic retry after cooldown expires
        _scheduleRetryAfterCooldown(
            rule, connection, icingaServiceName, cooldownRemaining);

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

      // Check if service is enabled, and enable if necessary
      session.log('Checking if service is enabled...', level: LogLevel.info);
      final enabledCheckResult =
          await sshClient.executeCommand(connection, rule.isEnabledCommand);
      logs.add(
          'Enabled check: ${rule.isEnabledCommand} -> exit ${enabledCheckResult.exitCode}, output: "${enabledCheckResult.stdout.trim()}"');

      final serviceEnabledState =
          enabledCheckResult.stdout.trim().toLowerCase();

      // Service is considered enabled if state is 'enabled' or 'enabled-runtime'
      // Some services might return 'static', 'indirect', etc. which don't need enabling
      final isServiceEnabled = serviceEnabledState == 'enabled' ||
          serviceEnabledState == 'enabled-runtime' ||
          serviceEnabledState == 'static' ||
          serviceEnabledState == 'indirect';

      if (!isServiceEnabled) {
        session.log(
            'Service ${rule.systemdServiceName} is disabled (state: $serviceEnabledState), enabling it...',
            level: LogLevel.warning);

        LogBroadcaster.broadcastLog(
            '⚙️ Service disabled: ${rule.systemdServiceName} on ${connection.host}, enabling...');

        final enableResult =
            await sshClient.executeCommand(connection, rule.enableCommand);
        logs.add(
            'Enable: ${rule.enableCommand} -> exit ${enableResult.exitCode}');

        // systemctl enable can return exit 1 if service is already enabled
        // Check both exit code success AND stderr/stdout content to determine actual success
        final enableOutput = enableResult.stdout.toLowerCase();
        final enableError = enableResult.stderr.toLowerCase();

        session.log(
            'Enable command details: exitCode=${enableResult.exitCode}, stdout="${enableResult.stdout.trim()}", stderr="${enableResult.stderr.trim()}"',
            level: LogLevel.debug);

        bool isEnableSuccess = enableResult.isSuccess ||
            enableError.contains('already enabled') ||
            enableError.contains('unit files have no installation config') ||
            enableError
                .contains('the unit files have no installation config') ||
            enableError.contains('static unit') ||
            enableError.contains('masked') ||
            enableOutput.contains('created symlink') ||
            enableOutput.contains('already enabled') ||
            enableOutput.contains('symlink already exists');

        // If enable command returned exit code 1 but we haven't detected success yet,
        // verify with 'systemctl is-enabled' as final check since exit code 1 can
        // be returned for already-enabled services on some systemd versions
        if (!isEnableSuccess && enableResult.exitCode == 1) {
          session.log(
              'Enable returned exit code 1, verifying actual enable status...',
              level: LogLevel.debug);

          final verifyResult =
              await sshClient.executeCommand(connection, rule.isEnabledCommand);
          final verifyState = verifyResult.stdout.trim().toLowerCase();

          session.log(
              'Verification check: exitCode=${verifyResult.exitCode}, stdout="${verifyState}"',
              level: LogLevel.debug);

          // If service is actually enabled, then the enable operation was successful
          if (verifyState == 'enabled' ||
              verifyState == 'static' ||
              verifyState == 'enabled-runtime') {
            isEnableSuccess = true;
            session.log(
                'Verification confirms ${rule.systemdServiceName} is enabled (${verifyState})',
                level: LogLevel.debug);
          }
        }

        if (isEnableSuccess) {
          session.log('Successfully enabled ${rule.systemdServiceName}',
              level: LogLevel.info);
          LogBroadcaster.broadcastLog(
              '✅ Service enabled: ${rule.systemdServiceName} on ${connection.host}');
        } else {
          session.log(
              'Failed to enable ${rule.systemdServiceName}: exitCode=${enableResult.exitCode}, stderr="${enableResult.stderr.trim()}", stdout="${enableResult.stdout.trim()}"',
              level: LogLevel.warning);
          LogBroadcaster.broadcastLog(
              '❌ Failed to enable service: ${rule.systemdServiceName} on ${connection.host} (exit ${enableResult.exitCode})');
          // Continue with restart attempt even if enable failed
        }
      } else {
        session.log('Service ${rule.systemdServiceName} is already enabled',
            level: LogLevel.info);
      }

      // Execute the restart command
      session.log('Executing restart command: ${rule.restartCommand}',
          level: LogLevel.info);
      final restartResult =
          await sshClient.executeCommand(connection, rule.restartCommand);
      logs.add(
          'Restart: ${rule.restartCommand} -> exit ${restartResult.exitCode}');

      // Log restart command result, but don't fail immediately based on exit code
      // Some services may return non-zero exit codes but still restart successfully
      if (restartResult.isFailure) {
        session.log(
            'Restart command returned exit code ${restartResult.exitCode}, but continuing to verify service status',
            level: LogLevel.warning);
        logs.add(
            'Warning: Restart command exit ${restartResult.exitCode}, checking actual service status');
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

      // Check service status - this is the final determinant of success
      // Use is-active instead of status for more reliable running state detection
      final statusResult =
          await sshClient.executeCommand(connection, rule.isActiveCommand);
      logs.add(
          'Active check: ${rule.isActiveCommand} -> exit ${statusResult.exitCode}, output: "${statusResult.stdout.trim()}"');

      // Also get detailed status for logging purposes (but don't use for success determination)
      final detailedStatusResult =
          await sshClient.executeCommand(connection, rule.statusCommand);
      logs.add(
          'Status: ${rule.statusCommand} -> exit ${detailedStatusResult.exitCode}');

      // Determine final success based on service being active
      // Prioritize stdout content over exit code since systemctl is-active can have inconsistent exit codes
      final serviceState = statusResult.stdout.trim().toLowerCase();
      final isServiceRunning = serviceState == 'active';
      final duration = DateTime.now().difference(startTime);

      session.log(
          'Service state determination: stdout="$serviceState", isActive=$isServiceRunning, exitCode=${statusResult.exitCode}',
          level: LogLevel.info);

      if (isServiceRunning) {
        // Service is running - consider this a success even if restart command had non-zero exit
        _recordRestart(restartKey);

        final message =
            '${sshClient.logOnly ? 'Simulated' : 'Executed'} service restart: ${rule.systemdServiceName} on ${connection.host} (${duration.inSeconds}s)';

        session.log(message, level: LogLevel.info);

        // Include warning if restart command failed but service is now running
        if (restartResult.isFailure) {
          final warningMessage =
              'Note: Restart command returned exit ${restartResult.exitCode}, but service is now running successfully';
          session.log(warningMessage, level: LogLevel.info);
          logs.add(warningMessage);
        }

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
      } else {
        // Service is not running - this is a genuine failure
        final actualState = statusResult.stdout.trim();
        final message =
            'Service restart failed: ${rule.systemdServiceName} state is "$actualState" (expected "active") after restart attempt (exit ${statusResult.exitCode})';

        session.log(message, level: LogLevel.error);
        LogBroadcaster.broadcastLog('❌ $message');

        return RestartResult(
          success: false,
          serviceName: rule.systemdServiceName,
          host: connection.host,
          duration: duration,
          message: message,
          logs: logs,
          wasSimulated: sshClient.logOnly,
        );
      }
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

    // Cancel any pending retries since the service has recovered
    cancelPendingRetry(host, serviceName);

    session.log(
      'Reset restart counter for $serviceName on $host (state changed from CRITICAL to OK)',
      level: LogLevel.info,
    );

    LogBroadcaster.broadcastLog(
        '🔄 RECOVERY Reset restart counter: $serviceName on $host (service recovered)');
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
    // Cancel all pending retries
    for (final retry in _pendingRetries.values) {
      retry.timer?.cancel();
    }
    _pendingRetries.clear();
    session.log('Service restart history cleared', level: LogLevel.info);
  }

  /// Schedule a retry attempt after cooldown period expires
  void _scheduleRetryAfterCooldown(RestartRule rule, SshConnection connection,
      String icingaServiceName, Duration cooldownRemaining) {
    final retryKey = '${connection.host}:${rule.systemdServiceName}';

    // Cancel any existing retry for this service
    _pendingRetries[retryKey]?.timer?.cancel();

    // Add a small buffer to ensure cooldown has fully expired
    final retryDelay = cooldownRemaining + const Duration(seconds: 5);
    final scheduledTime = DateTime.now().add(retryDelay);

    final timer = Timer(retryDelay, () async {
      // Remove from pending retries
      _pendingRetries.remove(retryKey);

      session.log(
          'Attempting scheduled retry for ${rule.systemdServiceName} on ${connection.host}',
          level: LogLevel.info);

      LogBroadcaster.broadcastLog(
          '🔄 Retry attempt: ${rule.systemdServiceName} on ${connection.host} (cooldown expired)');

      // Attempt the restart
      try {
        final result =
            await restartService(rule, connection, icingaServiceName);

        if (result.success) {
          LogBroadcaster.broadcastLog(
              '✅ Scheduled retry successful: ${rule.systemdServiceName} on ${connection.host}');
        } else {
          LogBroadcaster.broadcastLog(
              '❌ Scheduled retry failed: ${result.message}');
        }
      } catch (e) {
        session.log('Error during scheduled retry: $e', level: LogLevel.error);
        LogBroadcaster.broadcastLog(
            '❌ Scheduled retry error: ${rule.systemdServiceName} on ${connection.host} - $e');
      }
    });

    final pendingRetry = PendingRetry(
      rule: rule,
      connection: connection,
      icingaServiceName: icingaServiceName,
      scheduledTime: scheduledTime,
      timer: timer,
    );

    _pendingRetries[retryKey] = pendingRetry;

    session.log(
        'Scheduled retry for ${rule.systemdServiceName} on ${connection.host} at ${scheduledTime.toLocal()}',
        level: LogLevel.info);

    LogBroadcaster.broadcastLog(
        '⏰ Retry scheduled: ${rule.systemdServiceName} on ${connection.host} in ${retryDelay.inMinutes}min ${retryDelay.inSeconds % 60}s');
  }

  /// Cancel pending retry for a service (called when service recovers)
  void cancelPendingRetry(String host, String serviceName) {
    final retryKey = '$host:$serviceName';
    final pendingRetry = _pendingRetries.remove(retryKey);

    if (pendingRetry != null) {
      pendingRetry.timer?.cancel();
      session.log(
          'Cancelled pending retry for $serviceName on $host (service recovered)',
          level: LogLevel.info);
      LogBroadcaster.broadcastLog(
          '✅ Retry cancelled: $serviceName on $host (service recovered)');
    }
  }

  /// Get information about pending retries (for monitoring/debugging)
  Map<String, dynamic> getPendingRetries() {
    final retries = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (final entry in _pendingRetries.entries) {
      final key = entry.key;
      final retry = entry.value;
      final timeRemaining = retry.scheduledTime.difference(now);

      retries.add({
        'key': key,
        'service': retry.rule.systemdServiceName,
        'host': retry.connection.host,
        'scheduledTime': retry.scheduledTime.toIso8601String(),
        'timeRemainingSeconds': timeRemaining.inSeconds,
      });
    }

    return {
      'pendingRetries': retries,
      'count': retries.length,
    };
  }
}

import 'package:test/test.dart';
import 'package:serverpod/serverpod.dart';
import 'package:vaktmesteren_server/src/ops/services/linux_service_restart_service.dart';
import 'package:vaktmesteren_server/src/ops/clients/ssh_client.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';

void main() {
  group('Service Enable Check Tests', () {
    late Session mockSession;
    late SshClient mockSshClient;
    late LinuxServiceRestartService restartService;

    setUp(() {
      mockSession = MockSession();
      mockSshClient = SshClient(mockSession, logOnly: true);
      restartService = LinuxServiceRestartService(mockSession, mockSshClient);
    });

    test('should check if service is enabled and enable if disabled', () async {
      final rule = RestartRule(
        systemdServiceName: 'test-disabled-service',
        maxRestarts: 3,
        cooldownPeriod: const Duration(seconds: 1),
      );

      final connection = SshConnection(
        name: 'test-connection',
        host: 'test-host',
        username: 'test-user',
        privateKeyPath: '/dev/null',
      );

      // Attempt restart - should detect service is disabled and enable it
      var result = await restartService.restartService(
          rule, connection, 'test_disabled_service');

      print('✅ Service enable check test completed');
      print('   Result: ${result.success ? 'SUCCESS' : 'FAILED'}');
      print('   Message: ${result.message}');
      print('   Logs:');
      for (final log in result.logs) {
        print('     - $log');
      }

      // Verify success
      expect(result.success, isTrue);

      // Verify logs contain enable check and enable operation
      final logString = result.logs.join(' ');
      expect(logString, contains('is-enabled'));
      expect(logString, contains('systemctl enable'));
    });

    test('should not enable service if already enabled', () async {
      final rule = RestartRule(
        systemdServiceName: 'already-enabled-service',
        maxRestarts: 3,
        cooldownPeriod: const Duration(seconds: 1),
      );

      final connection = SshConnection(
        name: 'test-connection',
        host: 'test-host',
        username: 'test-user',
        privateKeyPath: '/dev/null',
      );

      // Attempt restart - service should already be enabled
      var result = await restartService.restartService(
          rule, connection, 'already_enabled_service');

      print('✅ Already enabled service test completed');
      print('   Result: ${result.success ? 'SUCCESS' : 'FAILED'}');
      print('   Logs:');
      for (final log in result.logs) {
        print('     - $log');
      }

      // Verify success
      expect(result.success, isTrue);

      // Verify logs contain enable check but not enable operation
      final logString = result.logs.join(' ');
      expect(logString, contains('is-enabled'));
      expect(logString, isNot(contains('systemctl enable')));
    });
  });
}

/// Mock session for testing
class MockSession implements Session {
  @override
  void log(String message,
      {LogLevel? level, dynamic exception, StackTrace? stackTrace}) {
    print('LOG [${level?.name}]: $message');
  }

  // Implement other required Session methods with minimal implementations
  @override
  noSuchMethod(Invocation invocation) => null;
}

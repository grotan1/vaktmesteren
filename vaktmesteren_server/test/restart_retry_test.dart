import 'package:test/test.dart';
import 'package:serverpod/serverpod.dart';
import '../lib/src/ops/services/linux_service_restart_service.dart';
import '../lib/src/ops/clients/ssh_client.dart';
import '../lib/src/ops/models/restart_rule.dart';
import '../lib/src/ops/models/ssh_connection.dart';

void main() {
  group('LinuxServiceRestartService Retry Tests', () {
    late Session mockSession;
    late SshClient mockSshClient;
    late LinuxServiceRestartService restartService;

    setUp(() {
      mockSession = MockSession();
      mockSshClient = SshClient(mockSession, logOnly: true);
      restartService = LinuxServiceRestartService(mockSession, mockSshClient);
    });

    test('should schedule retry after cooldown failure', () async {
      final rule = RestartRule(
        systemdServiceName: 'test-service',
        maxRestarts: 3,
        cooldownPeriod: const Duration(seconds: 5), // Short for testing
      );

      final connection = SshConnection(
        name: 'test-connection',
        host: 'test-host',
        username: 'test-user',
        privateKeyPath: '/dev/null',
      );

      // First restart - should succeed
      var result1 =
          await restartService.restartService(rule, connection, 'test_service');
      expect(result1.success, isTrue);

      // Second restart immediately - should fail due to cooldown
      var result2 =
          await restartService.restartService(rule, connection, 'test_service');
      expect(result2.success, isFalse);
      expect(result2.message, contains('cooldown'));

      // Check that a retry is scheduled
      final retryInfo = restartService.getPendingRetries();
      expect(retryInfo['count'], equals(1));
      expect(retryInfo['pendingRetries'][0]['service'], equals('test-service'));
      expect(retryInfo['pendingRetries'][0]['host'], equals('test-host'));

      print('✅ Retry scheduled successfully');
      print('   Service: test-service on test-host');
      print('   Pending retries: ${retryInfo['count']}');
    });

    test('should cancel retry when service recovers', () async {
      final rule = RestartRule(
        systemdServiceName: 'recovery-test-service',
        maxRestarts: 3,
        cooldownPeriod: const Duration(minutes: 10), // Long cooldown
      );

      final connection = SshConnection(
        name: 'recovery-connection',
        host: 'recovery-host',
        username: 'test-user',
        privateKeyPath: '/dev/null',
      );

      // First restart
      await restartService.restartService(
          rule, connection, 'recovery_test_service');

      // Second restart - should fail due to cooldown and schedule retry
      var result = await restartService.restartService(
          rule, connection, 'recovery_test_service');
      expect(result.success, isFalse);

      // Verify retry is scheduled
      var retryInfo = restartService.getPendingRetries();
      expect(retryInfo['count'], equals(1));

      // Simulate service recovery
      restartService.resetRestartCounter(
          'recovery-host', 'recovery-test-service');

      // Verify retry is cancelled
      retryInfo = restartService.getPendingRetries();
      expect(retryInfo['count'], equals(0));

      print('✅ Retry cancelled on service recovery');
      print('   Pending retries after recovery: ${retryInfo['count']}');
    });

    test('should clear all retries when history is cleared', () async {
      final rule = RestartRule(
        systemdServiceName: 'clear-test-service',
        maxRestarts: 3,
        cooldownPeriod: const Duration(minutes: 10),
      );

      final connection = SshConnection(
        name: 'clear-connection',
        host: 'clear-host',
        username: 'test-user',
        privateKeyPath: '/dev/null',
      );

      // Create multiple services with pending retries
      await restartService.restartService(
          rule, connection, 'clear_test_service_1');
      await restartService.restartService(
          rule, connection, 'clear_test_service_1'); // Creates retry

      var retryInfo = restartService.getPendingRetries();
      expect(retryInfo['count'], greaterThan(0));

      // Clear history
      restartService.clearHistory();

      // Verify all retries are cancelled
      retryInfo = restartService.getPendingRetries();
      expect(retryInfo['count'], equals(0));

      print('✅ All retries cleared successfully');
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

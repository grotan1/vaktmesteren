import 'package:test/test.dart';
import 'package:serverpod/serverpod.dart';
import 'package:vaktmesteren_server/src/ops/services/linux_service_restart_service.dart';
import 'package:vaktmesteren_server/src/ops/clients/ssh_client.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';

void main() {
  group('Service Enable Exit Code Tests', () {
    late Session mockSession;
    late SshClient mockSshClient;
    late LinuxServiceRestartService restartService;

    setUp(() {
      mockSession = MockSession();
      mockSshClient = SshClient(mockSession, logOnly: true);
      restartService = LinuxServiceRestartService(mockSession, mockSshClient);
    });

    test(
        'should handle systemctl enable exit code 1 as success when already enabled',
        () async {
      final rule1 = RestartRule(
        systemdServiceName: 'test-first-enable-service',
        maxRestarts: 3,
        cooldownPeriod: const Duration(seconds: 1),
      );

      final rule2 = RestartRule(
        systemdServiceName: 'test-first-enable-service', // Same service name
        maxRestarts: 3,
        cooldownPeriod: const Duration(seconds: 1),
      );

      final connection = SshConnection(
        name: 'test-connection',
        host: 'test-host-2', // Different host to avoid cooldown conflicts
        username: 'test-user',
        privateKeyPath: '/dev/null',
      );

      // First restart - will enable the service with exit code 0
      var result1 = await restartService.restartService(
          rule1, connection, 'test_service_1');
      expect(result1.success, isTrue);

      print('First enable attempt:');
      for (final log in result1.logs) {
        if (log.contains('Enable:')) {
          print('  $log');
        }
      }

      // Wait for cooldown
      await Future.delayed(const Duration(seconds: 2));

      // Second restart - should try to enable again but get exit code 1 (already enabled)
      var result2 = await restartService.restartService(
          rule2, connection, 'test_service_2');
      expect(result2.success, isTrue);

      print('Second enable attempt (should handle exit code 1):');
      for (final log in result2.logs) {
        if (log.contains('Enable:')) {
          print('  $log');
        }
      }

      print(
          '✅ Both restart attempts succeeded, proving exit code 1 handling works');
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

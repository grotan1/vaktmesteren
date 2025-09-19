import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';

void main() {
  group('Auto-detected Service Rule Lookup Tests', () {
    test('should find restart rule by systemd service name', () {
      final rules = [
        RestartRule(
          systemdServiceName: 'nginx',
          sshConnectionName: 'web-server',
          enabled: true,
          maxRestarts: 3,
          cooldownPeriod: const Duration(minutes: 10),
          preChecks: ['sudo nginx -t'],
          postChecks: ['sudo systemctl is-active nginx'],
        ),
        RestartRule(
          systemdServiceName: 'ser2net',
          sshConnectionName: 'ghrunner-server',
          enabled: true,
          maxRestarts: 2,
          cooldownPeriod: const Duration(minutes: 15),
          preChecks: [
            'sudo systemctl is-failed ser2net || true',
            'sudo netstat -ln | grep :2000 || true'
          ],
          postChecks: [
            'sudo systemctl is-active ser2net',
            'sleep 3 && sudo netstat -ln | grep :2000'
          ],
        ),
        RestartRule(
          systemdServiceName: 'apache2',
          sshConnectionName: 'web-server',
          enabled: false, // Disabled rule should not be returned
          maxRestarts: 3,
          cooldownPeriod: const Duration(minutes: 10),
          preChecks: [],
          postChecks: ['sudo systemctl is-active apache2'],
        ),
      ];

      final config = SshRestartConfig(
        connections: {},
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      // Test finding an existing rule
      final ser2netRule = config.findRuleBySystemdService('ser2net');
      expect(ser2netRule, isNotNull);
      expect(ser2netRule!.systemdServiceName, equals('ser2net'));
      expect(ser2netRule.sshConnectionName, equals('ghrunner-server'));
      expect(ser2netRule.maxRestarts, equals(2));
      expect(ser2netRule.cooldownPeriod, equals(const Duration(minutes: 15)));
      expect(ser2netRule.preChecks, hasLength(2));
      expect(ser2netRule.postChecks, hasLength(2));

      print('✅ Found ser2net rule with correct configuration');
      print('   Max restarts: ${ser2netRule.maxRestarts} attempts');
      print('   Cooldown: ${ser2netRule.cooldownPeriod.inMinutes} minutes');
      print('   Pre-checks: ${ser2netRule.preChecks.length}');
      print('   Post-checks: ${ser2netRule.postChecks.length}');
    });

    test('should return null for non-existent systemd service', () {
      final rules = [
        RestartRule(
          systemdServiceName: 'nginx',
          sshConnectionName: 'web-server',
          enabled: true,
          maxRestarts: 3,
          cooldownPeriod: const Duration(minutes: 10),
          preChecks: [],
          postChecks: [],
        ),
      ];

      final config = SshRestartConfig(
        connections: {},
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      final nonExistentRule = config.findRuleBySystemdService('non-existent');
      expect(nonExistentRule, isNull);

      print('✅ Correctly returned null for non-existent service');
    });

    test('should only return enabled rules', () {
      final rules = [
        RestartRule(
          systemdServiceName: 'disabled-service',
          sshConnectionName: 'web-server',
          enabled: false, // Disabled
          maxRestarts: 3,
          cooldownPeriod: const Duration(minutes: 10),
          preChecks: [],
          postChecks: [],
        ),
      ];

      final config = SshRestartConfig(
        connections: {},
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      final disabledRule = config.findRuleBySystemdService('disabled-service');
      expect(disabledRule, isNull);

      print('✅ Correctly filtered out disabled rules');
    });

    test('should demonstrate the auto-detection workflow', () {
      // Create test configuration that mimics the actual ssh_restart.yaml
      final rules = [
        RestartRule(
          systemdServiceName: 'ser2net',
          sshConnectionName: 'ghrunner-server',
          enabled: true,
          maxRestarts: 2,
          cooldownPeriod: const Duration(minutes: 15),
          preChecks: [
            'sudo systemctl is-failed ser2net || true',
            'sudo netstat -ln | grep :2000 || true'
          ],
          postChecks: [
            'sudo systemctl is-active ser2net',
            'sleep 3 && sudo netstat -ln | grep :2000'
          ],
        ),
      ];

      final config = SshRestartConfig(
        connections: {},
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      // Simulate the auto-detection workflow
      const systemdUnitName =
          'ser2net'; // From Icinga2 systemd_unit_unit variable
      final foundRule = config.findRuleBySystemdService(systemdUnitName);

      expect(foundRule, isNotNull);
      expect(foundRule!.sshConnectionName, equals('ghrunner-server'));

      print('✅ Complete auto-detection workflow test passed');
      print('   Input: systemd_unit_unit = "$systemdUnitName"');
      print('   Found rule: ${foundRule.systemdServiceName}');
      print('   SSH target: ${foundRule.sshConnectionName}');
      print(
          '   Throttling: ${foundRule.maxRestarts} attempts, ${foundRule.cooldownPeriod.inMinutes}min cooldown');
      print('   Pre-checks: ${foundRule.preChecks.join(', ')}');
      print('   Post-checks: ${foundRule.postChecks.join(', ')}');
    });
  });
}

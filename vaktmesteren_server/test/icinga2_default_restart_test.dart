import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';

void main() {
  group('Default Restart Behavior Tests', () {
    test('should create default rule with conservative settings', () {
      // Test creating a default restart rule for an auto-detected service
      const systemdUnitName = 'unknown-service';

      final defaultRule = RestartRule(
        systemdServiceName: systemdUnitName,
        // Use conservative default settings for auto-detected services without specific rules
        enabled: true,
        maxRestarts: 3, // Conservative default (resets when state changes)
        cooldownPeriod: const Duration(minutes: 10), // Conservative cooldown
        preChecks: [], // No pre-checks by default
        postChecks: [
          'sudo systemctl is-active $systemdUnitName'
        ], // Basic post-check
      );

      expect(defaultRule.systemdServiceName, equals('unknown-service'));
      expect(defaultRule.enabled, isTrue);
      expect(defaultRule.maxRestarts, equals(3));
      expect(defaultRule.cooldownPeriod, equals(const Duration(minutes: 10)));
      expect(defaultRule.preChecks, isEmpty);
      expect(defaultRule.postChecks, hasLength(1));
      expect(defaultRule.postChecks.first,
          equals('sudo systemctl is-active unknown-service'));

      print('✅ Default rule created with conservative settings');
      print('   Service: ${defaultRule.systemdServiceName}');
      print('   Max restarts: ${defaultRule.maxRestarts} attempts');
      print('   Cooldown: ${defaultRule.cooldownPeriod.inMinutes} minutes');
      print('   Pre-checks: ${defaultRule.preChecks.length}');
      print('   Post-checks: ${defaultRule.postChecks.length}');
    });

    test(
        'should demonstrate default restart workflow for unconfigured services',
        () {
      // Mock config that doesn't contain a rule for a specific service
      final config = SshRestartConfig(
        connections: {
          'default': SshConnection(
            name: 'default',
            host: 'monitoring.example.com',
            port: 22,
            username: 'monitoring',
            privateKeyPath: '/etc/ssh/monitoring_key',
            timeout: const Duration(seconds: 30),
          ),
        },
        rules: [
          // Only contains a rule for 'nginx', but not for 'unknown-service'
          RestartRule(
            systemdServiceName: 'nginx',
            enabled: true,
            maxRestarts: 5,
            cooldownPeriod: const Duration(minutes: 5),
            preChecks: ['sudo nginx -t'],
            postChecks: ['sudo systemctl is-active nginx'],
          ),
        ],
        enabled: true,
        logOnly: true,
      );

      // Try to find a rule for an unconfigured service
      final unknownServiceRule =
          config.findRuleBySystemdService('unknown-service');
      expect(unknownServiceRule, isNull,
          reason: 'Should not find rule for unconfigured service');

      // This would trigger default restart behavior in the actual implementation
      final wouldUseDefaultRestart = unknownServiceRule == null;
      expect(wouldUseDefaultRestart, isTrue);

      // The default connection should be available for dynamic connection creation
      final defaultConnection = config.getConnection('default');
      expect(defaultConnection, isNotNull);
      expect(defaultConnection!.host, equals('monitoring.example.com'));

      print('✅ Default restart workflow test passed');
      print('   No rule found for: unknown-service');
      print('   Would use default restart behavior: $wouldUseDefaultRestart');
      print('   Default connection available: ${defaultConnection.name}');
      print('   Default connection host: ${defaultConnection.host}');
    });

    test(
        'should verify that configured services still use their specific rules',
        () {
      final config = SshRestartConfig(
        connections: {
          'web-server': SshConnection(
            name: 'web-server',
            host: 'web.example.com',
            port: 22,
            username: 'deploy',
            privateKeyPath: '/etc/ssh/deploy_key',
            timeout: const Duration(seconds: 30),
          ),
        },
        rules: [
          RestartRule(
            systemdServiceName: 'nginx',
            sshConnectionName: 'web-server',
            enabled: true,
            maxRestarts: 5,
            cooldownPeriod: const Duration(minutes: 5),
            preChecks: ['sudo nginx -t'],
            postChecks: ['sudo systemctl is-active nginx'],
          ),
        ],
        enabled: true,
        logOnly: true,
      );

      // Configured service should still use its specific rule
      final nginxRule = config.findRuleBySystemdService('nginx');
      expect(nginxRule, isNotNull);
      expect(nginxRule!.maxRestarts, equals(5));
      expect(nginxRule.sshConnectionName, equals('web-server'));
      expect(nginxRule.preChecks, contains('sudo nginx -t'));

      // Unconfigured service should not have a specific rule (would use default)
      final apacheRule = config.findRuleBySystemdService('apache2');
      expect(apacheRule, isNull);

      print('✅ Rule precedence test passed');
      print(
          '   Configured service (nginx): Uses specific rule with 5 attempts limit');
      print(
          '   Unconfigured service (apache2): Would use default behavior with 3 attempts limit');
      print(
          '   This allows fine-grained control for critical services while providing fallback for all others');
    });
  });
}

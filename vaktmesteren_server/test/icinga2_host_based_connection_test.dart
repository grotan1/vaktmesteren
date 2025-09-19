import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';

void main() {
  group('Host-based SSH Connection Selection Tests', () {
    test('should find SSH connection by exact hostname match', () {
      final connections = {
        'server1': SshConnection(
          name: 'server1',
          host: 'example.com',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/key',
        ),
        'ghrunner.grsoft.no': SshConnection(
          name: 'ghrunner.grsoft.no',
          host: 'ghrunner.grsoft.no',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/key',
        ),
      };

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: [],
        enabled: true,
        logOnly: true,
      );

      // Test exact hostname match
      final connection = sshConfig.getConnectionByHost('ghrunner.grsoft.no');
      expect(connection, isNotNull);
      expect(connection!.host, equals('ghrunner.grsoft.no'));
      expect(connection.name, equals('ghrunner.grsoft.no'));

      print('✅ Found connection by exact hostname match');
      print('   Host: ${connection.host}');
      print('   Connection name: ${connection.name}');
    });

    test(
        'should find SSH connection by connection name when hostname not found',
        () {
      final connections = {
        'ghrunner-server': SshConnection(
          name: 'ghrunner-server',
          host: 'ghrunner.grsoft.no',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/key',
        ),
      };

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: [],
        enabled: true,
        logOnly: true,
      );

      // Test connection name fallback
      final connection = sshConfig.getConnectionByHost('ghrunner-server');
      expect(connection, isNotNull);
      expect(connection!.host, equals('ghrunner.grsoft.no'));
      expect(connection.name, equals('ghrunner-server'));

      print('✅ Found connection by connection name fallback');
      print('   Requested host: ghrunner-server');
      print('   Actual host: ${connection.host}');
      print('   Connection name: ${connection.name}');
    });

    test('should return null for non-existent hostname', () {
      final connections = {
        'server1': SshConnection(
          name: 'server1',
          host: 'example.com',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/key',
        ),
      };

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: [],
        enabled: true,
        logOnly: true,
      );

      final connection = sshConfig.getConnectionByHost('non-existent.com');
      expect(connection, isNull);

      print('✅ Correctly returned null for non-existent hostname');
    });

    test(
        'should demonstrate complete auto-detection workflow with host mapping',
        () {
      // Simulate your Icinga2 example:
      // Host: ghrunner.grsoft.no
      // Service vars: { systemd_unit_unit: "ser2net", auto_restart_service_linux: true }

      final icingaHostName = 'ghrunner.grsoft.no';
      final serviceVars = {
        'auto_restart_service_linux': true,
        'systemd_unit_unit': 'ser2net',
        'systemd_unit_activestate': ['active'],
        'systemd_unit_loadstate': 'loaded',
        'systemd_unit_severity': 'crit',
        'systemd_unit_substate': ['running'],
      };

      // Create SSH connections (including host-based mapping)
      final connections = {
        'ghrunner-server': SshConnection(
          name: 'ghrunner-server',
          host: 'ghrunner.grsoft.no',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/monitoring_key',
        ),
        'ghrunner.grsoft.no': SshConnection(
          name: 'ghrunner.grsoft.no',
          host: 'ghrunner.grsoft.no',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/monitoring_key',
        ),
      };

      // Create restart rules with "auto" connection
      final rules = [
        RestartRule(
          icingaServicePattern: '*',
          systemdServiceName: 'ser2net',
          sshConnectionName: 'auto', // Special value for host-based lookup
          enabled: true,
          maxRestarts: 2,
          cooldownPeriod: Duration(minutes: 15),
          preChecks: [
            'sudo systemctl is-failed ser2net || true',
            'sudo netstat -ln | grep :2000 || true',
          ],
          postChecks: [
            'sudo systemctl is-active ser2net',
            'sleep 3 && sudo netstat -ln | grep :2000',
          ],
        ),
      ];

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      // Workflow simulation

      // 1. Extract systemd unit name from service variables
      final systemdUnitName = serviceVars['systemd_unit_unit'] as String?;
      expect(systemdUnitName, equals('ser2net'));

      // 2. Find restart rule by systemd service name
      final foundRule = sshConfig.findRuleBySystemdService(systemdUnitName!);
      expect(foundRule, isNotNull);
      expect(foundRule!.sshConnectionName, equals('auto'));

      // 3. Resolve SSH connection (this simulates the logic in _executeAutomaticRestart)
      SshConnection? connection;
      if (foundRule.sshConnectionName == 'auto') {
        connection = sshConfig.getConnectionByHost(icingaHostName);
      } else {
        connection = sshConfig.getConnection(foundRule.sshConnectionName);
      }

      expect(connection, isNotNull);
      expect(connection!.host, equals('ghrunner.grsoft.no'));

      print('✅ Complete host-based auto-detection workflow test passed');
      print('   Icinga2 host: $icingaHostName');
      print('   systemd_unit_unit: $systemdUnitName');
      print('   Rule connection: ${foundRule.sshConnectionName}');
      print(
          '   Resolved SSH connection: ${connection.name} -> ${connection.host}');
      print(
          '   Rule settings: ${foundRule.maxRestarts} attempts, ${foundRule.cooldownPeriod.inMinutes}min cooldown');
      print('   Pre-checks: ${foundRule.preChecks.length}');
      print('   Post-checks: ${foundRule.postChecks.length}');
    });

    test(
        'should handle fallback when host-based connection not found but rule exists',
        () {
      final connections = {
        'default': SshConnection(
          name: 'default',
          host: 'fallback-server.com',
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/key',
        ),
      };

      final rules = [
        RestartRule(
          icingaServicePattern: '*',
          systemdServiceName: 'test-service',
          sshConnectionName: 'auto',
          enabled: true,
        ),
      ];

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      // Simulate looking for a host that doesn't have a specific connection
      final connection = sshConfig.getConnectionByHost('unknown-host.com');
      expect(connection, isNull);

      // In real implementation, this would fall back to default connection
      final defaultConnection = sshConfig.getConnection('default');
      expect(defaultConnection, isNotNull);

      print('✅ Fallback behavior test passed');
      print('   No connection found for unknown-host.com');
      print('   Would fall back to default: ${defaultConnection!.name}');
    });
  });
}

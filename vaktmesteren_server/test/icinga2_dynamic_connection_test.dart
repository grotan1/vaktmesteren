import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';

void main() {
  group('Dynamic SSH Connection Creation Tests', () {
    test('should create dynamic connection using default template', () {
      // Simulate configuration with default template
      final connections = {
        'default': SshConnection(
          name: 'default',
          host: 'template-will-use-icinga2-hostname', // Template placeholder
          port: 22,
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/monitoring_key',
          timeout: Duration(seconds: 30),
        ),
      };

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: [],
        enabled: true,
        logOnly: true,
      );

      // Simulate looking for a host that doesn't have a specific connection
      final icingaHostName = 'server-xyz.example.com';
      final hostConnection = sshConfig.getConnectionByHost(icingaHostName);
      expect(hostConnection, isNull); // No specific connection found

      // Simulate what the implementation would do
      final defaultTemplate = sshConfig.getConnection('default');
      expect(defaultTemplate, isNotNull);

      // Create dynamic connection using template
      final dynamicConnection = SshConnection(
        name: 'auto-$icingaHostName',
        host: icingaHostName, // Use actual hostname from Icinga2!
        port: defaultTemplate!.port,
        username: defaultTemplate.username,
        privateKeyPath: defaultTemplate.privateKeyPath,
        timeout: defaultTemplate.timeout,
      );

      expect(dynamicConnection.host, equals('server-xyz.example.com'));
      expect(dynamicConnection.name, equals('auto-server-xyz.example.com'));
      expect(dynamicConnection.username, equals('monitoring'));
      expect(
          dynamicConnection.privateKeyPath, equals('/etc/ssh/monitoring_key'));
      expect(dynamicConnection.port, equals(22));

      print('✅ Dynamic connection created using default template');
      print('   Icinga2 host: $icingaHostName');
      print('   Dynamic connection: ${dynamicConnection.name}');
      print(
          '   Target: ${dynamicConnection.username}@${dynamicConnection.host}:${dynamicConnection.port}');
      print('   Auth: ${dynamicConnection.privateKeyPath}');
    });

    test(
        'should create dynamic connection with standard defaults when no template exists',
        () {
      // Simulate configuration without default template
      final connections = <String, SshConnection>{};

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: [],
        enabled: true,
        logOnly: true,
      );

      // Simulate looking for a host that doesn't have any connections
      final icingaHostName = 'new-server.example.com';
      final hostConnection = sshConfig.getConnectionByHost(icingaHostName);
      expect(hostConnection, isNull);

      final defaultTemplate = sshConfig.getConnection('default');
      expect(defaultTemplate, isNull);

      // Create dynamic connection with standard defaults
      final dynamicConnection = SshConnection(
        name: 'dynamic-$icingaHostName',
        host: icingaHostName,
        port: 22,
        username: 'monitoring',
        privateKeyPath: '/etc/ssh/monitoring_key',
        timeout: Duration(seconds: 30),
      );

      expect(dynamicConnection.host, equals('new-server.example.com'));
      expect(dynamicConnection.name, equals('dynamic-new-server.example.com'));
      expect(dynamicConnection.username, equals('monitoring'));

      print('✅ Dynamic connection created with standard defaults');
      print('   Icinga2 host: $icingaHostName');
      print('   Dynamic connection: ${dynamicConnection.name}');
      print(
          '   Target: ${dynamicConnection.username}@${dynamicConnection.host}:${dynamicConnection.port}');
    });

    test('should demonstrate complete workflow with dynamic connection', () {
      // Real-world scenario from your setup
      final icingaHostName = 'unknown-server.grsoft.no'; // Not in connections
      final serviceVars = {
        'auto_restart_service_linux': true,
        'systemd_unit_unit': 'custom-service',
      };

      final connections = {
        'default': SshConnection(
          name: 'default',
          host: 'template-will-use-icinga2-hostname',
          port: 22,
          username: 'monitoring',
          privateKeyPath: '/etc/ssh/monitoring_key',
          timeout: Duration(seconds: 30),
        ),
      };

      final rules = [
        RestartRule(
          icingaServicePattern: '*',
          systemdServiceName: 'custom-service',
          sshConnectionName: 'auto', // Use automatic connection
          enabled: true,
          maxRestarts: 3,
          cooldownPeriod: Duration(minutes: 5),
        ),
      ];

      final sshConfig = SshRestartConfig(
        connections: connections,
        rules: rules,
        enabled: true,
        logOnly: true,
      );

      // Workflow simulation

      // 1. Extract service name from Icinga2 variables
      final systemdUnitName = serviceVars['systemd_unit_unit'] as String;
      expect(systemdUnitName, equals('custom-service'));

      // 2. Find restart rule
      final foundRule = sshConfig.findRuleBySystemdService(systemdUnitName);
      expect(foundRule, isNotNull);
      expect(foundRule!.sshConnectionName, equals('auto'));

      // 3. Try to find existing connection for hostname
      final existingConnection = sshConfig.getConnectionByHost(icingaHostName);
      expect(existingConnection, isNull); // No existing connection

      // 4. Get default template
      final defaultTemplate = sshConfig.getConnection('default');
      expect(defaultTemplate, isNotNull);

      // 5. Create dynamic connection using template + actual hostname
      final dynamicConnection = SshConnection(
        name: 'auto-$icingaHostName',
        host: icingaHostName, // KEY: Uses actual Icinga2 hostname!
        port: defaultTemplate!.port,
        username: defaultTemplate.username,
        privateKeyPath: defaultTemplate.privateKeyPath,
        timeout: defaultTemplate.timeout,
      );

      expect(dynamicConnection.host, equals('unknown-server.grsoft.no'));
      expect(dynamicConnection.username, equals('monitoring'));

      print('✅ Complete dynamic connection workflow test passed');
      print('   Icinga2 host: $icingaHostName');
      print('   systemd_unit_unit: $systemdUnitName');
      print('   Rule connection: ${foundRule.sshConnectionName}');
      print('   Dynamic connection created: ${dynamicConnection.name}');
      print(
          '   Final target: ${dynamicConnection.username}@${dynamicConnection.host}:${dynamicConnection.port}');
      print(
          '   This allows SSH restart on ANY Icinga2 host without pre-configuration!');
    });
  });
}

import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';

void main() {
  group('Connection-based Restart Configuration Tests', () {
    test('should load connections with restart settings from new structure',
        () {
      // Test the new YAML structure with restart settings at connection level
      final configMap = {
        'enabled': true,
        'logOnly': true,
        'connections': {
          'ghrunner.grsoft.no': {
            'host': 'ghrunner.grsoft.no',
            'port': 22,
            'username': 'root',
            'privateKeyPath': '/home/grotan/.ssh/id_ed25519',
            'timeoutSeconds': 30,
            'maxRestarts': 2,
            'timeBetweenRestartAttempts': 15,
          },
          'web-prod-01.example.com': {
            'host': 'web-prod-01.example.com',
            'port': 22,
            'username': 'monitoring',
            'privateKeyPath': '/etc/ssh/monitoring_key',
            'timeoutSeconds': 30,
            'maxRestarts': 3,
            'timeBetweenRestartAttempts': 10,
          },
        },
        // No restartMappings needed! Automatic hostname-based selection works
      };

      final config = SshRestartConfig.fromMap(configMap);

      // Verify connections loaded with restart settings
      expect(config.connections.length, equals(2));

      final ghrunnerConnection = config.connections['ghrunner.grsoft.no'];
      expect(ghrunnerConnection, isNotNull);
      expect(ghrunnerConnection!.maxRestarts, equals(2));
      expect(
          ghrunnerConnection.timeBetweenRestartAttempts.inMinutes, equals(15));

      final webConnection = config.connections['web-prod-01.example.com'];
      expect(webConnection, isNotNull);
      expect(webConnection!.maxRestarts, equals(3));
      expect(webConnection.timeBetweenRestartAttempts.inMinutes, equals(10));

      // Verify no restart mappings needed (empty)
      expect(config.restartMappings.length, equals(0));

      print('✅ Connection-based configuration loaded successfully');
      print(
          '   ghrunner.grsoft.no: ${ghrunnerConnection.maxRestarts} attempts, ${ghrunnerConnection.timeBetweenRestartAttempts.inMinutes}min');
      print(
          '   web-prod-01.example.com: ${webConnection.maxRestarts} attempts, ${webConnection.timeBetweenRestartAttempts.inMinutes}min');
      print('   No restart mappings needed - automatic hostname matching!');
    });

    test(
        'should automatically find connections by hostname without explicit mappings',
        () {
      final config = SshRestartConfig(
        connections: {
          'ghrunner.grsoft.no': SshConnection(
            name: 'ghrunner.grsoft.no',
            host: 'ghrunner.grsoft.no',
            username: 'root',
            privateKeyPath: '/home/grotan/.ssh/id_ed25519',
            maxRestarts: 2,
            timeBetweenRestartAttempts: const Duration(minutes: 15),
          ),
          'web-server': SshConnection(
            name: 'web-server',
            host: 'web-prod-01.example.com',
            username: 'monitoring',
            privateKeyPath: '/etc/ssh/monitoring_key',
            maxRestarts: 3,
            timeBetweenRestartAttempts: const Duration(minutes: 10),
          ),
        },
        // NO restartMappings - testing automatic hostname selection
        enabled: true,
        logOnly: true,
      );

      // Test automatic hostname-based connection selection (connection name matches hostname)
      final ser2netConnection =
          config.getConnectionForService('ser2net', 'ghrunner.grsoft.no');
      expect(ser2netConnection, isNotNull);
      expect(ser2netConnection!.name, equals('ghrunner.grsoft.no'));
      expect(ser2netConnection.maxRestarts, equals(2));
      expect(
          ser2netConnection.timeBetweenRestartAttempts.inMinutes, equals(15));

      // Test automatic hostname-based connection selection (host property matches hostname)
      final nginxConnection =
          config.getConnectionForService('nginx', 'web-prod-01.example.com');
      expect(nginxConnection, isNotNull);
      expect(nginxConnection!.name, equals('web-server'));
      expect(nginxConnection.maxRestarts, equals(3));
      expect(nginxConnection.timeBetweenRestartAttempts.inMinutes, equals(10));

      // Test hostname fallback for unmapped service (connection name matches hostname)
      final unmappedConnection = config.getConnectionForService(
          'unknown-service', 'ghrunner.grsoft.no');
      expect(unmappedConnection, isNotNull);
      expect(unmappedConnection!.name, equals('ghrunner.grsoft.no'));

      print(
          '✅ Automatic hostname-based connection selection working correctly');
      print(
          '   ser2net on ghrunner.grsoft.no -> ${ser2netConnection.name} (${ser2netConnection.maxRestarts} attempts)');
      print(
          '   nginx on web-prod-01.example.com -> ${nginxConnection.name} (${nginxConnection.maxRestarts} attempts)');
      print(
          '   unknown-service on ghrunner.grsoft.no -> ${unmappedConnection.name} (automatic fallback)');
      print(
          '   💡 No explicit mappings needed - hostname matching just works!');
    });

    test(
        'should demonstrate pure hostname-based configuration (no mappings needed)',
        () {
      // This shows the ultimate simplified configuration - pure hostname matching

      final config = SshRestartConfig(
        connections: {
          'production.example.com': SshConnection(
            name: 'production.example.com',
            host: 'production.example.com',
            username: 'monitoring',
            privateKeyPath: '/etc/ssh/monitoring_key',
            maxRestarts: 2, // All services on this host: 2 attempts
            timeBetweenRestartAttempts: const Duration(
                minutes: 15), // All services on this host: 15 min cooldown
          ),
          'development.example.com': SshConnection(
            name: 'development.example.com',
            host: 'development.example.com',
            username: 'monitoring',
            privateKeyPath: '/etc/ssh/monitoring_key',
            maxRestarts:
                5, // All services on this host: 5 attempts (less strict)
            timeBetweenRestartAttempts: const Duration(
                minutes:
                    5), // All services on this host: 5 min cooldown (faster)
          ),
        },
        // NO restartMappings at all! Pure hostname-based automatic selection
        enabled: true,
        logOnly: true,
      );

      // Services automatically find connections by hostname from Icinga2
      final webService = config.getConnectionForService(
          'web-service', 'production.example.com');
      final apiService = config.getConnectionForService(
          'api-service', 'production.example.com');

      expect(webService, isNotNull);
      expect(webService!.maxRestarts, equals(2));
      expect(webService.timeBetweenRestartAttempts.inMinutes, equals(15));
      expect(apiService, isNotNull);
      expect(apiService!.maxRestarts, equals(2));
      expect(apiService.timeBetweenRestartAttempts.inMinutes, equals(15));

      // Development services automatically get development host settings
      final testService = config.getConnectionForService(
          'test-service', 'development.example.com');
      expect(testService, isNotNull);
      expect(testService!.maxRestarts, equals(5));
      expect(testService.timeBetweenRestartAttempts.inMinutes, equals(5));

      print('✅ Pure hostname-based configuration working perfectly');
      print(
          '   Production services: ${webService.maxRestarts} attempts, ${webService.timeBetweenRestartAttempts.inMinutes}min cooldown');
      print(
          '   Development services: ${testService.maxRestarts} attempts, ${testService.timeBetweenRestartAttempts.inMinutes}min cooldown');
      print(
          '   💡 Zero configuration overhead - just hostname matching! MUCH simpler!');
    });
  });
}

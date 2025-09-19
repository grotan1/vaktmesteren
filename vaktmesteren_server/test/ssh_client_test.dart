import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_config.dart';

void main() {
  group('SSH Client Tests', () {

    group('Configuration', () {
      test('should create SSH config from map', () {
        final configMap = {
          'enabled': true,
          'maxConnections': 15,
          'connectionTimeoutSeconds': 45,
          'commandTimeoutSeconds': 600,
          'maxRetries': 5,
          'retryDelaySeconds': 3,
          'verifyHostKeys': false,
          'knownHostsPath': '/custom/known_hosts',
          'logCommands': false,
          'logConnectionEvents': true,
        };

        final config = SshConfig.fromMap(configMap);

        expect(config.enabled, isTrue);
        expect(config.maxConnections, equals(15));
        expect(config.connectionTimeout.inSeconds, equals(45));
        expect(config.commandTimeout.inSeconds, equals(600));
        expect(config.maxRetries, equals(5));
        expect(config.retryDelay.inSeconds, equals(3));
        expect(config.verifyHostKeys, isFalse);
        expect(config.knownHostsPath, equals('/custom/known_hosts'));
        expect(config.logCommands, isFalse);
        expect(config.logConnectionEvents, isTrue);
      });

      test('should use default values for missing config', () {
        final config = SshConfig.fromMap({});

        expect(config.enabled, isFalse);
        expect(config.maxConnections, equals(10));
        expect(config.connectionTimeout.inSeconds, equals(30));
        expect(config.commandTimeout.inSeconds, equals(300));
        expect(config.maxRetries, equals(3));
        expect(config.retryDelay.inSeconds, equals(2));
        expect(config.verifyHostKeys, isTrue);
        expect(config.knownHostsPath, isNull);
        expect(config.logCommands, isTrue);
        expect(config.logConnectionEvents, isTrue);
      });
    });

    group('SSH Connection Model', () {
      test('should create connection from map', () {
        final connectionMap = {
          'host': 'example.com',
          'port': 2222,
          'username': 'admin',
          'privateKeyPath': '/path/to/key',
          'timeoutSeconds': 60,
        };

        final connection = SshConnection.fromMap('test-conn', connectionMap);

        expect(connection.name, equals('test-conn'));
        expect(connection.host, equals('example.com'));
        expect(connection.port, equals(2222));
        expect(connection.username, equals('admin'));
        expect(connection.privateKeyPath, equals('/path/to/key'));
        expect(connection.timeout.inSeconds, equals(60));
        expect(connection.usesKeyAuth, isTrue);
      });

      test('should use default values', () {
        final connectionMap = {
          'host': 'example.com',
          'username': 'admin',
        };

        final connection = SshConnection.fromMap('test-conn', connectionMap);

        expect(connection.port, equals(22));
        expect(connection.timeout.inSeconds, equals(30));
        expect(connection.privateKeyPath, isNull);
        expect(connection.password, isNull);
        expect(connection.usesKeyAuth, isFalse);
      });

      test('should generate connection string correctly', () {
        final connection = SshConnection.fromMap('test', {
          'host': 'server.example.com',
          'port': 2222,
          'username': 'admin',
        });

        expect(connection.connectionString, equals('admin@server.example.com:2222'));
      });
    });
  });
}
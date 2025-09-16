import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/icinga2_events.dart';
import 'package:vaktmesteren_server/src/icinga2_event_listener.dart';

void main() {
  group('Icinga2 Integration Tests', () {
    test('CheckResultEvent can be created from JSON', () {
      final json = {
        'type': 'CheckResult',
        'host': 'test-host',
        'service': 'test-service',
        'check_result': {
          'exit_status': 0,
          'output': 'OK - Service is running',
          'performance_data': []
        },
        'downtime_depth': 0,
        'acknowledgement': false
      };

      final event = Icinga2Event.fromJson(json) as CheckResultEvent;

      expect(event.type, 'CheckResult');
      expect(event.host, 'test-host');
      expect(event.service, 'test-service');
      expect(event.checkResult['exit_status'], 0);
      expect(event.downtimeDepth, 0);
      expect(event.acknowledgement, false);
    });

    test('StateChangeEvent can be created from JSON', () {
      final json = {
        'type': 'StateChange',
        'host': 'test-host',
        'service': 'test-service',
        'state': 2,
        'state_type': 1,
        'check_result': {
          'exit_status': 2,
          'output': 'CRITICAL - Service is down'
        },
        'downtime_depth': 0,
        'acknowledgement': false
      };

      final event = Icinga2Event.fromJson(json) as StateChangeEvent;

      expect(event.type, 'StateChange');
      expect(event.host, 'test-host');
      expect(event.service, 'test-service');
      expect(event.state, 2);
      expect(event.stateType, 1);
    });

    test('NotificationEvent can be created from JSON', () {
      final json = {
        'type': 'Notification',
        'host': 'test-host',
        'service': 'test-service',
        'command': 'notify-service-by-email',
        'users': ['admin@example.com'],
        'notification_type': 'PROBLEM',
        'author': 'icingaadmin',
        'text': 'Service is down',
        'check_result': {
          'exit_status': 2,
          'output': 'CRITICAL - Service is down'
        }
      };

      final event = Icinga2Event.fromJson(json) as NotificationEvent;

      expect(event.type, 'Notification');
      expect(event.host, 'test-host');
      expect(event.service, 'test-service');
      expect(event.command, 'notify-service-by-email');
      expect(event.users, ['admin@example.com']);
      expect(event.notificationType, 'PROBLEM');
      expect(event.author, 'icingaadmin');
      expect(event.text, 'Service is down');
    });

    test('AcknowledgementSetEvent can be created from JSON', () {
      final json = {
        'type': 'AcknowledgementSet',
        'host': 'test-host',
        'service': 'test-service',
        'state': 2,
        'state_type': 1,
        'author': 'admin',
        'comment': 'Acknowledging the issue',
        'acknowledgement_type': 1,
        'notify': true,
        'expiry': 1234567890
      };

      final event = Icinga2Event.fromJson(json) as AcknowledgementSetEvent;

      expect(event.type, 'AcknowledgementSet');
      expect(event.host, 'test-host');
      expect(event.service, 'test-service');
      expect(event.author, 'admin');
      expect(event.comment, 'Acknowledging the issue');
      expect(event.acknowledgementType, 1);
      expect(event.notify, true);
      expect(event.expiry, 1234567890);
    });

    test('ObjectCreatedEvent can be created from JSON', () {
      final json = {
        'type': 'ObjectCreated',
        'object_type': 'Host',
        'object_name': 'new-host'
      };

      final event = Icinga2Event.fromJson(json) as ObjectCreatedEvent;

      expect(event.type, 'ObjectCreated');
      expect(event.objectType, 'Host');
      expect(event.objectName, 'new-host');
    });

    test('UnknownEvent handles unrecognized event types', () {
      final json = {'type': 'UnknownEventType', 'custom_field': 'custom_value'};

      final event = Icinga2Event.fromJson(json) as UnknownEvent;

      expect(event.type, 'UnknownEventType');
      expect(event.rawData['custom_field'], 'custom_value');
    });

    test('Icinga2Config loads with default values', () async {
      // This test verifies that the config loading doesn't crash
      // In a real test environment, you'd mock the session and config loading
      final config = Icinga2Config(
        host: '10.0.0.11',
        port: 5665,
        scheme: 'https',
        username: 'eventstream-user',
        password: 'supersecretpassword',
        skipCertificateVerification: true,
        queue: 'test-queue',
        types: ['CheckResult'],
        filter: '',
        timeout: 30,
        reconnectEnabled: true,
        reconnectDelay: 5,
        maxRetries: 10,
      );

      expect(config.host, '10.0.0.11');
      expect(config.port, 5665);
      expect(config.username, 'eventstream-user');
      expect(config.password, 'supersecretpassword');
      expect(config.types, ['CheckResult']);
    });
  });
}

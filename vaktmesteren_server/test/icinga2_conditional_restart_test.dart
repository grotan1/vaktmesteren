// ignore_for_file: avoid_print

import 'package:test/test.dart';

void main() {
  group('Icinga2 Conditional SSH Restart Tests', () {
    test('should check auto_restart_service_linux variable from event data',
        () {
      // Test event with auto_restart_service_linux: true
      final eventWithAutoRestart = {
        'host': 'test-server',
        'service': 'test-service',
        'state': 2, // CRITICAL
        'state_type': 1, // HARD
        'vars': {'auto_restart_service_linux': true, 'other_var': 'some_value'},
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      };

      // Test event with auto_restart_service_linux: false
      final eventWithoutAutoRestart = {
        'host': 'test-server',
        'service': 'test-service',
        'state': 2, // CRITICAL
        'state_type': 1, // HARD
        'vars': {
          'auto_restart_service_linux': false,
          'other_var': 'some_value'
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      };

      // Test event without vars section
      final eventWithoutVars = {
        'host': 'test-server',
        'service': 'test-service',
        'state': 2, // CRITICAL
        'state_type': 1, // HARD
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      };

      // Test event with vars but no auto_restart_service_linux
      final eventWithVarsButNoAutoRestart = {
        'host': 'test-server',
        'service': 'test-service',
        'state': 2, // CRITICAL
        'state_type': 1, // HARD
        'vars': {'other_var': 'some_value'},
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      };

      // Extract service vars logic
      Map<String, dynamic>? extractServiceVars(Map<String, dynamic> event) {
        return event['vars'] as Map<String, dynamic>?;
      }

      bool shouldAutoRestart(Map<String, dynamic> event) {
        final serviceVars = extractServiceVars(event);
        return serviceVars?['auto_restart_service_linux'] as bool? ?? false;
      }

      // Test the logic
      expect(shouldAutoRestart(eventWithAutoRestart), isTrue,
          reason:
              'Should auto restart when auto_restart_service_linux is true');

      expect(shouldAutoRestart(eventWithoutAutoRestart), isFalse,
          reason:
              'Should not auto restart when auto_restart_service_linux is false');

      expect(shouldAutoRestart(eventWithoutVars), isFalse,
          reason: 'Should not auto restart when vars section is missing');

      expect(shouldAutoRestart(eventWithVarsButNoAutoRestart), isFalse,
          reason:
              'Should not auto restart when auto_restart_service_linux is missing from vars');

      print('✅ All conditional SSH restart logic tests passed');
    });

    test('should handle different data types for auto_restart_service_linux',
        () {
      // Test with string 'true'
      final eventWithStringTrue = {
        'vars': {'auto_restart_service_linux': 'true'}
      };

      // Test with integer 1
      final eventWithIntTrue = {
        'vars': {'auto_restart_service_linux': 1}
      };

      // Test with integer 0
      final eventWithIntFalse = {
        'vars': {'auto_restart_service_linux': 0}
      };

      bool shouldAutoRestart(Map<String, dynamic> event) {
        final serviceVars = event['vars'] as Map<String, dynamic>?;
        final autoRestartValue = serviceVars?['auto_restart_service_linux'];

        // Handle different types that Icinga2 might send
        if (autoRestartValue is bool) {
          return autoRestartValue;
        } else if (autoRestartValue is String) {
          return autoRestartValue.toLowerCase() == 'true';
        } else if (autoRestartValue is int) {
          return autoRestartValue != 0;
        }

        return false; // Default to false if not set or unrecognized type
      }

      // These should now properly handle different data types
      expect(shouldAutoRestart(eventWithStringTrue), isTrue,
          reason: 'Should auto restart with string "true"');

      expect(shouldAutoRestart(eventWithIntTrue), isTrue,
          reason: 'Should auto restart with integer 1');

      expect(shouldAutoRestart(eventWithIntFalse), isFalse,
          reason: 'Should not auto restart with integer 0');

      print('✅ Data type handling tests passed');
    });
  });
}

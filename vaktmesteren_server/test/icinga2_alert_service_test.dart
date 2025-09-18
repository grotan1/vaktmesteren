// ignore_for_file: avoid_print

import 'package:test/test.dart';
import 'package:vaktmesteren_server/src/icinga2_alert_service.dart';

void main() {
  group('Icinga2AlertService Tests', () {
    test('AlertState enum values', () {
      expect(AlertState.ok.value, equals(0));
      expect(AlertState.alertingCritical.value, equals(1));
      expect(AlertState.criticalSuppressed.value, equals(2));

      expect(AlertState.fromValue(0), equals(AlertState.ok));
      expect(AlertState.fromValue(1), equals(AlertState.alertingCritical));
      expect(AlertState.fromValue(2), equals(AlertState.criticalSuppressed));
      expect(
          AlertState.fromValue(99), equals(AlertState.ok)); // Default fallback
    });

    test('Alert state calculation logic', () {
      // Mock the _calculateAlertState method logic
      AlertState calculateAlertState(
          int state, int downtimeDepth, bool acknowledgement) {
        if (state == 0) {
          return AlertState.ok;
        } else if (state == 2) {
          // Critical
          if (downtimeDepth > 0 || acknowledgement) {
            return AlertState.criticalSuppressed;
          } else {
            return AlertState.alertingCritical;
          }
        } else {
          // For WARNING (1) and UNKNOWN (3), treat as OK for alerting purposes
          return AlertState.ok;
        }
      }

      // Test OK state
      expect(calculateAlertState(0, 0, false), equals(AlertState.ok));
      expect(calculateAlertState(0, 1, true), equals(AlertState.ok));

      // Test critical state - should alert
      expect(calculateAlertState(2, 0, false),
          equals(AlertState.alertingCritical));

      // Test critical state - suppressed by downtime
      expect(calculateAlertState(2, 1, false),
          equals(AlertState.criticalSuppressed));

      // Test critical state - suppressed by acknowledgement
      expect(calculateAlertState(2, 0, true),
          equals(AlertState.criticalSuppressed));

      // Test critical state - suppressed by both
      expect(calculateAlertState(2, 1, true),
          equals(AlertState.criticalSuppressed));

      // Test warning state - treated as OK
      expect(calculateAlertState(1, 0, false), equals(AlertState.ok));

      // Test unknown state - treated as OK
      expect(calculateAlertState(3, 0, false), equals(AlertState.ok));
    });

    test('State transition logic for alerting', () {
      // Mock state transition logic
      bool shouldSendAlert(AlertState fromState, AlertState toState) {
        return (fromState == AlertState.ok &&
                toState == AlertState.alertingCritical) ||
            (fromState == AlertState.alertingCritical &&
                toState == AlertState.ok) ||
            (fromState == AlertState.criticalSuppressed &&
                toState == AlertState.alertingCritical);
      }

      String? getAlertType(AlertState fromState, AlertState toState) {
        if (fromState == AlertState.ok &&
            toState == AlertState.alertingCritical) {
          return 'CRITICAL';
        } else if (fromState == AlertState.alertingCritical &&
            toState == AlertState.ok) {
          return 'RECOVERY';
        } else if (fromState == AlertState.criticalSuppressed &&
            toState == AlertState.alertingCritical) {
          return 'CRITICAL';
        }
        return null;
      }

      // Should send critical alert: OK -> Alerting Critical
      expect(
          shouldSendAlert(AlertState.ok, AlertState.alertingCritical), isTrue);
      expect(getAlertType(AlertState.ok, AlertState.alertingCritical),
          equals('CRITICAL'));

      // Should send recovery alert: Alerting Critical -> OK
      expect(
          shouldSendAlert(AlertState.alertingCritical, AlertState.ok), isTrue);
      expect(getAlertType(AlertState.alertingCritical, AlertState.ok),
          equals('RECOVERY'));

      // Should send critical alert: Suppressed -> Alerting Critical (came out of downtime/ack)
      expect(
          shouldSendAlert(
              AlertState.criticalSuppressed, AlertState.alertingCritical),
          isTrue);
      expect(
          getAlertType(
              AlertState.criticalSuppressed, AlertState.alertingCritical),
          equals('CRITICAL'));

      // Should NOT send alert: OK -> Suppressed Critical
      expect(shouldSendAlert(AlertState.ok, AlertState.criticalSuppressed),
          isFalse);
      expect(
          getAlertType(AlertState.ok, AlertState.criticalSuppressed), isNull);

      // Should NOT send alert: Alerting Critical -> Suppressed Critical (going into downtime/ack)
      expect(
          shouldSendAlert(
              AlertState.alertingCritical, AlertState.criticalSuppressed),
          isFalse);
      expect(
          getAlertType(
              AlertState.alertingCritical, AlertState.criticalSuppressed),
          isNull);

      // Should NOT send alert: Same state
      expect(shouldSendAlert(AlertState.ok, AlertState.ok), isFalse);
      expect(
          shouldSendAlert(
              AlertState.alertingCritical, AlertState.alertingCritical),
          isFalse);
      expect(
          shouldSendAlert(
              AlertState.criticalSuppressed, AlertState.criticalSuppressed),
          isFalse);
    });
  });
}

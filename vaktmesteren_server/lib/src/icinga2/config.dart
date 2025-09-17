part of '../icinga2_event_listener.dart';

/// Configuration class for Icinga2 connection (moved to part)
class Icinga2Config {
  final String host;
  final int port;
  final String scheme;
  final String username;
  final String password;
  final bool skipCertificateVerification;
  final String queue;
  final List<String> types;
  final String filter;
  final int timeout;
  final bool reconnectEnabled;
  final int reconnectDelay;
  final int maxRetries;
  // Inactivity timeout for the event stream (seconds). If no line arrives
  // within this time, we assume the connection is stalled and reconnect.
  final int streamInactivitySeconds;
  // Whether to use Dio for streaming instead of dart:io HttpClient
  final bool useDio;
  // Backfill interval for recovery checker (seconds)
  final int recoveryBackfillSeconds;

  Icinga2Config({
    required this.host,
    required this.port,
    required this.scheme,
    required this.username,
    required this.password,
    required this.skipCertificateVerification,
    required this.queue,
    required this.types,
    required this.filter,
    required this.timeout,
    required this.reconnectEnabled,
    required this.reconnectDelay,
    required this.maxRetries,
    this.streamInactivitySeconds = 300,
    this.useDio = false,
    this.recoveryBackfillSeconds = 60,
  });

  /// Load configuration from YAML file
  static Future<Icinga2Config> loadFromConfig(Session session) async {
    try {
      final cfgFile = File('config/icinga2.yaml');
      if (cfgFile.existsSync()) {
        try {
          final content = cfgFile.readAsStringSync();
          final doc = loadYaml(content);
          if (doc is YamlMap) {
            return Icinga2Config(
              host: doc['host'] ?? '10.0.0.11',
              port: doc['port'] ?? 5665,
              scheme: doc['scheme'] ?? 'https',
              username: doc['username'] ?? 'eventstream-user',
              password: doc['password'] ?? 'supersecretpassword',
              skipCertificateVerification:
                  doc['skipCertificateVerification'] ?? true,
              queue: doc['queue'] ?? 'vaktmesteren-server-queue',
              types: (doc['types'] is List)
                  ? List<String>.from(doc['types'])
                  : [
                      'CheckResult',
                      'StateChange',
                      'Notification',
                      'AcknowledgementSet',
                      'AcknowledgementCleared',
                      'CommentAdded',
                      'CommentRemoved',
                      'DowntimeAdded',
                      'DowntimeRemoved',
                      'DowntimeStarted',
                      'DowntimeTriggered',
                      'ObjectCreated',
                      'ObjectModified',
                      'ObjectDeleted'
                    ],
              filter: doc['filter'] ?? 'match("integrasjoner*", event.host)',
              timeout: doc['timeout'] ?? 30,
              reconnectEnabled: doc['reconnectEnabled'] ?? true,
              reconnectDelay: doc['reconnectDelay'] ?? 5,
              maxRetries: doc['maxRetries'] ?? 10,
              streamInactivitySeconds: doc['streamInactivitySeconds'] ??
                  doc['eventStreamInactivitySeconds'] ??
                  300,
              useDio: doc['useDio'] ?? false,
              recoveryBackfillSeconds: doc['recoveryBackfillSeconds'] ?? 60,
            );
          }
        } catch (e) {
          session.log('Failed to parse config/icinga2.yaml: $e',
              level: LogLevel.debug);
        }
      }

      return Icinga2Config(
        host: '10.0.0.11',
        port: 5665,
        scheme: 'https',
        username: 'eventstream-user',
        password: 'supersecretpassword',
        skipCertificateVerification: true,
        queue: 'vaktmesteren-server-queue',
        types: [
          'CheckResult',
          'StateChange',
          'Notification',
          'AcknowledgementSet',
          'AcknowledgementCleared',
          'CommentAdded',
          'CommentRemoved',
          'DowntimeAdded',
          'DowntimeRemoved',
          'DowntimeStarted',
          'DowntimeTriggered',
          'ObjectCreated',
          'ObjectModified',
          'ObjectDeleted'
        ],
        filter: 'match("integrasjoner*", event.host)',
        timeout: 30,
        reconnectEnabled: true,
        reconnectDelay: 5,
        maxRetries: 10,
        streamInactivitySeconds: 300,
        useDio: false,
        recoveryBackfillSeconds: 60,
      );
    } catch (e) {
      session.log('Failed to load Icinga2 configuration: $e',
          level: LogLevel.error);
      return Icinga2Config(
        host: '10.0.0.11',
        port: 5665,
        scheme: 'https',
        username: 'eventstream-user',
        password: 'supersecretpassword',
        skipCertificateVerification: true,
        queue: 'vaktmesteren-server-queue',
        types: [
          'CheckResult',
          'StateChange',
          'Notification',
          'AcknowledgementSet',
          'AcknowledgementCleared',
          'CommentAdded',
          'CommentRemoved',
          'DowntimeAdded',
          'DowntimeRemoved',
          'DowntimeStarted',
          'DowntimeTriggered',
          'ObjectCreated',
          'ObjectModified',
          'ObjectDeleted'
        ],
        filter: '',
        timeout: 30,
        reconnectEnabled: true,
        reconnectDelay: 5,
        maxRetries: 10,
        streamInactivitySeconds: 300,
        useDio: false,
        recoveryBackfillSeconds: 60,
      );
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:serverpod/serverpod.dart';
import 'package:yaml/yaml.dart';
import 'package:vaktmesteren_server/src/generated/protocol.dart';
import 'package:vaktmesteren_server/src/web/routes/log_viewer.dart';

/// Simple alert states for tracking
enum AlertState {
  ok(0), // Service is OK
  alertingCritical(1), // Service is CRITICAL and we've sent alert
  criticalSuppressed(2); // Service is CRITICAL but suppressed (downtime/ack)

  const AlertState(this.value);
  final int value;

  static AlertState fromValue(int value) {
    return AlertState.values
        .firstWhere((e) => e.value == value, orElse: () => AlertState.ok);
  }
}

/// Configuration for Icinga2 connection
class Icinga2Config {
  final String host;
  final int port;
  final String scheme;
  final String username;
  final String password;
  final bool skipCertificateVerification;
  final String queue;

  const Icinga2Config({
    required this.host,
    required this.port,
    required this.scheme,
    required this.username,
    required this.password,
    required this.skipCertificateVerification,
    required this.queue,
  });

  String get baseUrl => '$scheme://$host:$port';

  /// Load configuration from YAML file
  static Future<Icinga2Config> loadFromConfig(Session session) async {
    try {
      final cfgFile = File('config/icinga2.yaml');
      if (!cfgFile.existsSync()) {
        throw Exception('Icinga2 config file not found: config/icinga2.yaml');
      }

      final yamlString = await cfgFile.readAsString();
      final yaml = loadYaml(yamlString) as Map;
      final icinga2 = yaml['icinga2'] as Map;

      return Icinga2Config(
        host: icinga2['host'] as String,
        port: icinga2['port'] as int,
        scheme: icinga2['scheme'] as String,
        username: icinga2['username'] as String,
        password: icinga2['password'] as String,
        skipCertificateVerification:
            icinga2['skipCertificateVerification'] as bool? ?? false,
        queue: icinga2['eventStream']['queue'] as String,
      );
    } catch (e) {
      session.log('Failed to load Icinga2 config: $e', level: LogLevel.error);
      rethrow;
    }
  }
}

/// Simple Icinga2 Alert Service using event streams
class Icinga2AlertService {
  final Session session;
  final Icinga2Config config;
  late final Dio _dio;

  StreamSubscription<String>? _eventSubscription;
  bool _isRunning = false;
  Timer? _retentionTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 10;
  static const Duration reconnectDelay = Duration(seconds: 5);

  Icinga2AlertService(this.session, this.config) {
    _setupHttpClient();
  }

  void _setupHttpClient() {
    _dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout:
          const Duration(seconds: 300), // Long timeout for event stream
      headers: {
        'Accept': 'application/json',
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      },
    ));

    if (config.skipCertificateVerification) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
  }

  /// Start the alert service
  Future<void> start() async {
    if (_isRunning) {
      session.log('Icinga2AlertService is already running',
          level: LogLevel.warning);
      return;
    }

    _isRunning = true;
    session.log('Starting Icinga2AlertService...', level: LogLevel.info);

    // Broadcast service start to WebSocket clients
    LogBroadcaster.broadcastLog(
        '🟢 Icinga2AlertService started - monitoring for alerts');

    // Start retention cleanup timer (run daily)
    session.log('Starting retention cleanup...', level: LogLevel.info);
    _startRetentionCleanup();

    // Check initial service states
    try {
      await _checkInitialServiceStates();
    } catch (e) {
      session.log('Error in initial state check: $e', level: LogLevel.error);
    }

    // Start event stream
    session.log('About to connect to event stream...', level: LogLevel.info);
    try {
      await _connectEventStream();
      session.log('Event stream connection completed', level: LogLevel.info);
    } catch (e, stackTrace) {
      session.log(
          'Error connecting to event stream: $e\nStack trace: $stackTrace',
          level: LogLevel.error);
    }
  }

  /// Stop the alert service
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    session.log('Stopping Icinga2AlertService...', level: LogLevel.info);

    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _retentionTimer?.cancel();
    _retentionTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Connect to Icinga2 event stream
  Future<void> _connectEventStream() async {
    if (!_isRunning) {
      return;
    }

    try {
      session.log('Connecting to Icinga2 event stream...',
          level: LogLevel.info);

      final response = await _dio.post<ResponseBody>(
        '/v1/events',
        data: {
          'queue': config.queue,
          'types': [
            'StateChange',
            'CheckResult'
          ], // Subscribe to both state changes and check results
          'filter': '', // No filter to see all events
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'X-HTTP-Method-Override': 'POST'},
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to connect to event stream: ${response.statusCode}');
      }

      _reconnectAttempts =
          0; // Reset reconnect counter on successful connection
      session.log('Successfully connected to Icinga2 event stream',
          level: LogLevel.info);

      // Broadcast successful connection to WebSocket clients
      LogBroadcaster.broadcastLog(
          '✅ Connected to Icinga2 event stream - ready for alerts');

      // Listen to the stream
      _eventSubscription = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .listen(
        (line) {
          _handleEventLine(line);
        },
        onError: (error) {
          _handleStreamError(error);
        },
        onDone: () {
          _handleStreamDone();
        },
        cancelOnError: false,
      );
    } catch (e) {
      session.log('Failed to connect to event stream: $e',
          level: LogLevel.error);

      // Broadcast connection failure to WebSocket clients
      LogBroadcaster.broadcastLog(
          '❌ Failed to connect to Icinga2 event stream - will retry');
      _scheduleReconnect();
    }
  }

  /// Handle a single event line from the stream
  void _handleEventLine(String line) async {
    try {
      final event = jsonDecode(line) as Map<String, dynamic>;
      final eventType = event['type'];

      if (eventType == 'StateChange') {
        session.log('Processing StateChange event', level: LogLevel.info);
        await _processStateChangeEvent(event);
      } else if (eventType == 'CheckResult') {
        session.log('Processing CheckResult event', level: LogLevel.info);
        await _processCheckResultEvent(event);
      } else {
        // Reduce noise from other event types
        // session.log('Received other event type: $eventType', level: LogLevel.info);
      }
    } catch (e) {
      session.log('Error parsing event line: $e', level: LogLevel.warning);
    }
  }

  /// Process a StateChange event
  Future<void> _processStateChangeEvent(Map<String, dynamic> event) async {
    try {
      final host = event['host'] as String;
      final service = event['service'] as String?;
      final state = event['state'] as int;
      final stateType = event['state_type'] as int;
      final downtimeDepth = event['downtime_depth'] as int? ?? 0;
      final acknowledgementValue = event['acknowledgement'];
      final acknowledgement = acknowledgementValue is bool
          ? acknowledgementValue
          : (acknowledgementValue as int?) != 0;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          ((event['timestamp'] as double) * 1000).round());

      session.log(
          'StateChange: host=$host, service=$service, state=$state, state_type=$stateType',
          level: LogLevel.info);

      // Skip host checks, only process services
      if (service == null) {
        session.log('Skipping host check', level: LogLevel.info);
        return;
      }

      // Only process hard state changes
      if (stateType != 1) {
        session.log('Skipping soft state change (state_type=$stateType)',
            level: LogLevel.info);
        return;
      }

      final canonicalKey = '$host!$service';
      session.log('Processing service: $canonicalKey', level: LogLevel.info);

      // Calculate current alert state
      final currentAlertState =
          _calculateAlertState(state, downtimeDepth, acknowledgement);
      session.log('Current alert state: $currentAlertState',
          level: LogLevel.info);

      // Get stored state
      final storedState = await _getStoredState(canonicalKey);
      session.log('Stored state: $storedState', level: LogLevel.info);

      // Check if we need to send an alert
      if (currentAlertState != storedState) {
        session.log(
            'State transition detected: $storedState -> $currentAlertState',
            level: LogLevel.info);
        await _handleStateTransition(canonicalKey, host, service, storedState,
            currentAlertState, event, timestamp);
        await _updateStoredState(
            canonicalKey, host, service, currentAlertState, timestamp);
      } else {
        session.log('No state change, skipping', level: LogLevel.info);
      }
    } catch (e) {
      session.log('Error processing StateChange event: $e',
          level: LogLevel.error);
    }
  }

  /// Process a CheckResult event (can detect state changes from check results)
  Future<void> _processCheckResultEvent(Map<String, dynamic> event) async {
    try {
      final host = event['host'] as String;
      final service = event['service'] as String?;

      // Skip host checks, only process services
      if (service == null) {
        return;
      }

      final checkResult = event['check_result'] as Map<String, dynamic>?;
      if (checkResult == null) {
        return;
      }

      final state = checkResult['state'] as int?;
      final previousHardState = checkResult['previous_hard_state'] as int?;

      if (state == null) {
        return;
      }

      // Only process if this represents a hard state change
      if (previousHardState != null && state == previousHardState) {
        return;
      }

      // Only care about OK (0) and CRITICAL (2) states
      if (state != 0 && state != 2) {
        return;
      }

      final downtimeDepth = event['downtime_depth'] as int? ?? 0;
      final acknowledgementValue = event['acknowledgement'];
      final acknowledgement = acknowledgementValue is bool
          ? acknowledgementValue
          : (acknowledgementValue as int?) != 0;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          ((event['timestamp'] as double) * 1000).round());

      final canonicalKey = '$host!$service';
      session.log('CheckResult state transition: $canonicalKey, state=$state',
          level: LogLevel.info);

      // Calculate current alert state
      final currentAlertState =
          _calculateAlertState(state, downtimeDepth, acknowledgement);

      // Get stored state
      final storedState = await _getStoredState(canonicalKey);

      // Check if we need to send an alert
      if (currentAlertState != storedState) {
        session.log(
            'ALERT: State transition $storedState -> $currentAlertState for $canonicalKey',
            level: LogLevel.warning);
        await _handleStateTransition(canonicalKey, host, service, storedState,
            currentAlertState, event, timestamp);
        await _updateStoredState(
            canonicalKey, host, service, currentAlertState, timestamp);
      } else {
        // Transition detected in Icinga2 but already at correct state in our DB
        // No action needed
      }
    } catch (e) {
      session.log('Error processing CheckResult event: $e',
          level: LogLevel.error);
    }
  }

  /// Calculate alert state based on service state and suppression factors
  AlertState _calculateAlertState(
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

  /// Get stored alert state for a service
  Future<AlertState> _getStoredState(String canonicalKey) async {
    try {
      final persistedState = await PersistedAlertState.db.findFirstRow(
        session,
        where: (t) => t.canonicalKey.equals(canonicalKey),
      );

      if (persistedState != null) {
        return AlertState.fromValue(persistedState.lastState);
      }

      return AlertState.ok; // Default to OK if no stored state
    } catch (e) {
      session.log('Error getting stored state for $canonicalKey: $e',
          level: LogLevel.error);
      return AlertState.ok;
    }
  }

  /// Handle state transition and send alerts if needed
  Future<void> _handleStateTransition(
    String canonicalKey,
    String host,
    String? service,
    AlertState fromState,
    AlertState toState,
    Map<String, dynamic> event,
    DateTime timestamp,
  ) async {
    String? alertMessage;

    // Determine if we should send an alert
    if (fromState == AlertState.ok && toState == AlertState.alertingCritical) {
      // Send CRITICAL alert
      alertMessage = 'CRITICAL: Service has entered critical state';
    } else if (fromState == AlertState.alertingCritical &&
        toState == AlertState.ok) {
      // Send RECOVERY alert
      alertMessage = 'RECOVERY: Service has recovered';
    } else if (fromState == AlertState.criticalSuppressed &&
        toState == AlertState.alertingCritical) {
      // Send CRITICAL alert (came out of suppression)
      alertMessage = 'CRITICAL: Service has entered critical state';
    }

    // Create alert history entry if we have a message
    if (alertMessage != null) {
      await _createAlertHistoryEntry(
          canonicalKey, host, service, toState.value, alertMessage, timestamp);
      session.log('Alert: $canonicalKey -> $alertMessage',
          level: LogLevel.info);

      // Broadcast alert to real-time WebSocket clients with appropriate glyph
      if (toState == AlertState.ok) {
        // Recovery alert - use checkmark
        LogBroadcaster.broadcastLog('✅ $alertMessage for $canonicalKey');
      } else {
        // Critical alert - use warning
        LogBroadcaster.broadcastLog('🚨 $alertMessage for $canonicalKey');
      }
    }
  }

  /// Update stored state for a service
  Future<void> _updateStoredState(
    String canonicalKey,
    String host,
    String? service,
    AlertState alertState,
    DateTime timestamp,
  ) async {
    try {
      final existingState = await PersistedAlertState.db.findFirstRow(
        session,
        where: (t) => t.canonicalKey.equals(canonicalKey),
      );

      if (existingState != null) {
        // Update existing
        await PersistedAlertState.db.updateRow(
          session,
          existingState.copyWith(
            lastState: alertState.value,
            lastUpdated: timestamp,
          ),
        );
      } else {
        // Create new
        await PersistedAlertState.db.insertRow(
          session,
          PersistedAlertState(
            host: host,
            service: service,
            canonicalKey: canonicalKey,
            lastState: alertState.value,
            lastUpdated: timestamp,
          ),
        );
      }
    } catch (e) {
      session.log('Error updating stored state for $canonicalKey: $e',
          level: LogLevel.error);
    }
  }

  /// Create an alert history entry
  Future<void> _createAlertHistoryEntry(
    String canonicalKey,
    String host,
    String? service,
    int state,
    String message,
    DateTime timestamp,
  ) async {
    try {
      await AlertHistory.db.insertRow(
        session,
        AlertHistory(
          host: host,
          service: service,
          canonicalKey: canonicalKey,
          state: state,
          message: message,
          createdAt: timestamp,
        ),
      );
    } catch (e) {
      session.log('Error creating alert history entry: $e',
          level: LogLevel.error);
    }
  }

  /// Handle stream errors
  void _handleStreamError(dynamic error) {
    session.log('Event stream error: $error', level: LogLevel.error);

    // Broadcast stream error to WebSocket clients
    LogBroadcaster.broadcastLog(
        '⚠️ Icinga2 event stream error - reconnecting...');

    _scheduleReconnect();
  }

  /// Handle stream completion
  void _handleStreamDone() {
    session.log('Event stream closed', level: LogLevel.warning);

    // Broadcast stream closure to WebSocket clients
    LogBroadcaster.broadcastLog(
        '🔄 Icinga2 event stream disconnected - reconnecting...');

    _scheduleReconnect();
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (!_isRunning || _reconnectAttempts >= maxReconnectAttempts) {
      if (_reconnectAttempts >= maxReconnectAttempts) {
        session.log('Max reconnection attempts reached, giving up',
            level: LogLevel.error);
      }
      return;
    }

    _reconnectAttempts++;
    session.log(
        'Scheduling reconnect attempt $_reconnectAttempts in ${reconnectDelay.inSeconds}s',
        level: LogLevel.info);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () async {
      if (_isRunning) {
        await _connectEventStream();
      }
    });
  }

  /// Start retention cleanup timer
  void _startRetentionCleanup() {
    // Run cleanup daily at 2 AM
    const cleanupTime = Duration(hours: 2);
    final now = DateTime.now();
    final nextCleanup = DateTime(now.year, now.month, now.day,
            cleanupTime.inHours, cleanupTime.inMinutes)
        .add(now.hour >= cleanupTime.inHours
            ? const Duration(days: 1)
            : Duration.zero);

    final timeToCleanup = nextCleanup.difference(now);

    _retentionTimer = Timer(timeToCleanup, () {
      _runRetentionCleanup();
      // Schedule daily cleanup
      _retentionTimer = Timer.periodic(
          const Duration(days: 1), (_) => _runRetentionCleanup());
    });

    session.log(
        'Retention cleanup scheduled for ${nextCleanup.toIso8601String()}',
        level: LogLevel.info);
  }

  /// Clean up old alert history entries (older than 3 days)
  Future<void> _runRetentionCleanup() async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 3));

      final deletedEntries = await AlertHistory.db.deleteWhere(
        session,
        where: (t) => t.createdAt < cutoffDate,
      );

      session.log(
          'Retention cleanup: deleted ${deletedEntries.length} old alert history entries',
          level: LogLevel.info);
    } catch (e) {
      session.log('Error during retention cleanup: $e', level: LogLevel.error);
    }
  }

  /// Check initial state of all services to detect existing critical states
  Future<void> _checkInitialServiceStates() async {
    try {
      session.log('Checking initial service states...', level: LogLevel.info);

      final response = await _dio.post(
        '/v1/objects/services',
        data: {
          'attrs': [
            'state',
            'state_type',
            'downtime_depth',
            'acknowledgement',
            'host_name',
            'name'
          ],
          'filter':
              'service.state_type==1 && service.state==2', // Only hard critical states
        },
        options: Options(
          headers: {'X-HTTP-Method-Override': 'GET'},
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get service states: ${response.statusCode}');
      }

      final services = response.data['results'] as List;
      session.log('Found ${services.length} services in hard critical state',
          level: LogLevel.info);

      for (final serviceData in services) {
        final attrs = serviceData['attrs'] as Map<String, dynamic>;
        final host = attrs['host_name'] as String;
        final service = attrs['name'] as String;
        final state = attrs['state'] as int;
        final stateType = attrs['state_type'] as int;
        final downtimeDepth = attrs['downtime_depth'] as int? ?? 0;
        final acknowledgementValue = attrs['acknowledgement'];
        final acknowledgement = acknowledgementValue is bool
            ? acknowledgementValue
            : (acknowledgementValue as int?) != 0;

        // Skip if not hard critical state (double-check the filter)
        if (stateType != 1 || state != 2) continue;

        final canonicalKey = '$host!$service';
        final currentAlertState =
            _calculateAlertState(state, downtimeDepth, acknowledgement);

        // Get stored state
        final storedState = await _getStoredState(canonicalKey);

        // Check if we need to send an alert
        if (currentAlertState != storedState) {
          // Create a synthetic event for logging
          final syntheticEvent = {
            'host': host,
            'service': service,
            'state': state,
            'state_type': stateType,
            'downtime_depth': downtimeDepth,
            'acknowledgement': acknowledgement,
            'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          };

          await _handleStateTransition(
            canonicalKey,
            host,
            service,
            storedState,
            currentAlertState,
            syntheticEvent,
            DateTime.now(),
          );
          await _updateStoredState(
              canonicalKey, host, service, currentAlertState, DateTime.now());
        }
      }

      session.log('Initial service state check completed',
          level: LogLevel.info);
    } catch (e) {
      session.log('Error checking initial service states: $e',
          level: LogLevel.error);
    }
  }
}

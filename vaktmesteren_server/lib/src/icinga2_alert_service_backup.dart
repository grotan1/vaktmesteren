// ignore_for_file: unnecessary_string_escapes

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:serverpod/serverpod.dart';
import 'package:yaml/yaml.dart';
import 'package:vaktmesteren_server/src/generated/protocol.dart';
import 'package:vaktmesteren_server/src/web/routes/log_viewer.dart';
import 'package:vaktmesteren_server/src/ops/clients/ssh_client.dart';
import 'package:vaktmesteren_server/src/ops/services/linux_service_restart_service.dart';
import 'package:vaktmesteren_server/src/ops/config/ssh_restart_config_loader.dart';
import 'package:vaktmesteren_server/src/ops/models/restart_rule.dart';
import 'package:vaktmesteren_server/src/ops/models/ssh_connection.dart';
import 'package:vaktmesteren_server/src/ops/services/teams_notification_service.dart';

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

  // SSH restart components
  SshClient? _sshClient;
  LinuxServiceRestartService? _restartService;
  SshRestartConfig? _sshConfig;

  // Teams notification components
  TeamsNotificationService? _teamsService;

  StreamSubscription<String>? _eventSubscription;
  bool _isRunning = false;
  Timer? _retentionTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 10;
  static const Duration reconnectDelay = Duration(seconds: 5);

  Icinga2AlertService(this.session, this.config) {
    _setupHttpClient();
    // Note: SSH initialization will happen in start() method
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

  /// Initialize SSH restart functionality
  Future<void> _initializeSshRestart() async {
    session.log('Inside _initializeSshRestart method', level: LogLevel.debug);
    try {
      session.log('About to log SSH initialization...', level: LogLevel.debug);
      session.log('Initializing SSH restart functionality...',
          level: LogLevel.info);

      // Broadcast initialization start to WebSocket clients
      LogBroadcaster.broadcastLog('🔧 Initializing SSH restart system...');

      // Load SSH restart configuration
      session.log('Loading SSH restart configuration...', level: LogLevel.info);
      _sshConfig = await SshRestartConfigLoader.loadConfig(session);

      session.log(
          'SSH config loaded: enabled=${_sshConfig?.enabled}, logOnly=${_sshConfig?.logOnly}',
          level: LogLevel.info);
      if (_sshConfig?.enabled == true) {
        // Initialize SSH client (in log-only mode by default)
        _sshClient = SshClient(session, logOnly: _sshConfig?.logOnly ?? true);

        // Initialize restart service
        _restartService = LinuxServiceRestartService(session, _sshClient!);

        session.log(
          'SSH restart system initialized: ${_sshConfig!.connections.length} connections, '
          '${_sshConfig!.rules.length} rules, logOnly=${_sshConfig!.logOnly}',
          level: LogLevel.info,
        );

        // Broadcast initialization to WebSocket clients
        LogBroadcaster.broadcastLog(
            '🔧 SSH restart system initialized (${_sshConfig!.logOnly ? 'LOG-ONLY' : 'LIVE'} mode)');
      } else {
        session.log('SSH restart system is disabled in configuration',
            level: LogLevel.info);
      }
    } catch (e) {
      session.log('Failed to initialize SSH restart system: $e',
          level: LogLevel.error);

      // Continue without SSH restart functionality
      _sshConfig = null;
      _sshClient = null;
      _restartService = null;
    }
  }

  /// Initialize Teams notification functionality
  Future<void> _initializeTeamsNotifications() async {
    try {
      session.log('Loading Teams notification configuration...',
          level: LogLevel.info);

      // Broadcast initialization start to WebSocket clients
      LogBroadcaster.broadcastLog(
          '📨 Initializing Teams notification system...');

      // Initialize Teams notification service
      _teamsService = TeamsNotificationService(session);
      await _teamsService!.initialize();

      final status = _teamsService!.getStatus();

      if (status['enabled'] == true) {
        session.log(
          'Teams notification system initialized: ${status['activeWebhookCount']} webhooks, '
          '${status['activeRuleCount']} rules, logOnly=${status['logOnly']}',
          level: LogLevel.info,
        );

        // Broadcast initialization to WebSocket clients
        LogBroadcaster.broadcastLog(
            '📨 Teams notifications initialized (${status['logOnly'] ? 'LOG-ONLY' : 'LIVE'} mode)');
      } else {
        session.log('Teams notification system is disabled in configuration',
            level: LogLevel.info);
        LogBroadcaster.broadcastLog('📨 Teams notifications disabled');
      }
    } catch (e) {
      session.log('Failed to initialize Teams notification system: $e',
          level: LogLevel.error);

      // Continue without Teams notifications
      _teamsService = null;
      LogBroadcaster.broadcastLog('❌ Teams notification initialization failed');
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

    // Initialize SSH restart functionality
    try {
      session.log('About to initialize SSH restart system...',
          level: LogLevel.debug);
      await _initializeSshRestart();
      session.log('SSH restart system initialization completed',
          level: LogLevel.info);
    } catch (e) {
      session.log('Error initializing SSH restart system: $e',
          level: LogLevel.error);
    }

    // Initialize Teams notifications
    try {
      session.log('Initializing Teams notification system...',
          level: LogLevel.info);
      await _initializeTeamsNotifications();
      session.log('Teams notification system initialization completed',
          level: LogLevel.info);
    } catch (e) {
      session.log('Error initializing Teams notification system: $e',
          level: LogLevel.error);
    }

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
      final stateType = checkResult['state_type'] as int?;
      final previousHardState = checkResult['previous_hard_state'] as int?;

      if (state == null) {
        return;
      }

      // Only process hard state changes (state_type == 1)
      if (stateType != 1) {
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

    session.log('State transition: $canonicalKey from $fromState to $toState',
        level: LogLevel.info);
    LogBroadcaster.broadcastLog(
        '🔄 State transition: $canonicalKey ($fromState → $toState)');

    // Determine if we should send an alert
    if (fromState == AlertState.ok && toState == AlertState.alertingCritical) {
      // Send CRITICAL alert
      alertMessage = 'CRITICAL: Service has entered critical state';
      session.log('Alert condition met: OK → CRITICAL', level: LogLevel.info);
    } else if (fromState == AlertState.alertingCritical &&
        toState == AlertState.ok) {
      // Send RECOVERY alert
      alertMessage = 'RECOVERY: Service has recovered';
      session.log('Alert condition met: CRITICAL → OK', level: LogLevel.info);
    } else if (fromState == AlertState.criticalSuppressed &&
        toState == AlertState.alertingCritical) {
      // Send CRITICAL alert (came out of suppression)
      alertMessage = 'CRITICAL: Service has entered critical state';
      session.log('Alert condition met: SUPPRESSED → CRITICAL',
          level: LogLevel.info);
    } else {
      session.log(
          'No alert condition met for transition: $fromState → $toState',
          level: LogLevel.info);
      LogBroadcaster.broadcastLog(
          'ℹ️ No alert needed for: $canonicalKey ($fromState → $toState)');
    }

    // Create alert history entry if we have a message
    if (alertMessage != null) {
      session.log(
          'Creating alert history entry for $canonicalKey: $alertMessage',
          level: LogLevel.info);

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

      // Send Teams notifications for alerts
      await _sendTeamsNotification(host, service, toState, alertMessage);

      // Trigger SSH service restart for CRITICAL alerts
      if (toState == AlertState.alertingCritical && service != null) {
        await _triggerServiceRestart(service, host, canonicalKey, event);
      }
    }
  }

  /// Trigger SSH service restart for critical alerts
  Future<void> _triggerServiceRestart(String icingaServiceName, String host,
      String canonicalKey, Map<String, dynamic> event) async {
    try {
      // Check if auto restart is enabled for this service
      // The event stream doesn't include service vars, so we need to fetch them via API
      final serviceVars = await _fetchServiceVars(host, icingaServiceName);
      final autoRestartValue = serviceVars?['auto_restart_service_linux'];

      // Handle different types that Icinga2 might send
      bool autoRestartEnabled = false;
      if (autoRestartValue is bool) {
        autoRestartEnabled = autoRestartValue;
      } else if (autoRestartValue is String) {
        autoRestartEnabled = autoRestartValue.toLowerCase() == 'true';
      } else if (autoRestartValue is int) {
        autoRestartEnabled = autoRestartValue != 0;
      }

      if (!autoRestartEnabled) {
        session.log(
            'Service $canonicalKey has auto_restart_service_linux disabled, skipping SSH restart',
            level: LogLevel.info);
        LogBroadcaster.broadcastLog(
            '⏭️ SSH restart skipped for $canonicalKey (auto_restart_service_linux: ${autoRestartValue ?? 'not set'})');
        return;
      }

      session.log(
          'Service $canonicalKey has auto_restart_service_linux enabled, proceeding with SSH restart',
          level: LogLevel.info);
      LogBroadcaster.broadcastLog(
          '✅ SSH restart enabled for $canonicalKey (auto_restart_service_linux: $autoRestartValue)');

      // Check if SSH restart system is available
      if (_sshConfig == null || _restartService == null || _sshClient == null) {
        session.log(
            'SSH restart system not available, skipping restart for $canonicalKey',
            level: LogLevel.info);
        return;
      }

      if (!_sshConfig!.enabled) {
        session.log(
            'SSH restart system is disabled, skipping restart for $canonicalKey',
            level: LogLevel.info);
        return;
      }

      // Check if systemd_unit_unit is specified in service variables for automatic detection
      final systemdUnitName = serviceVars?['systemd_unit_unit'] as String?;

      if (systemdUnitName != null && systemdUnitName.isNotEmpty) {
        session.log(
            'Using automatic systemd service detection: $systemdUnitName',
            level: LogLevel.info);
        LogBroadcaster.broadcastLog(
            '🎯 Automatic service detection: $systemdUnitName');

        await _executeAutomaticRestart(
            systemdUnitName, host, icingaServiceName, canonicalKey);
        return;
      }

      session.log(
          'No systemd_unit_unit found - fallback pattern matching disabled. Only auto-detected services will trigger SSH restarts.',
          level: LogLevel.info);
      LogBroadcaster.broadcastLog(
          '� SSH restart disabled: No systemd_unit_unit variable found for service: $icingaServiceName');
      LogBroadcaster.broadcastLog(
          '💡 To enable SSH restart: Ensure Icinga2 service includes systemd_unit_unit variable matching a configured rule');
      return;
    } catch (e) {
      session.log('Error in SSH service restart trigger: $e',
          level: LogLevel.error);
      LogBroadcaster.broadcastLog('❌ SSH restart system error: $e');
    }
  }

  /// Execute automatic restart using systemd_unit_unit from Icinga2 service variables
  Future<void> _executeAutomaticRestart(String systemdUnitName, String host,
      String icingaServiceName, String canonicalKey) async {
    try {
      // First, try to find an existing restart rule for this systemd service
      final existingRule =
          _sshConfig!.findRuleBySystemdService(systemdUnitName);

      if (existingRule != null) {
        session.log(
            'Found existing restart rule for systemd service: $systemdUnitName',
            level: LogLevel.info);
        LogBroadcaster.broadcastLog(
            '🎯 Using configured rule for auto-detected service: $systemdUnitName');

        // Get the SSH connection for this rule
        SshConnection? connection;

        if (existingRule.sshConnectionName == "auto") {
          // Use host-based connection lookup for "auto" rules
          connection = _sshConfig!.getConnectionByHost(host);
          if (connection != null) {
            session.log(
                'Rule uses auto connection, found SSH connection for host "$host": ${connection.name}',
                level: LogLevel.info);
            LogBroadcaster.broadcastLog(
                '🎯 Rule auto-selected SSH connection for host "$host": ${connection.name}');
          }
        } else {
          // Use specified connection name
          connection =
              _sshConfig!.getConnection(existingRule.sshConnectionName);
        }

        if (connection == null) {
          final connectionRef = existingRule.sshConnectionName == "auto"
              ? 'auto-detected connection for host "$host"'
              : 'SSH connection "${existingRule.sshConnectionName}"';
          session.log('$connectionRef not found for auto-detected service rule',
              level: LogLevel.error);
          LogBroadcaster.broadcastLog(
              '❌ $connectionRef not configured for auto-detected service');
          return;
        }

        // Log the restart attempt with rule details
        LogBroadcaster.broadcastLog(
            '🔄 Rule-based automatic restart: $systemdUnitName on ${connection.host} (${_sshConfig!.logOnly ? 'SIMULATION' : 'LIVE'})');
        LogBroadcaster.broadcastLog(
            '⚙️ Rule settings: max ${existingRule.maxRestartsPerHour}/hour, ${existingRule.cooldownPeriod.inMinutes}min cooldown');

        // Execute the restart using the existing rule
        final result = await _restartService!
            .restartService(existingRule, connection, icingaServiceName);

        if (result.success) {
          session.log(
              'Rule-based automatic restart ${result.wasSimulated ? 'simulation ' : ''}successful: ${result.message}',
              level: LogLevel.info);
          LogBroadcaster.broadcastLog(
              '✅ Rule-based automatic restart successful: $systemdUnitName');
        } else {
          session.log(
              'Rule-based automatic restart ${result.wasSimulated ? 'simulation ' : ''}failed: ${result.message}',
              level: LogLevel.warning);
          LogBroadcaster.broadcastLog(
              '❌ Rule-based automatic restart failed: ${result.message}');
        }
        return;
      }

      // No restart rule found for this systemd service - do NOT restart
      session.log(
          'No specific restart rule found for systemd service: $systemdUnitName, using default behavior',
          level: LogLevel.info);
      LogBroadcaster.broadcastLog(
          '� No specific rule found for auto-detected service: $systemdUnitName, using default restart behavior');
      LogBroadcaster.broadcastLog(
          '� To enable SSH restart: Add rule with systemdServiceName: "$systemdUnitName" to configuration');
      return;
    } catch (e) {
      session.log('Error in automatic service restart for $systemdUnitName: $e',
          level: LogLevel.error);
      LogBroadcaster.broadcastLog(
          '❌ Automatic restart error for $systemdUnitName: $e');
    }
  }

  /// Fetch service variables from Icinga2 API
  Future<Map<String, dynamic>?> _fetchServiceVars(
      String host, String service) async {
    try {
      // Use Dio to make the API request
      final response = await _dio.get(
        '/v1/objects/services',
        queryParameters: {'filter': 'service.__name==\"$host!$service\"'},
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>?;

        if (results != null && results.isNotEmpty) {
          final serviceObject = results.first as Map<String, dynamic>;
          final attrs = serviceObject['attrs'] as Map<String, dynamic>?;
          final vars = attrs?['vars'] as Map<String, dynamic>?;

          session.log(
              'Successfully fetched service vars: ${vars?.keys.toList()}',
              level: LogLevel.info);
          return vars;
        } else {
          session.log('No service found for $host!$service',
              level: LogLevel.warning);
          return null;
        }
      } else {
        session.log('Failed to fetch service vars: HTTP ${response.statusCode}',
            level: LogLevel.error);
        LogBroadcaster.broadcastLog(
            '❌ Failed to fetch service vars: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      session.log('Error fetching service vars: $e', level: LogLevel.error);
      LogBroadcaster.broadcastLog('❌ Error fetching service vars: $e');
      return null;
    }
  }

  /// Send Teams notification for alerts
  Future<void> _sendTeamsNotification(String host, String? service,
      AlertState alertState, String message) async {
    try {
      // Check if Teams notification system is available
      if (_teamsService == null) {
        session.log(
            'Teams notification system not available, skipping notification',
            level: LogLevel.debug);
        return;
      }

      // Convert alert state to severity
      String severity;
      switch (alertState) {
        case AlertState.ok:
          severity = 'RECOVERY';
          break;
        case AlertState.alertingCritical:
          severity = 'CRITICAL';
          break;
        case AlertState.criticalSuppressed:
          severity = 'WARNING'; // Suppressed alerts as warnings
          break;
      }

      // Send Teams notification
      await _teamsService!.processAlert(
        severity: severity,
        host: host,
        service: service,
        message: message,
        metadata: {
          'timestamp': DateTime.now().toIso8601String(),
          'alertState': alertState.value,
        },
      );
    } catch (e) {
      session.log('Error sending Teams notification: $e',
          level: LogLevel.error);
      LogBroadcaster.broadcastLog('❌ Teams notification error: $e');
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
      session.log(
          'Inserting alert history: host=$host, service=$service, state=$state, message=$message',
          level: LogLevel.info);

      final alertHistory = AlertHistory(
        host: host,
        service: service,
        canonicalKey: canonicalKey,
        state: state,
        message: message,
        createdAt: timestamp,
      );

      session.log('Created AlertHistory object: $alertHistory',
          level: LogLevel.info);

      await AlertHistory.db.insertRow(session, alertHistory);

      session.log('Alert history entry created successfully for $canonicalKey',
          level: LogLevel.info);
      LogBroadcaster.broadcastLog('✅ Alert history saved: $canonicalKey');
    } catch (e, stackTrace) {
      session.log(
          'Error creating alert history entry: $e\nStack trace: $stackTrace',
          level: LogLevel.error);
      LogBroadcaster.broadcastLog('❌ Alert history save failed: $e');
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

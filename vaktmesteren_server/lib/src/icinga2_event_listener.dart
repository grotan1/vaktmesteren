import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:serverpod/serverpod.dart';
import 'icinga2_events.dart';
import 'web/routes/log_viewer.dart';
import 'package:vaktmesteren_server/src/generated/protocol.dart';

/// Configuration class for Icinga2 connection
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
  });

  /// Load configuration from YAML file
  static Future<Icinga2Config> loadFromConfig(Session session) async {
    try {
      // For now, return hardcoded config based on the provided credentials
      // TODO: Implement proper configuration loading from icinga2.yaml
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
        filter: '', // Empty filter to include all events
        timeout: 30,
        reconnectEnabled: true,
        reconnectDelay: 5,
        maxRetries: 10,
      );
    } catch (e) {
      session.log('Failed to load Icinga2 configuration: $e',
          level: LogLevel.error);
      // Return default configuration
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
        filter: '', // Empty filter to include all events
        timeout: 30,
        reconnectEnabled: true,
        reconnectDelay: 5,
        maxRetries: 10,
      );
    }
  }
}

/// Service class for listening to Icinga2 event streams
class Icinga2EventListener {
  final Session session;
  final Icinga2Config config;

  // NOTE: _client, _streamSubscription and _reconnectTimer were unused and
  // removed to satisfy analyzer warnings.
  int _retryCount = 0;
  bool _isShuttingDown = false;
  IOClient? _ioClient;
  int _debugEventCount = 0;
  DateTime? _lastEventAt;

  // Polling has been removed - the event stream (and websocket) provide live updates.
  Timer? _reconnectTimer;
  // Track last broadcast state per canonical key (host!service) to avoid duplicate alerts
  final Map<String, int> _lastBroadcastState = {};
  final Map<String, PersistedAlertState> _persistedStates = {};

  Icinga2EventListener(this.session, this.config);

  /// Start the event listener
  Future<void> start() async {
    session.log('Icinga2EventListener: Starting event listener...',
        level: LogLevel.info);
    await _loadPersistedStates();
    await _reconcileStatesOnStartup();
    final startMessage = '🟢 Iicinga2EventListener: Starting event listener...';
    LogBroadcaster.broadcastLog(startMessage);
    session.log('Starting Iicinga2 event listener...', level: LogLevel.info);

    // Start event streaming in background (don't await) so polling can run as a fallback
    // ignore: unawaited_futures
    _connect();

    // No polling started - we rely on the event stream and websocket for updates.
  }

  Future<void> _reconcileStatesOnStartup() async {
    session.log('Reconciling Icinga states on startup...',
        level: LogLevel.info);
    try {
      final headers = {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final servicesUrl =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/services';

      final response =
          await _ioClient!.get(Uri.parse(servicesUrl), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        for (final serviceData in results) {
          final attrs = serviceData['attrs'];
          final host = attrs['host_name'] as String;
          final service = attrs['name'] as String;
          final state = (attrs['state'] as num).toInt();
          final canonicalKey = _canonicalKey(host, service);

          final persistedState = _persistedStates[canonicalKey];
          if (persistedState == null || persistedState.lastState != state) {
            session.log(
                'Reconciling state for $canonicalKey: persisted=${persistedState?.lastState}, icinga=$state',
                level: LogLevel.info);
            await _persistState(canonicalKey, host, service, state);
          }
        }
        session.log('Finished reconciling ${results.length} services.',
            level: LogLevel.info);
      } else {
        session.log(
            'Failed to fetch services from Icinga for reconciliation. Status: ${response.statusCode}, Body: ${response.body}',
            level: LogLevel.error);
      }
    } catch (e) {
      session.log('Failed to reconcile Icinga states: $e',
          level: LogLevel.error);
    }
  }

  Future<void> _loadPersistedStates() async {
    try {
      final states = await PersistedAlertState.db.find(
        session,
        orderBy: (t) => t.lastUpdated,
      );
      for (final state in states) {
        _persistedStates[state.canonicalKey] = state;
        _lastBroadcastState[state.canonicalKey] = state.lastState;
      }
      session.log('Loaded ${_persistedStates.length} persisted alert states.',
          level: LogLevel.info);
    } catch (e) {
      session.log('Failed to load persisted alert states: $e',
          level: LogLevel.error);
    }
  }

  // Polling removed - no-op.

  // Polling code removed.

  /// Connect to Iicinga2 event stream
  Future<void> _connect() async {
    if (_isShuttingDown) return;

    try {
      session.log(
          'Iicinga2EventListener: Connecting to Iicinga2 at ${config.scheme}://${config.host}:${config.port}',
          level: LogLevel.info);

      // Create HTTP client with SSL settings
      final httpClient = HttpClient();
      if (config.skipCertificateVerification) {
        httpClient.badCertificateCallback = (cert, host, port) => true;
      }

      // Use IOClient to wrap the HttpClient for the http package
      _ioClient = IOClient(httpClient);
      session.log('Iicinga2EventListener: HTTP client created',
          level: LogLevel.debug);

      // Prepare authentication headers
      final credentials =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      // First, test basic connectivity and discover available endpoints
      final testUrl = '${config.scheme}://${config.host}:${config.port}/v1';
      session.log(
          'Iicinga2EventListener: Testing basic connectivity to $testUrl',
          level: LogLevel.debug);

      final testResponse = await _ioClient!
          .get(Uri.parse(testUrl), headers: headers)
          .timeout(Duration(seconds: 30));

      session.log(
          'Iicinga2EventListener: Test response status: ${testResponse.statusCode}',
          level: LogLevel.debug);
      session.log('Iicinga2EventListener: API response: ${testResponse.body}',
          level: LogLevel.debug);

      if (testResponse.statusCode != 200) {
        session.log(
            'Iicinga2EventListener: Basic API test failed: ${testResponse.body}',
            level: LogLevel.error);
        throw Exception(
            'Iicinga2 API not accessible: ${testResponse.statusCode}');
      }

      // Check what endpoints are available
      session.log('Iicinga2EventListener: Checking available endpoints...',
          level: LogLevel.debug);
      final endpointsUrl =
          '${config.scheme}://${config.host}:${config.port}/v1';
      final endpointsResponse = await _ioClient!
          .get(Uri.parse(endpointsUrl), headers: headers)
          .timeout(Duration(seconds: 30));

      session.log(
          'Iicinga2EventListener: Available endpoints response: ${endpointsResponse.body}',
          level: LogLevel.debug);

      // Test other API endpoints to verify functionality
      session.log('Iicinga2EventListener: Testing other API endpoints...',
          level: LogLevel.debug);

      // Test /v1/status endpoint
      final statusUrl =
          '${config.scheme}://${config.host}:${config.port}/v1/status';
      session.log('Iicinga2EventListener: Testing $statusUrl',
          level: LogLevel.debug);
      try {
        final statusResponse = await _ioClient!
            .get(Uri.parse(statusUrl), headers: headers)
            .timeout(Duration(seconds: 10));
        session.log(
            'Iicinga2EventListener: Status endpoint response: ${statusResponse.statusCode}',
            level: LogLevel.debug);
        if (statusResponse.statusCode == 200) {
          session.log(
              'Iicinga2EventListener: Status endpoint works - API is functional',
              level: LogLevel.debug);
        }
      } catch (e) {
        session.log('Iicinga2EventListener: Status endpoint failed: $e',
            level: LogLevel.debug);
      }

      // Test /v1/objects/hosts endpoint
      final objectsUrl =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/hosts';
      session.log('Iicinga2EventListener: Testing $objectsUrl',
          level: LogLevel.debug);
      try {
        final objectsResponse = await _ioClient!
            .get(Uri.parse(objectsUrl), headers: headers)
            .timeout(Duration(seconds: 10));
        session.log(
            'Iicinga2EventListener: Objects endpoint response: ${objectsResponse.statusCode}',
            level: LogLevel.debug);
        if (objectsResponse.statusCode == 200) {
          session.log(
              'Iicinga2EventListener: Objects endpoint works - API permissions are correct',
              level: LogLevel.debug);
        }
      } catch (e) {
        session.log('Iicinga2EventListener: Objects endpoint failed: $e',
            level: LogLevel.debug);
      }

      // Try POST request to /v1/events for event streaming
      session.log(
          'Iicinga2EventListener: Attempting event stream subscription to /v1/events',
          level: LogLevel.debug);

      // For event streaming, we need to use HttpClient directly to access the response stream
      final eventsUrl = Uri.parse(
          '${config.scheme}://${config.host}:${config.port}/v1/events');
      final requestBody = {
        'queue': config.queue,
        'types': config.types,
        if (config.filter.isNotEmpty) 'filter': config.filter,
      };

      session.log(
          'Iicinga2EventListener: Event stream request body: $requestBody',
          level: LogLevel.debug);

      // Use HttpClient directly for streaming response
      final streamHttpClient = HttpClient();
      if (config.skipCertificateVerification) {
        streamHttpClient.badCertificateCallback = (cert, host, port) => true;
      }

      try {
        final request = await streamHttpClient.postUrl(eventsUrl);
        request.headers.set('Authorization', headers['Authorization']!);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('Accept', 'application/json');

        // Write the request body
        request.write(jsonEncode(requestBody));

        session.log('Iicinga2EventListener: Sending POST request to $eventsUrl',
            level: LogLevel.debug);
        // Streaming endpoint can be slow to return and may be long-lived.
        // Allow a generous timeout for the initial response so transient
        // network latency doesn't cause frequent reconnects.
        final response = await request.close().timeout(Duration(seconds: 60));

        session.log(
            'Iicinga2EventListener: Event stream response status: ${response.statusCode}',
            level: LogLevel.debug);
        session.log(
            'Iicinga2EventListener: Event stream response headers: ${response.headers}',
            level: LogLevel.debug);

        if (response.statusCode == 200) {
          session.log(
              'Iicinga2EventListener: Successfully connected to Iicinga2 event stream',
              level: LogLevel.info);
          final connectMessage =
              '🔗 Iicinga2EventListener: Successfully connected to Iicinga2 event stream';
          LogBroadcaster.broadcastLog(connectMessage);
          session.log('Successfully connected to Iicinga2 event stream',
              level: LogLevel.info);
          _retryCount = 0;

          // Process the event stream
          await _processEventStream(response);
        } else {
          session.log(
              'Iicinga2EventListener: Event stream connection failed: ${response.statusCode}',
              level: LogLevel.error);
          final responseBody = await response.transform(utf8.decoder).join();
          session.log('Iicinga2EventListener: Response body: $responseBody',
              level: LogLevel.error);
          throw Exception(
              'Event stream connection failed: HTTP ${response.statusCode}');
        }
      } finally {
        streamHttpClient.close();
      }
    } catch (e) {
      session.log('Iicinga2EventListener: Failed to connect to Iicinga2: $e',
          level: LogLevel.error);

      if (config.reconnectEnabled && !_isShuttingDown) {
        _scheduleReconnect();
      }
    }
  }

  /// Process the event stream response
  Future<void> _processEventStream(HttpClientResponse response) async {
    if (_isShuttingDown) return;

    try {
      session.log('Iicinga2EventListener: Starting to process event stream...',
          level: LogLevel.debug);

      // Convert the response to a stream of lines
      final rawStream =
          response.transform(utf8.decoder).transform(LineSplitter());

      // Wrap the stream with an inactivity timeout so we detect stalled
      // connections. If no data arrives for [inactivityTimeout], the
      // subscription will be cancelled and we schedule a reconnect.
      final inactivityTimeout = Duration(minutes: 2);
      final stream = rawStream.timeout(inactivityTimeout, onTimeout: (sink) {
        session.log(
            'Iicinga2EventListener: Event stream inactive for ${inactivityTimeout.inMinutes} minutes, timing out',
            level: LogLevel.warning);
        try {
          // Record inactivity timestamp
          _lastEventAt = DateTime.now();
          // Close the sink to break the await-for loop
          sink.close();
        } catch (_) {}
      });

      await for (final line in stream) {
        if (_isShuttingDown) break;

        if (line.trim().isNotEmpty) {
          // Uncomment for debugging: session.log('Iicinga2EventListener: Received event line: $line', level: LogLevel.debug);
          try {
            final event = jsonDecode(line);

            // Special debugging for integrasjoner events
            if (event['host'] == 'integrasjoner') {
              session.log(
                  '🎯 INTEGRASJONER EVENT RECEIVED: ${event['type']} for ${event['host']}/${event['service']}',
                  level: LogLevel.debug);
            }

            // Log all events for debugging (increased from 5 to 20)
            if (_debugEventCount < 20) {
              session.log(
                  'Iicinga2EventListener: Processing event type: ${event['type']}, host: ${event['host']}, service: ${event['service']}',
                  level: LogLevel.debug);
              _debugEventCount++;
            }

            // Also log every 100th event to see ongoing activity
            if (_debugEventCount % 100 == 0) {
              session.log(
                  'Iicinga2EventListener: Still processing events... count: $_debugEventCount, last: ${event['type']} for ${event['host']}/${event['service']}',
                  level: LogLevel.debug);
            }

            _lastEventAt = DateTime.now();
            _handleEvent(event);
          } catch (e) {
            session.log('Failed to parse event: $e', level: LogLevel.warning);
            session.log('Raw event data: $line', level: LogLevel.debug);
          }
        } else {
          session.log(
              'Iicinga2EventListener: Received empty line from event stream',
              level: LogLevel.debug);
        }
      }

      session.log('Iicinga2EventListener: Event stream ended',
          level: LogLevel.info);

      // If the stream ended unexpectedly (not during shutdown), schedule a
      // reconnect so we resume listening automatically. This prevents the
      // listener from stopping permanently when the connection drops.
      if (config.reconnectEnabled && !_isShuttingDown) {
        session.log('Event stream ended unexpectedly, scheduling reconnect',
            level: LogLevel.warning);
        _scheduleReconnect();
      }
    } catch (e) {
      session.log('Iicinga2EventListener: Error processing event stream: $e',
          level: LogLevel.error);
      session.log('Error processing event stream: $e', level: LogLevel.error);

      // Reconnection will be scheduled below if configured.

      if (config.reconnectEnabled && !_isShuttingDown) {
        _scheduleReconnect();
      }
    }
  }

  /// Handle incoming events
  void _handleEvent(Map<String, dynamic> event) {
    try {
      final icingaEvent = Icinga2Event.fromJson(event);
      session.log(
          'Received ${icingaEvent.type} event for ${icingaEvent.host}${icingaEvent.service != null ? '/${icingaEvent.service}' : ''}',
          level: LogLevel.info);

      // Route to specific event handler based on type
      switch (icingaEvent.type) {
        case 'CheckResult':
          _handleCheckResult(icingaEvent as CheckResultEvent);
          break;
        case 'StateChange':
          _handleStateChange(icingaEvent as StateChangeEvent);
          break;
        case 'Notification':
          _handleNotification(icingaEvent as NotificationEvent);
          break;
        case 'AcknowledgementSet':
          _handleAcknowledgementSet(icingaEvent as AcknowledgementSetEvent);
          break;
        case 'AcknowledgementCleared':
          _handleAcknowledgementCleared(
              icingaEvent as AcknowledgementClearedEvent);
          break;
        case 'CommentAdded':
          _handleCommentAdded(icingaEvent as CommentAddedEvent);
          break;
        case 'CommentRemoved':
          _handleCommentRemoved(icingaEvent as CommentRemovedEvent);
          break;
        case 'DowntimeAdded':
          _handleDowntimeAdded(icingaEvent as DowntimeAddedEvent);
          break;
        case 'DowntimeRemoved':
          _handleDowntimeRemoved(icingaEvent as DowntimeRemovedEvent);
          break;
        case 'DowntimeStarted':
          _handleDowntimeStarted(icingaEvent as DowntimeStartedEvent);
          break;
        case 'DowntimeTriggered':
          _handleDowntimeTriggered(icingaEvent as DowntimeTriggeredEvent);
          break;
        case 'ObjectCreated':
          _handleObjectCreated(icingaEvent as ObjectCreatedEvent);
          break;
        case 'ObjectModified':
          _handleObjectModified(icingaEvent as ObjectModifiedEvent);
          break;
        case 'ObjectDeleted':
          _handleObjectDeleted(icingaEvent as ObjectDeletedEvent);
          break;
        default:
          _handleUnknownEvent(icingaEvent as UnknownEvent);
      }
    } catch (e) {
      session.log('Failed to process event: $e', level: LogLevel.error);
      session.log('Raw event data: $event', level: LogLevel.debug);
    }
  }

  /// Helper to decide if we should broadcast alerts to the web UI.
  /// Only events originating from the `integrasjoner` host are broadcast.
  bool _shouldBroadcastForHost(String host) {
    // Normalize host (lowercase, strip domain) before comparing so
    // events from e.g. "integrasjoner.example.local" or different
    // case variants still match the intended host.
    final baseHost = host.split('.').first.toLowerCase().trim();
    return baseHost == 'integrasjoner';
  }

  /// Canonical key for a service: host!service (service may be empty)
  String _canonicalKey(String host, String? service) {
    // Normalize host and service parts so the same logical service maps
    // to a single canonical key even if host/service casing or domain
    // suffixes differ between events.
    final baseHost = host.split('.').first.toLowerCase().trim();
    final svc = service?.toLowerCase().trim() ?? '';
    return '$baseHost!$svc';
  }

  Future<void> _persistState(
      String canonicalKey, String host, String? service, int state) async {
    try {
      var persistedState = _persistedStates[canonicalKey];
      if (persistedState == null) {
        persistedState = PersistedAlertState(
          host: host,
          service: service,
          canonicalKey: canonicalKey,
          lastState: state,
          lastUpdated: DateTime.now(),
        );
        await PersistedAlertState.db.insertRow(session, persistedState);
      } else {
        persistedState.lastState = state;
        persistedState.lastUpdated = DateTime.now();
        await PersistedAlertState.db.updateRow(session, persistedState);
      }
      _persistedStates[canonicalKey] = persistedState;
    } catch (e) {
      session.log('Failed to persist state for $canonicalKey: $e',
          level: LogLevel.error);
    }
  }

  /// Helper to produce a friendly host/service label without showing '/null'
  String _hostServiceLabel(String host, String? service) {
    final baseHost = host.split('.').first.toLowerCase().trim();
    if (service == null || service.toString().trim().isEmpty) {
      return baseHost;
    }
    final svc = service.toString().trim();
    return '$baseHost/$svc';
  }

  /// Return true if we should broadcast this state for the given key.
  /// Ensures we only broadcast a given state once per key until it changes.
  bool _shouldBroadcastForKey(String key, int state) {
    final last = _lastBroadcastState[key];
    // Debug: log transitions to help understand missed broadcasts
    if (last == state) {
      session.log('No broadcast for $key: state unchanged ($state)',
          level: LogLevel.debug);
      return false;
    }
    session.log(
        'Broadcasting for $key: state changed ${last ?? 'null'} -> $state',
        level: LogLevel.debug);
    _lastBroadcastState[key] = state;
    return true;
  }

  /// Convert a check_result map or state string/exit code to an integer state code.
  /// 0 = OK, 1 = WARNING, 2 = CRITICAL, 3 = UNKNOWN
  // NOTE: _stateCodeFromCheckResult was removed because it was unused.

  /// Handle check result events
  void _handleCheckResult(CheckResultEvent event) {
    // Process check result based on state and exit code
    final rawState = event.checkResult['state'];
    final exitCode = event.checkResult['exit_code'] ?? -1;
    final output = event.checkResult['output'] ?? '';

    // Determine numeric state code robustly: accept numeric codes or string names
    int stateCode;
    if (rawState is num) {
      stateCode = rawState.toInt();
    } else if (rawState is String) {
      switch (rawState.toUpperCase()) {
        case 'OK':
          stateCode = 0;
          break;
        case 'WARNING':
          stateCode = 1;
          break;
        case 'CRITICAL':
          stateCode = 2;
          break;
        case 'UNKNOWN':
        default:
          stateCode = 3;
      }
    } else {
      // Fallback to exitCode if state not provided
      stateCode = (exitCode >= 0)
          ? (exitCode == 2 ? 2 : (exitCode == 1 ? 1 : (exitCode == 0 ? 0 : 3)))
          : 3;
    }

    // Check if this is a hard state (state_type == 1) - if not available, assume hard for critical
    final stateType =
        event.checkResult['state_type'] ?? (exitCode == 2 ? 1 : 0);
    final isHardState = stateType == 1;

    // Check if service is in downtime or acknowledged
    final isInDowntime = (event.checkResult['downtime_depth'] ?? 0) > 0;
    final isAcknowledged = event.checkResult['acknowledgement'] ?? false;

    // Don't alert if in downtime or acknowledged
    final shouldAlert = isHardState && !isInDowntime && !isAcknowledged;

    // Only alert on HARD states for WARNING and CRITICAL, but always log OK recoveries
    final canonical = _canonicalKey(event.host, event.service);
    _persistState(canonical, event.host, event.service, stateCode);
    session.log(
        'CheckResult decision for $canonical: stateCode=$stateCode exitCode=$exitCode isHard=$isHardState shouldAlert=$shouldAlert',
        level: LogLevel.debug);

    if (stateCode == 2 && shouldAlert) {
      session.log(
          '🚨 ALERT CRITICAL: ${_hostServiceLabel(event.host, event.service)} - $output',
          level: LogLevel.error);
      session.log(
          'ALERT: Service ${event.service} on ${event.host} is CRITICAL!',
          level: LogLevel.error);
      // TODO: Send critical alert to duty officer
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, 2)) {
        LogBroadcaster.broadcastLog(
            '🚨 ALERT CRITICAL: ${_hostServiceLabel(event.host, event.service)} - $output');
      }
    } else if (stateCode == 1 && shouldAlert) {
      session.log(
          '⚠️ ALERT WARNING: ${_hostServiceLabel(event.host, event.service)} - $output',
          level: LogLevel.warning);
      session.log('ALERT: Service ${event.service} on ${event.host} is WARNING',
          level: LogLevel.warning);
      // TODO: Send warning notification
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, 1)) {
        LogBroadcaster.broadcastLog(
            '⚠️ ALERT WARNING: ${_hostServiceLabel(event.host, event.service)} - $output');
      }
    } else if (stateCode == 0) {
      // OK recovery: always log and broadcast recoveries
      // For recoveries, do not include plugin/check output (may contain secrets).
      session.log(
          '✅ ALERT RECOVERY: ${_hostServiceLabel(event.host, event.service)}',
          level: LogLevel.info);
      session.log(
          'RECOVERY: Service ${event.service} on ${event.host} is back OK',
          level: LogLevel.info);
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, 0)) {
        LogBroadcaster.broadcastLog(
            '✅ ALERT RECOVERY: ${_hostServiceLabel(event.host, event.service)}');
      }

      // Ensure we record the recovery state so subsequent alerts are
      // recognized. If the recovery was not broadcast for some reason
      // (soft state, suppression, etc.), updating the last state here
      // prevents the previous ALERT state from blocking future alerts.
      try {
        _lastBroadcastState[canonical] = 0;
        session.log('Recorded recovery state for $canonical -> 0',
            level: LogLevel.debug);
      } catch (_) {}
    } else if (isInDowntime || isAcknowledged) {
      // Log suppressed alerts due to downtime/acknowledgement
      final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
      session.log(
          'ALERT SUPPRESSED ($reason): ${_hostServiceLabel(event.host, event.service)} - $output',
          level: LogLevel.info);
      session.log(
          'ALERT SUPPRESSED ($reason): ${_hostServiceLabel(event.host, event.service)} - $stateCode',
          level: LogLevel.info);
    } else if (stateCode == 2 && !isHardState) {
      // Log soft critical states without alerting
      session.log(
          'SOFT CRITICAL: ${_hostServiceLabel(event.host, event.service)} - $output',
          level: LogLevel.warning);
    } else if (stateCode == 1 && !isHardState) {
      // Log soft warning states without alerting
      session.log(
          'SOFT WARNING: ${_hostServiceLabel(event.host, event.service)} - $output',
          level: LogLevel.info);
    } else {
      session.log(
          'UNKNOWN: ${_hostServiceLabel(event.host, event.service)} - $output',
          level: LogLevel.warning);
    }

    // TODO: Store check result in database for historical tracking
    // TODO: Update monitoring dashboard
  }

  /// Handle state change events
  void _handleStateChange(StateChangeEvent event) {
    // Map state codes to readable names
    final stateNames = {
      0: 'OK',
      1: 'WARNING',
      2: 'CRITICAL',
      3: 'UNKNOWN',
      99: 'PENDING'
    };

    final stateTypeNames = {0: 'SOFT', 1: 'HARD'};

    final stateName = stateNames[event.state] ?? 'UNKNOWN';
    final stateTypeName = stateTypeNames[event.stateType] ?? 'UNKNOWN';

    // Only alert on HARD states (stateType == 1), not SOFT states (stateType == 0)
    final isHardState = event.stateType == 1;

    // Check if service is in downtime or acknowledged
    final isInDowntime = event.downtimeDepth > 0;
    final isAcknowledged = event.acknowledgement;

    // Don't alert if in downtime or acknowledged
    final shouldAlert = isHardState && !isInDowntime && !isAcknowledged;

    // Log state changes with appropriate severity - but only alert on hard states
    final canonical = _canonicalKey(event.host, event.service);
    _persistState(canonical, event.host, event.service, event.state);
    session.log(
        'StateChange decision for $canonical: state=${event.state} type=${event.stateType} isHard=$isHardState shouldAlert=$shouldAlert',
        level: LogLevel.debug);
    if (event.state == 2 && shouldAlert) {
      // CRITICAL - Hard state only, not in downtime/acknowledged
      session.log(
          '🚨 ALERT CRITICAL: ${_hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)',
          level: LogLevel.error);
      final logMessage =
          '🚨 ALERT CRITICAL: ${_hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)';
      session.log(logMessage, level: LogLevel.error);
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, event.state)) {
        LogBroadcaster.broadcastLog(logMessage);
      }
      // TODO: Trigger critical alert escalation
    } else if (event.state == 1 && shouldAlert) {
      // WARNING - Hard state only, not in downtime/acknowledged
      session.log(
          '⚠️ ALERT WARNING: ${_hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)',
          level: LogLevel.warning);
      final logMessage =
          '⚠️ ALERT WARNING: ${_hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)';
      session.log(logMessage, level: LogLevel.warning);
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, event.state)) {
        LogBroadcaster.broadcastLog(logMessage);
      }
      // TODO: Send warning notification
    } else if (event.state == 0 && isHardState) {
      // OK - Hard state recovery (always alert recoveries)
      session.log(
          '✅ ALERT RECOVERY: ${_hostServiceLabel(event.host, event.service)} recovered to $stateName ($stateTypeName)',
          level: LogLevel.info);
      final logMessage =
          '✅ ALERT RECOVERY: ${_hostServiceLabel(event.host, event.service)} recovered to $stateName ($stateTypeName)';
      session.log(logMessage, level: LogLevel.info);
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, event.state)) {
        LogBroadcaster.broadcastLog(logMessage);
      }
      // TODO: Clear active alerts
    } else if (isInDowntime || isAcknowledged) {
      // Log suppressed alerts due to downtime/acknowledgement
      final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
      session.log(
          'ALERT SUPPRESSED ($reason): ${_hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)',
          level: LogLevel.info);
      final logMessage =
          '🔕 ALERT SUPPRESSED ($reason): ${_hostServiceLabel(event.host, event.service)} - $stateName';
      session.log(logMessage, level: LogLevel.info);
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, event.state)) {
        LogBroadcaster.broadcastLog(logMessage);
      }
    } else {
      // Log soft states or unknown states without alerting
      session.log(
          'STATE CHANGE (Soft): ${_hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)',
          level: LogLevel.info);
    }

    // TODO: Update service status dashboard
    // TODO: Record state change history
  }

  /// Handle notification events
  void _handleNotification(NotificationEvent event) {
    // Process different types of notifications
    final notificationType = event.notificationType;
    final users = event.users.join(', ');
    final command = event.command;

    // Check if this notification is for a hard state
    final stateType = event.checkResult['state_type'] ??
        1; // Default to hard if not specified
    final isHardState = stateType == 1;

    // Check if service is in downtime or acknowledged
    final isInDowntime = (event.checkResult['downtime_depth'] ?? 0) > 0;
    final isAcknowledged = event.checkResult['acknowledgement'] ?? false;

    // Don't alert if in downtime or acknowledged
    final shouldAlert = isHardState && !isInDowntime && !isAcknowledged;

    session.log(
        'NOTIFICATION: $notificationType sent to $users via $command for ${_hostServiceLabel(event.host, event.service)} (State: ${isHardState ? 'HARD' : 'SOFT'})',
        level: LogLevel.info);

    // TODO: Store notification in database for audit trail
    // TODO: Forward notification to external systems (SMS, email, etc.)
    // TODO: Update notification dashboard

    // Only escalate on hard state notifications, not in downtime/acknowledged
    if (shouldAlert &&
        (notificationType.contains('PROBLEM') ||
            notificationType.contains('CRITICAL'))) {
      session.log(
          '🚨 PROBLEM NOTIFICATION: Immediate attention required for ${_hostServiceLabel(event.host, event.service)}',
          level: LogLevel.warning);
      session.log(
          'PROBLEM NOTIFICATION: ${_hostServiceLabel(event.host, event.service)} needs immediate attention!',
          level: LogLevel.warning);
      // TODO: Escalate to on-call duty officer
    } else if (shouldAlert &&
        (notificationType.contains('RECOVERY') ||
            notificationType.contains('OK'))) {
      session.log(
          '✅ RECOVERY NOTIFICATION: ${_hostServiceLabel(event.host, event.service)} has recovered',
          level: LogLevel.info);
      session.log(
          'RECOVERY NOTIFICATION: ${_hostServiceLabel(event.host, event.service)} is back OK',
          level: LogLevel.info);
      // TODO: Clear active alerts
    } else if (isInDowntime || isAcknowledged) {
      // Log suppressed notifications due to downtime/acknowledgement
      final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
      session.log(
          'NOTIFICATION SUPPRESSED ($reason): $notificationType for ${_hostServiceLabel(event.host, event.service)}',
          level: LogLevel.info);
      session.log(
          'NOTIFICATION SUPPRESSED ($reason): ${_hostServiceLabel(event.host, event.service)} - $notificationType',
          level: LogLevel.info);
    } else if (!isHardState) {
      session.log(
          'SOFT STATE NOTIFICATION: ${_hostServiceLabel(event.host, event.service)} - $notificationType (not escalating)',
          level: LogLevel.info);
    }
  }

  /// Handle acknowledgement set events
  void _handleAcknowledgementSet(AcknowledgementSetEvent event) {
    final author = event.author;
    final comment = event.comment;

    session.log(
        'ACKNOWLEDGEMENT SET: ${_hostServiceLabel(event.host, event.service)} acknowledged by $author: $comment',
        level: LogLevel.info);

    // TODO: Store acknowledgement in database
    // TODO: Update incident management system
    // TODO: Notify team that issue is being handled
    // TODO: Stop escalation notifications for this service
  }

  /// Handle acknowledgement cleared events
  void _handleAcknowledgementCleared(AcknowledgementClearedEvent event) {
    session.log(
        'ACKNOWLEDGEMENT CLEARED: ${_hostServiceLabel(event.host, event.service)} acknowledgement removed',
        level: LogLevel.info);

    // TODO: Update incident management system
    // TODO: Resume escalation notifications if problem persists
    // TODO: Notify team that acknowledgement was cleared
  }

  /// Handle comment added events
  void _handleCommentAdded(CommentAddedEvent event) {
    // TODO: Implement comment added processing
    session.log('Processing comment added: ${event.comment}',
        level: LogLevel.debug);
  }

  /// Handle comment removed events
  void _handleCommentRemoved(CommentRemovedEvent event) {
    // TODO: Implement comment removed processing
    session.log('Processing comment removed: ${event.comment}',
        level: LogLevel.debug);
  }

  /// Handle downtime added events
  void _handleDowntimeAdded(DowntimeAddedEvent event) {
    // TODO: Implement downtime added processing
    session.log('Processing downtime added: ${event.downtime}',
        level: LogLevel.debug);
  }

  /// Handle downtime removed events
  void _handleDowntimeRemoved(DowntimeRemovedEvent event) {
    // TODO: Implement downtime removed processing
    session.log('Processing downtime removed: ${event.downtime}',
        level: LogLevel.debug);
  }

  /// Handle downtime started events
  void _handleDowntimeStarted(DowntimeStartedEvent event) {
    // TODO: Implement downtime started processing
    session.log('Processing downtime started: ${event.downtime}',
        level: LogLevel.debug);
  }

  /// Handle downtime triggered events
  void _handleDowntimeTriggered(DowntimeTriggeredEvent event) {
    // TODO: Implement downtime triggered processing
    session.log('Processing downtime triggered: ${event.downtime}',
        level: LogLevel.debug);
  }

  /// Handle object created events
  void _handleObjectCreated(ObjectCreatedEvent event) {
    // TODO: Implement object created processing
    session.log(
        'Processing object created: ${event.objectType} ${event.objectName}',
        level: LogLevel.debug);
  }

  /// Handle object modified events
  void _handleObjectModified(ObjectModifiedEvent event) {
    // TODO: Implement object modified processing
    session.log(
        'Processing object modified: ${event.objectType} ${event.objectName}',
        level: LogLevel.debug);
  }

  /// Handle object deleted events
  void _handleObjectDeleted(ObjectDeletedEvent event) {
    // TODO: Implement object deleted processing
    session.log(
        'Processing object deleted: ${event.objectType} ${event.objectName}',
        level: LogLevel.debug);
  }

  /// Handle unknown events
  void _handleUnknownEvent(UnknownEvent event) {
    // TODO: Implement unknown event processing
    session.log('Processing unknown event type: ${event.type}',
        level: LogLevel.debug);
    session.log('Raw data: ${event.rawData}', level: LogLevel.debug);
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_retryCount >= config.maxRetries) {
      session.log('Max reconnection attempts reached, giving up',
          level: LogLevel.error);
      return;
    }

    _retryCount++;
    // Exponential backoff with cap and jitter
    final base = config.reconnectDelay; // base seconds
    final maxDelay = 300; // cap at 5 minutes
    var delaySeconds = base * (1 << (_retryCount - 1));
    if (delaySeconds > maxDelay) delaySeconds = maxDelay;
    // add jitter +/- 20%
    final jitterRange = (delaySeconds * 0.2).toInt();
    final jitter =
        (DateTime.now().millisecondsSinceEpoch % (jitterRange * 2 + 1)) -
            jitterRange;
    delaySeconds = (delaySeconds + jitter).clamp(1, maxDelay);

    session.log(
        'Scheduling reconnection attempt $_retryCount in $delaySeconds seconds (lastEventAt=${_lastEventAt?.toIso8601String() ?? 'never'})',
        level: LogLevel.info);

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isShuttingDown) {
        _connect();
      }
    });
  }

  /// Stop the event listener and clean up resources
  /// Cancels any pending reconnect timer and closes the HTTP client.
  Future<void> stop() async {
    _isShuttingDown = true;

    if (_reconnectTimer?.isActive ?? false) {
      _reconnectTimer?.cancel();
    }
    _reconnectTimer = null;

    try {
      _ioClient?.close();
    } catch (_) {
      // ignore errors during shutdown
    }
    _ioClient = null;

    session.log('Icinga2EventListener: Stopped', level: LogLevel.info);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:serverpod/serverpod.dart';
import 'icinga2_events.dart';
import 'web/routes/log_viewer.dart';

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

  // Polling has been removed - the event stream (and websocket) provide live updates.
  Timer? _reconnectTimer;
  // Track last broadcast state per canonical key (host!service) to avoid duplicate alerts
  final Map<String, int> _lastBroadcastState = {};

  Icinga2EventListener(this.session, this.config);

  /// Start the event listener
  Future<void> start() async {
    print('Icinga2EventListener: Starting event listener...');
    final startMessage = '🟢 Icinga2EventListener: Starting event listener...';
    LogBroadcaster.broadcastLog(startMessage);
    session.log('Starting Icinga2 event listener...', level: LogLevel.info);

    // Start event streaming in background (don't await) so polling can run as a fallback
    _connect();

    // No polling started - we rely on the event stream and websocket for updates.
  }

  // Polling removed - no-op.

  // Polling code removed.

  /// Connect to Icinga2 event stream
  Future<void> _connect() async {
    if (_isShuttingDown) return;

    try {
      print(
          'Icinga2EventListener: Connecting to Icinga2 at ${config.scheme}://${config.host}:${config.port}');
      session.log(
          'Connecting to Icinga2 at ${config.scheme}://${config.host}:${config.port}',
          level: LogLevel.info);

      // Create HTTP client with SSL settings
      final httpClient = HttpClient();
      if (config.skipCertificateVerification) {
        httpClient.badCertificateCallback = (cert, host, port) => true;
      }

      // Use IOClient to wrap the HttpClient for the http package
      _ioClient = IOClient(httpClient);
      print('Icinga2EventListener: HTTP client created');

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
      print('Icinga2EventListener: Testing basic connectivity to $testUrl');

      final testResponse = await _ioClient!
          .get(Uri.parse(testUrl), headers: headers)
          .timeout(Duration(seconds: 10));

      print(
          'Icinga2EventListener: Test response status: ${testResponse.statusCode}');
      print('Icinga2EventListener: API response: ${testResponse.body}');

      if (testResponse.statusCode != 200) {
        print(
            'Icinga2EventListener: Basic API test failed: ${testResponse.body}');
        throw Exception(
            'Icinga2 API not accessible: ${testResponse.statusCode}');
      }

      // Check what endpoints are available
      print('Icinga2EventListener: Checking available endpoints...');
      final endpointsUrl =
          '${config.scheme}://${config.host}:${config.port}/v1';
      final endpointsResponse = await _ioClient!
          .get(Uri.parse(endpointsUrl), headers: headers)
          .timeout(Duration(seconds: 10));

      print(
          'Icinga2EventListener: Available endpoints response: ${endpointsResponse.body}');

      // Test other API endpoints to verify functionality
      print('Icinga2EventListener: Testing other API endpoints...');

      // Test /v1/status endpoint
      final statusUrl =
          '${config.scheme}://${config.host}:${config.port}/v1/status';
      print('Icinga2EventListener: Testing $statusUrl');
      try {
        final statusResponse = await _ioClient!
            .get(Uri.parse(statusUrl), headers: headers)
            .timeout(Duration(seconds: 5));
        print(
            'Icinga2EventListener: Status endpoint response: ${statusResponse.statusCode}');
        if (statusResponse.statusCode == 200) {
          print(
              'Icinga2EventListener: Status endpoint works - API is functional');
        }
      } catch (e) {
        print('Icinga2EventListener: Status endpoint failed: $e');
      }

      // Test /v1/objects/hosts endpoint
      final objectsUrl =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/hosts';
      print('Icinga2EventListener: Testing $objectsUrl');
      try {
        final objectsResponse = await _ioClient!
            .get(Uri.parse(objectsUrl), headers: headers)
            .timeout(Duration(seconds: 5));
        print(
            'Icinga2EventListener: Objects endpoint response: ${objectsResponse.statusCode}');
        if (objectsResponse.statusCode == 200) {
          print(
              'Icinga2EventListener: Objects endpoint works - API permissions are correct');
        }
      } catch (e) {
        print('Icinga2EventListener: Objects endpoint failed: $e');
      }

      // Try POST request to /v1/events for event streaming
      print(
          'Icinga2EventListener: Attempting event stream subscription to /v1/events');

      // For event streaming, we need to use HttpClient directly to access the response stream
      final eventsUrl = Uri.parse(
          '${config.scheme}://${config.host}:${config.port}/v1/events');
      final requestBody = {
        'queue': config.queue,
        'types': config.types,
        if (config.filter.isNotEmpty) 'filter': config.filter,
      };

      print('Icinga2EventListener: Event stream request body: $requestBody');

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

        print('Icinga2EventListener: Sending POST request to $eventsUrl');
        final response = await request.close().timeout(Duration(seconds: 10));

        print(
            'Icinga2EventListener: Event stream response status: ${response.statusCode}');
        print(
            'Icinga2EventListener: Event stream response headers: ${response.headers}');

        if (response.statusCode == 200) {
          print(
              'Icinga2EventListener: Successfully connected to Icinga2 event stream');
          final connectMessage =
              '🔗 Icinga2EventListener: Successfully connected to Icinga2 event stream';
          LogBroadcaster.broadcastLog(connectMessage);
          session.log('Successfully connected to Icinga2 event stream',
              level: LogLevel.info);
          _retryCount = 0;

          // Process the event stream
          await _processEventStream(response);
        } else {
          print(
              'Icinga2EventListener: Event stream connection failed: ${response.statusCode}');
          final responseBody = await response.transform(utf8.decoder).join();
          print('Icinga2EventListener: Response body: $responseBody');
          throw Exception(
              'Event stream connection failed: HTTP ${response.statusCode}');
        }
      } finally {
        streamHttpClient.close();
      }
    } catch (e) {
      print('Icinga2EventListener: Failed to connect to Icinga2: $e');
      session.log('Failed to connect to Icinga2: $e', level: LogLevel.error);

      if (config.reconnectEnabled && !_isShuttingDown) {
        _scheduleReconnect();
      }
    }
  }

  /// Process the event stream response
  Future<void> _processEventStream(HttpClientResponse response) async {
    if (_isShuttingDown) return;

    try {
      print('Icinga2EventListener: Starting to process event stream...');

      // Convert the response to a stream of lines
      final stream = response.transform(utf8.decoder).transform(LineSplitter());

      await for (final line in stream) {
        if (_isShuttingDown) break;

        if (line.trim().isNotEmpty) {
          // Uncomment for debugging: print('Icinga2EventListener: Received event line: $line');
          try {
            final event = jsonDecode(line);

            // Special debugging for integrasjoner events
            if (event['host'] == 'integrasjoner') {
              print(
                  '🎯 INTEGRASJONER EVENT RECEIVED: ${event['type']} for ${event['host']}/${event['service']}');
            }

            // Log all events for debugging (increased from 5 to 20)
            if (_debugEventCount < 20) {
              print(
                  'Icinga2EventListener: Processing event type: ${event['type']}, host: ${event['host']}, service: ${event['service']}');
              _debugEventCount++;
            }

            // Also log every 100th event to see ongoing activity
            if (_debugEventCount % 100 == 0) {
              print(
                  'Icinga2EventListener: Still processing events... count: $_debugEventCount, last: ${event['type']} for ${event['host']}/${event['service']}');
            }

            _handleEvent(event);
          } catch (e) {
            session.log('Failed to parse event: $e', level: LogLevel.warning);
            session.log('Raw event data: $line', level: LogLevel.debug);
          }
        } else {
          print('Icinga2EventListener: Received empty line from event stream');
        }
      }

      print('Icinga2EventListener: Event stream ended');

      // If the stream ended unexpectedly (not during shutdown), schedule a
      // reconnect so we resume listening automatically. This prevents the
      // listener from stopping permanently when the connection drops.
      if (config.reconnectEnabled && !_isShuttingDown) {
        session.log('Event stream ended unexpectedly, scheduling reconnect',
            level: LogLevel.warning);
        _scheduleReconnect();
      }
    } catch (e) {
      print('Icinga2EventListener: Error processing event stream: $e');
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
    session.log('Broadcasting for $key: state changed ${last ?? 'null'} -> $state',
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
    final state = event.checkResult['state'] ?? 'UNKNOWN';
    final exitCode = event.checkResult['exit_code'] ?? -1;
    final output = event.checkResult['output'] ?? '';

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
  // Diagnostic logging to help debug missed broadcasts where an OK recovery
  // is observed but later ALERTs aren't emitted. This prints host/service
  // canonicalization and decision flags.
  session.log(
    'CheckResult decision for $canonical: state=$state exitCode=$exitCode isHard=$isHardState shouldAlert=$shouldAlert',
    level: LogLevel.debug);
    if ((state == 'CRITICAL' || exitCode == 2) && shouldAlert) {
      session.log('🚨 ALERT CRITICAL: ${event.host}/${event.service} - $output',
          level: LogLevel.error);
      print(
          '🚨 🚨 🚨 ALERT: Service ${event.service} on ${event.host} is CRITICAL! 🚨 🚨 🚨');
      // TODO: Send critical alert to duty officer
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, 2)) {
        LogBroadcaster.broadcastLog(
            '🚨 ALERT CRITICAL: ${event.host}/${event.service} - $output');
      }
    } else if ((state == 'WARNING' || exitCode == 1) && shouldAlert) {
      session.log('⚠️ ALERT WARNING: ${event.host}/${event.service} - $output',
          level: LogLevel.warning);
      print('⚠️ ALERT: Service ${event.service} on ${event.host} is WARNING');
      // TODO: Send warning notification
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, 1)) {
        LogBroadcaster.broadcastLog(
            '⚠️ ALERT WARNING: ${event.host}/${event.service} - $output');
      }
    } else if (state == 'OK' || exitCode == 0) {
      session.log('✅ ALERT RECOVERY: ${event.host}/${event.service} - $output',
          level: LogLevel.info);
      print(
          '✅ ✅ ✅ RECOVERY: Service ${event.service} on ${event.host} is back OK! ✅ ✅ ✅');
  if (!_shouldBroadcastForHost(event.host)) {
    session.log('Skipping broadcast for $canonical: host filter mismatch',
    level: LogLevel.debug);
  } else if (_shouldBroadcastForKey(canonical, 0)) {
    LogBroadcaster.broadcastLog(
    '✅ ALERT RECOVERY: ${event.host}/${event.service} - $output');
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
          'ALERT SUPPRESSED ($reason): ${event.host}/${event.service} - $output',
          level: LogLevel.info);
      print(
          '🔕 ALERT SUPPRESSED ($reason): ${event.host}/${event.service} - $state');
    } else if ((state == 'CRITICAL' || exitCode == 2) && !isHardState) {
      // Log soft critical states without alerting
      session.log('SOFT CRITICAL: ${event.host}/${event.service} - $output',
          level: LogLevel.warning);
    } else if ((state == 'WARNING' || exitCode == 1) && !isHardState) {
      // Log soft warning states without alerting
      session.log('SOFT WARNING: ${event.host}/${event.service} - $output',
          level: LogLevel.info);
    } else {
      session.log('UNKNOWN: ${event.host}/${event.service} - $output',
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
  session.log(
    'StateChange decision for $canonical: state=${event.state} type=${event.stateType} isHard=$isHardState shouldAlert=$shouldAlert',
    level: LogLevel.debug);
    if (event.state == 2 && shouldAlert) {
      // CRITICAL - Hard state only, not in downtime/acknowledged
      session.log(
          '🚨 ALERT CRITICAL: ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
          level: LogLevel.error);
      final logMessage =
          '🚨 ALERT CRITICAL: ${event.host}/${event.service} changed to $stateName ($stateTypeName)';
      print(logMessage);
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
          '⚠️ ALERT WARNING: ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
          level: LogLevel.warning);
      final logMessage =
          '⚠️ ALERT WARNING: ${event.host}/${event.service} changed to $stateName ($stateTypeName)';
      print(logMessage);
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
          '✅ ALERT RECOVERY: ${event.host}/${event.service} recovered to $stateName ($stateTypeName)',
          level: LogLevel.info);
      final logMessage =
          '✅ ALERT RECOVERY: ${event.host}/${event.service} recovered to $stateName ($stateTypeName)';
      print(logMessage);
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
          'ALERT SUPPRESSED ($reason): ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
          level: LogLevel.info);
      final logMessage =
          '🔕 ALERT SUPPRESSED ($reason): ${event.host}/${event.service} - $stateName';
      print(logMessage);
      if (!_shouldBroadcastForHost(event.host)) {
        session.log('Skipping broadcast for $canonical: host filter mismatch',
            level: LogLevel.debug);
      } else if (_shouldBroadcastForKey(canonical, event.state)) {
        LogBroadcaster.broadcastLog(logMessage);
      }
    } else {
      // Log soft states or unknown states without alerting
      session.log(
          'STATE CHANGE (Soft): ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
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
        'NOTIFICATION: $notificationType sent to $users via $command for ${event.host}/${event.service} (State: ${isHardState ? 'HARD' : 'SOFT'})',
        level: LogLevel.info);

    // TODO: Store notification in database for audit trail
    // TODO: Forward notification to external systems (SMS, email, etc.)
    // TODO: Update notification dashboard

    // Only escalate on hard state notifications, not in downtime/acknowledged
    if (shouldAlert &&
        (notificationType.contains('PROBLEM') ||
            notificationType.contains('CRITICAL'))) {
      session.log(
          '🚨 PROBLEM NOTIFICATION: Immediate attention required for ${event.host}/${event.service}',
          level: LogLevel.warning);
      print(
          '🚨 🚨 🚨 PROBLEM NOTIFICATION: ${event.host}/${event.service} needs immediate attention! 🚨 🚨 🚨');
      // TODO: Escalate to on-call duty officer
    } else if (shouldAlert &&
        (notificationType.contains('RECOVERY') ||
            notificationType.contains('OK'))) {
      session.log(
          '✅ RECOVERY NOTIFICATION: ${event.host}/${event.service} has recovered',
          level: LogLevel.info);
      print(
          '✅ ✅ ✅ RECOVERY NOTIFICATION: ${event.host}/${event.service} is back OK! ✅ ✅ ✅');
      // TODO: Clear active alerts
    } else if (isInDowntime || isAcknowledged) {
      // Log suppressed notifications due to downtime/acknowledgement
      final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
      session.log(
          'NOTIFICATION SUPPRESSED ($reason): $notificationType for ${event.host}/${event.service}',
          level: LogLevel.info);
      print(
          '🔕 NOTIFICATION SUPPRESSED ($reason): ${event.host}/${event.service} - $notificationType');
    } else if (!isHardState) {
      session.log(
          'SOFT STATE NOTIFICATION: ${event.host}/${event.service} - $notificationType (not escalating)',
          level: LogLevel.info);
    }
  }

  /// Handle acknowledgement set events
  void _handleAcknowledgementSet(AcknowledgementSetEvent event) {
    final author = event.author;
    final comment = event.comment;

    session.log(
        'ACKNOWLEDGEMENT SET: ${event.host}/${event.service} acknowledged by $author: $comment',
        level: LogLevel.info);

    // TODO: Store acknowledgement in database
    // TODO: Update incident management system
    // TODO: Notify team that issue is being handled
    // TODO: Stop escalation notifications for this service
  }

  /// Handle acknowledgement cleared events
  void _handleAcknowledgementCleared(AcknowledgementClearedEvent event) {
    session.log(
        'ACKNOWLEDGEMENT CLEARED: ${event.host}/${event.service} acknowledgement removed',
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
    final delay = config.reconnectDelay * _retryCount; // Exponential backoff

    session.log(
        'Scheduling reconnection attempt $_retryCount in $delay seconds',
        level: LogLevel.info);

    _reconnectTimer = Timer(Duration(seconds: delay), () {
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

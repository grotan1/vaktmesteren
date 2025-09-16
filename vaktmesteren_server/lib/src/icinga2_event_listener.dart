import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';
import 'icinga2_events.dart';

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
          'AcknowledgementCleared'
        ],
        filter: '',
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
        types: ['CheckResult', 'StateChange', 'Notification'],
        filter: '',
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

  http.Client? _client;
  StreamSubscription<String>? _streamSubscription;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  bool _isConnected = false;
  bool _isShuttingDown = false;

  Icinga2EventListener(this.session, this.config);

  /// Start the event listener
  Future<void> start() async {
    session.log('Starting Icinga2 event listener...', level: LogLevel.info);
    await _connect();
  }

  /// Stop the event listener
  Future<void> stop() async {
    session.log('Stopping Icinga2 event listener...', level: LogLevel.info);
    _isShuttingDown = true;

    _reconnectTimer?.cancel();
    if (_streamSubscription != null) {
      await _streamSubscription!.cancel();
    }
    _client?.close();

    _isConnected = false;
  }

  /// Connect to Icinga2 event stream
  Future<void> _connect() async {
    if (_isShuttingDown) return;

    try {
      session.log(
          'Connecting to Icinga2 at ${config.scheme}://${config.host}:${config.port}',
          level: LogLevel.info);

      // Create HTTP client with SSL settings
      final httpClient = HttpClient();
      if (config.skipCertificateVerification) {
        httpClient.badCertificateCallback = (cert, host, port) => true;
      }

      _client = http.Client();

      // Prepare the request
      final url = '${config.scheme}://${config.host}:${config.port}/v1/events';
      final requestBody = {
        'queue': config.queue,
        'types': config.types,
        if (config.filter.isNotEmpty) 'filter': config.filter,
      };

      final credentials =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      // Make the POST request
      final response = await _client!
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        session.log('Successfully connected to Icinga2 event stream',
            level: LogLevel.info);
        _isConnected = true;
        _retryCount = 0;

        // Process the streaming response
        final stream = response.body;
        _processStream(stream);
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      session.log('Failed to connect to Icinga2: $e', level: LogLevel.error);
      _isConnected = false;

      if (config.reconnectEnabled && !_isShuttingDown) {
        _scheduleReconnect();
      }
    }
  }

  /// Process the event stream
  void _processStream(String responseBody) {
    // Split the response by newlines (Icinga2 sends JSON objects separated by newlines)
    final lines = LineSplitter.split(responseBody);

    for (final line in lines) {
      if (_isShuttingDown) break;

      if (line.trim().isNotEmpty) {
        try {
          final event = jsonDecode(line);
          _handleEvent(event);
        } catch (e) {
          session.log('Failed to parse event: $e', level: LogLevel.warning);
          session.log('Raw event data: $line', level: LogLevel.debug);
        }
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

  /// Handle check result events
  void _handleCheckResult(CheckResultEvent event) {
    // Process check result based on state and exit code
    final state = event.checkResult['state'] ?? 'UNKNOWN';
    final exitCode = event.checkResult['exit_code'] ?? -1;
    final output = event.checkResult['output'] ?? '';

    // Log based on severity
    if (state == 'CRITICAL' || exitCode == 2) {
      session.log('CRITICAL: ${event.host}/${event.service} - $output',
          level: LogLevel.error);
      // TODO: Send critical alert to duty officer
    } else if (state == 'WARNING' || exitCode == 1) {
      session.log('WARNING: ${event.host}/${event.service} - $output',
          level: LogLevel.warning);
      // TODO: Send warning notification
    } else if (state == 'OK' || exitCode == 0) {
      session.log('OK: ${event.host}/${event.service} - $output',
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

    // Log state changes with appropriate severity
    if (event.state == 2) {
      // CRITICAL
      session.log(
          'STATE CHANGE CRITICAL: ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
          level: LogLevel.error);
      // TODO: Trigger critical alert escalation
    } else if (event.state == 1) {
      // WARNING
      session.log(
          'STATE CHANGE WARNING: ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
          level: LogLevel.warning);
      // TODO: Send warning notification
    } else if (event.state == 0) {
      // OK
      session.log(
          'STATE CHANGE OK: ${event.host}/${event.service} recovered to $stateName ($stateTypeName)',
          level: LogLevel.info);
      // TODO: Clear active alerts
    } else {
      session.log(
          'STATE CHANGE: ${event.host}/${event.service} changed to $stateName ($stateTypeName)',
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

    session.log(
        'NOTIFICATION: $notificationType sent to $users via $command for ${event.host}/${event.service}',
        level: LogLevel.info);

    // TODO: Store notification in database for audit trail
    // TODO: Forward notification to external systems (SMS, email, etc.)
    // TODO: Update notification dashboard

    if (notificationType.contains('PROBLEM') ||
        notificationType.contains('CRITICAL')) {
      session.log(
          'PROBLEM NOTIFICATION: Immediate attention required for ${event.host}/${event.service}',
          level: LogLevel.warning);
      // TODO: Escalate to on-call duty officer
    } else if (notificationType.contains('RECOVERY') ||
        notificationType.contains('OK')) {
      session.log(
          'RECOVERY NOTIFICATION: ${event.host}/${event.service} has recovered',
          level: LogLevel.info);
      // TODO: Clear active alerts
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

  /// Check if the listener is currently connected
  bool get isConnected => _isConnected;
}

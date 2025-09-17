import 'dart:async';
import 'dart:convert';
import 'dart:io';
// Removed http IOClient; using Dio for all HTTP interactions
import 'package:dio/dio.dart' as dio;
import 'package:dio/io.dart' as dio_io;
import 'package:serverpod/serverpod.dart';
import 'package:yaml/yaml.dart';
import 'icinga2_events.dart';
import 'web/routes/log_viewer.dart';
import 'package:vaktmesteren_server/src/generated/protocol.dart';

part 'icinga2/config.dart';
part 'icinga2/handlers.dart';

// Icinga2Config is now defined in part 'icinga2/config.dart'

/// Service class for listening to Icinga2 event streams
class Icinga2EventListener {
  final Session session;
  final Icinga2Config config;

  // NOTE: _client, _streamSubscription and _reconnectTimer were unused and
  // removed to satisfy analyzer warnings.
  int _retryCount = 0;
  bool _isShuttingDown = false;
  // Using Dio exclusively for HTTP and streaming
  dio.Dio? _dio;
  // Debug event counter removed (no longer used)
  DateTime? _lastEventAt;
  // Track when we last broadcast a state for a canonical key to suppress
  // rapid duplicate broadcasts that can occur when both CheckResult and
  // StateChange events are emitted for the same change or when reconnects
  // cause the same event(s) to be re-delivered.
  final Map<String, DateTime> _lastBroadcastAt = {};

  // Polling has been removed - the event stream (and websocket) provide live updates.
  Timer? _reconnectTimer;
  // Retention job timer
  Timer? _retentionTimer;
  // Recovery backfill timer: polls occasionally to synthesize a missing OK
  // recovery if the event stream was disconnected when the recovery occurred.
  Timer? _recoveryBackfillTimer;
  // Problem state reconciliation timer: periodically checks for non-OK services
  // that are no longer in downtime and may have been missed.
  Timer? _problemStateReconciliationTimer;
  // Track last broadcast state per canonical key (host!service) to avoid duplicate alerts
  final Map<String, int> _lastBroadcastState = {};
  final Map<String, PersistedAlertState> _persistedStates = {};

  Icinga2EventListener(this.session, this.config);

  /// Start the event listener
  Future<void> start() async {
    session.log('Icinga2EventListener: Starting event listener...',
        level: LogLevel.info);
    await _loadPersistedStates();
    // Ensure Dio client is ready before any API calls
    _initDio();
    await _reconcileStatesOnStartup();
    session.log('Starting Iicinga2 event listener...', level: LogLevel.info);

    // Start event streaming in background (don't await)
    // ignore: unawaited_futures
    _connectWithDio();

    // Start retention job (hourly) to delete old alert history
    _startRetentionJob();

    // Start a light-weight recovery backfill job that runs periodically and
    // ensures we don't miss a recovery if the event stream briefly disconnects.
    _startRecoveryBackfillJob();

    // Start a job to reconcile problem states that might have been missed.
    _startProblemStateReconciliationJob();

    // No polling started - we rely on the event stream and websocket for updates.
  }

  void _startProblemStateReconciliationJob() {
    _problemStateReconciliationTimer?.cancel();
    // Run every minute to check for missed problem states.
    _problemStateReconciliationTimer =
        Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_runProblemStateReconciliation());
    });
  }

  Future<void> _runProblemStateReconciliation() async {
    try {
      if (_dio == null) return;

      // Fetch all non-OK services for the target host.
      final services = await _fetchHostServicesAttrs('integrasjoner');
      for (final attrs in services) {
        final state = (attrs['state'] as num?)?.toInt() ?? 0;
        if (state == 0) continue; // Skip OK services

        final host = (attrs['host_name'] ?? '').toString();
        final service = (attrs['name'] ?? '').toString();
        if (service.isEmpty) continue;

        // First, check if the service is currently in downtime.
        // If it is, we don't need to do anything, as the regular
        // post-downtime logic will handle it when the downtime ends.
        final isInDowntime = await _hasActiveDowntime(host, service: service);
        if (isInDowntime) {
          continue;
        }

        // If the service is not in downtime and is in a problem state,
        // run the check-and-trigger logic. This will handle alerting
        // if the state is hard, not acknowledged, and the state has
        // changed since the last broadcast.
        await _checkAndTriggerAfterDowntime(host, service,
            forceBroadcast: true);
      }
    } catch (e) {
      try {
        session.log('Problem state reconciliation failed: $e',
            level: LogLevel.debug);
      } catch (_) {}
    }
  }

  Future<void> _reconcileStatesOnStartup() async {
    session.log('Reconciling Icinga states on startup...',
        level: LogLevel.info);
    try {
      // Use Dio to fetch current services for reconciliation
      final response = await _dio!
          .get('/v1/objects/services')
          .timeout(Duration(seconds: config.timeout));

      if (response.statusCode == 200) {
        final data =
            response.data is String ? jsonDecode(response.data) : response.data;
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
            'Failed to fetch services from Icinga for reconciliation. Status: ${response.statusCode}, Body: ${response.data}',
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
  // Removed legacy _connect() that used HttpClient; using Dio exclusively

  /// Ensure the Dio client is initialized with proper base URL, headers,
  /// and TLS behavior.
  void _initDio() {
    if (_dio != null) return;
    final options = dio.BaseOptions(
      baseUrl: '${config.scheme}://${config.host}:${config.port}',
      connectTimeout: Duration(seconds: config.timeout),
      receiveTimeout:
          Duration(seconds: config.streamInactivitySeconds + config.timeout),
      sendTimeout: Duration(seconds: config.timeout),
      headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Connection': 'keep-alive',
      },
    );
    final d = dio.Dio(options);
    final adapter = dio_io.IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final client = HttpClient();
      if (config.skipCertificateVerification) {
        client.badCertificateCallback = (cert, host, port) => true;
      }
      return client;
    };
    d.httpClientAdapter = adapter;
    _dio = d;
  }

  /// Process the event stream response
  // Removed legacy _processEventStream; streaming handled in _connectWithDio

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
          // ignore: unawaited_futures
          handleCheckResult(this, icingaEvent as CheckResultEvent);
          break;
        case 'StateChange':
          // ignore: unawaited_futures
          handleStateChange(this, icingaEvent as StateChangeEvent);
          break;
        case 'Notification':
          handleNotification(this, icingaEvent as NotificationEvent);
          break;
        case 'AcknowledgementSet':
          handleAcknowledgementSet(
              this, icingaEvent as AcknowledgementSetEvent);
          break;
        case 'AcknowledgementCleared':
          handleAcknowledgementCleared(
              this, icingaEvent as AcknowledgementClearedEvent);
          break;
        case 'CommentAdded':
          handleCommentAdded(this, icingaEvent as CommentAddedEvent);
          break;
        case 'CommentRemoved':
          handleCommentRemoved(this, icingaEvent as CommentRemovedEvent);
          break;
        case 'DowntimeAdded':
          handleDowntimeAdded(this, icingaEvent as DowntimeAddedEvent);
          break;
        case 'DowntimeRemoved':
          handleDowntimeRemoved(this, icingaEvent as DowntimeRemovedEvent);
          break;
        case 'DowntimeStarted':
          handleDowntimeStarted(this, icingaEvent as DowntimeStartedEvent);
          break;
        case 'DowntimeTriggered':
          handleDowntimeTriggered(this, icingaEvent as DowntimeTriggeredEvent);
          break;
        case 'ObjectCreated':
          handleObjectCreated(this, icingaEvent as ObjectCreatedEvent);
          break;
        case 'ObjectModified':
          handleObjectModified(this, icingaEvent as ObjectModifiedEvent);
          break;
        case 'ObjectDeleted':
          handleObjectDeleted(this, icingaEvent as ObjectDeletedEvent);
          break;
        default:
          handleUnknownEvent(this, icingaEvent as UnknownEvent);
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

  /// Persist a historical alert entry (append-only)
  Future<void> _persistHistory(String canonicalKey, String host,
      String? service, int state, String? message,
      {DateTime? at}) async {
    try {
      // Only persist history for hosts we're interested in broadcasting.
      // This keeps persistent logs consistent with what is shown in the
      // realtime UI and avoids storing noise for unrelated hosts.
      if (!_shouldBroadcastForHost(host)) return;

      // Do not persist plugin/check output (may contain secrets). Instead
      // persist a formatted, human-friendly message that matches the
      // broadcast format (emoji + state label + host/service) so the
      // history shown in the UI looks identical to the realtime logs.
      final stateNames = {0: 'OK', 1: 'WARNING', 2: 'CRITICAL', 3: 'UNKNOWN'};
      final emoji = (state == 2)
          ? '\uD83D\uDEA8' // 🚨 CRITICAL siren, aligns with broadcast
          : (state == 1)
              ? '\u26A0\uFE0F' // ⚠️
              : (state == 0)
                  ? '\u2705' // ✅
                  : '';
      final label = stateNames[state] ?? 'STATE:$state';
      final hostSvc = _hostServiceLabel(host, service);
      final formattedMessage =
          '$emoji ALERT ${label == 'OK' ? 'RECOVERY' : label}: $hostSvc';

      final entry = AlertHistory(
        host: host,
        service: service,
        canonicalKey: canonicalKey,
        state: state,
        // Persist the formatted message only (no plugin output)
        message: formattedMessage,
        createdAt: at ?? DateTime.now(),
      );

      // Use a background session so we don't depend on request/session lifetime
      // Use the existing long-lived session provided to the listener.
      await AlertHistory.db.insertRow(session, entry);
    } catch (e) {
      session.log('Failed to persist alert history for $canonicalKey: $e',
          level: LogLevel.error);
    }
  }

  /// Start retention job which deletes alert_history older than configured retention days
  void _startRetentionJob() {
    // Default retention: 3 days
    final retentionDays = _readRetentionDaysFromConfig();
    // Run immediately once, then hourly
    _runRetentionJob(retentionDays);
    _retentionTimer = Timer.periodic(Duration(hours: 1), (_) {
      _runRetentionJob(retentionDays);
    });
  }

  void _stopRetentionJob() {
    // Intentionally left blank; retention timer canceled by cancelling the
    // periodic Timer reference. Kept for future expansion.
    try {
      _retentionTimer?.cancel();
    } catch (_) {}
    _retentionTimer = null;
  }

  /// Start a periodic job that checks current Icinga states and backfills
  /// a missing OK recovery broadcast if needed (for target host only).
  void _startRecoveryBackfillJob() {
    // Run every 60 seconds. This is intentionally light-weight and filtered
    // to the target host to avoid load.
    _recoveryBackfillTimer?.cancel();
    _recoveryBackfillTimer =
        Timer.periodic(Duration(seconds: config.recoveryBackfillSeconds), (_) {
      unawaited(_runRecoveryBackfill());
    });
  }

  Future<void> _runRecoveryBackfill() async {
    try {
      // Require Dio to be initialized
      if (_dio == null) return;

      // Only consider the integrasjoner host to keep the query small.
      final url =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/services';
      final credentials =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-HTTP-Method-Override': 'GET',
      };
      final body = jsonEncode({
        'filter': 'host.name=="integrasjoner"',
        'attrs': ['name', 'state', 'host_name'],
      });

      final response = await _dio!
          .post(url, data: body, options: dio.Options(headers: headers))
          .timeout(Duration(seconds: 20));
      if (response.statusCode != 200) return;

      final data =
          response.data is String ? jsonDecode(response.data) : response.data;
      final results = (data['results'] as List?) ?? const [];
      for (final serviceData in results) {
        final attrs = serviceData['attrs'] as Map<String, dynamic>?;
        if (attrs == null) continue;
        final host = (attrs['host_name'] ?? '').toString();
        if (!_shouldBroadcastForHost(host)) continue;
        final service = (attrs['name'] ?? '').toString();
        final state = (attrs['state'] as num?)?.toInt() ?? 3;
        final key = _canonicalKey(host, service);

        // If Icinga says OK but our last seen or last broadcast was non-OK,
        // synthesize a recovery broadcast.
        final lastSeen = _persistedStates[key]?.lastState;
        final lastBroadcast = _lastBroadcastState[key];
        if (state == 0 &&
            ((lastSeen != null && lastSeen != 0) ||
                (lastBroadcast != null && lastBroadcast != 0))) {
          final msg =
              '✅ ALERT RECOVERY: ${_hostServiceLabel(host, service)} (backfill)';
          LogBroadcaster.broadcastLog(msg);
          // Update local tracking and persistence to reflect recovery.
          _lastBroadcastState[key] = 0;
          _lastBroadcastAt[key] = DateTime.now();
          await _persistState(key, host, service, 0);
          // Persist history for backfilled recovery as well
          unawaited(_persistHistory(key, host, service, 0, null));
        }
      }
    } catch (e) {
      // Keep errors quiet; this is a best-effort job.
      try {
        session.log('Recovery backfill failed: $e', level: LogLevel.debug);
      } catch (_) {}
    }
  }

  int _readRetentionDaysFromConfig() {
    try {
      // Look for common config files in repository order and read retention_days
      final candidates = [
        'config/production.yaml',
        'config/staging.yaml',
        'config/development.yaml',
        'config/test.yaml',
      ];
      for (final path in candidates) {
        final file = File(path);
        if (!file.existsSync()) continue;
        try {
          final content = file.readAsStringSync();
          final doc = loadYaml(content);
          if (doc is YamlMap && doc.containsKey('retention_days')) {
            final val = doc['retention_days'];
            if (val is int && val > 0) return val;
            if (val is String) {
              final parsed = int.tryParse(val);
              if (parsed != null && parsed > 0) return parsed;
            }
          }
        } catch (e) {
          // ignore parse errors and try next file
        }
      }
      return 3;
    } catch (_) {
      return 3;
    }
  }

  Future<void> _runRetentionJob(int retentionDays) async {
    try {
      final cutoff =
          DateTime.now().toUtc().subtract(Duration(days: retentionDays));
      // Delete rows older than cutoff using the generated ORM where-builder.
      // The where-builder supports the '<' comparator for DateTime columns.
      final deleted = await AlertHistory.db.deleteWhere(
        session,
        where: (t) => t.createdAt < cutoff,
      );
      session.log(
          'Retention job: deleted ${deleted.length} alert_history rows older than $cutoff',
          level: LogLevel.info);
    } catch (e) {
      session.log('Retention job failed: $e', level: LogLevel.error);
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
  /// Only broadcast when the state actually changes for the canonical key.
  bool _shouldBroadcastForKey(String key, int state) {
    final lastState = _lastBroadcastState[key];
    if (lastState == state) {
      // No state change; skip broadcasting to avoid periodic duplicates
      session.log('Skip broadcast for $key (unchanged state: $state)',
          level: LogLevel.debug);
      return false;
    }

    // State actually changed; record and allow broadcast
    session.log(
        'Broadcasting for $key: state changed ${lastState ?? 'null'} -> $state',
        level: LogLevel.debug);
    _lastBroadcastState[key] = state;
    _lastBroadcastAt[key] = DateTime.now();
    return true;
  }

  /// Throttle suppressed log spam without mutating last broadcast state.
  /// Returns true if we should skip a suppressed broadcast due to time threshold.
  bool _shouldThrottleSuppressed(String key,
      {Duration window = const Duration(seconds: 15)}) {
    final lastAt = _lastBroadcastAt[key];
    if (lastAt == null) return false;
    return DateTime.now().difference(lastAt) < window;
  }

  /// Extract host/service from a downtime payload.
  /// Supports keys like host_name/service_name or parses composite name "host!service!...".
  (String host, String? service)? _extractHostServiceFromDowntime(
      Map<String, dynamic> downtime) {
    try {
      String? host = (downtime['host_name'] ?? downtime['host'])?.toString();
      String? service =
          (downtime['service_name'] ?? downtime['service'])?.toString();
      host = host?.trim();
      service = service?.trim();
      if ((host == null || host.isEmpty) && (downtime['name'] is String)) {
        final name = (downtime['name'] as String);
        final parts = name.split('!');
        if (parts.isNotEmpty) {
          host = parts[0];
          if (parts.length > 1) {
            service = parts[1];
          }
        }
      }
      if (host == null || host.isEmpty) return null;
      if (service != null && service.isEmpty) service = null;
      return (host, service);
    } catch (_) {
      return null;
    }
  }

  /// Fetch current service attributes from Iicinga2 for the given host/service.
  /// Returns a map with keys: host_name, name, state, state_type, downtime_depth, acknowledgement.
  Future<Map<String, dynamic>?> _fetchServiceAttrs(
      String host, String service) async {
    try {
      if (_dio == null) return null;
      final url =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/services';
      final credentials =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-HTTP-Method-Override': 'GET',
      };
      // Normalize host to base (strip domain) and match possible FQDN variants.
      // Using match() avoids strict equality issues between short and FQDN host names.
      final baseHost = host.split('.').first;
      // In Icinga 2 filters, refer to 'service.name' for the service object name.
      final filter =
          'match("${baseHost}*", host.name) && service.name=="$service"';
      final body = jsonEncode({
        'filter': filter,
        'attrs': [
          'name',
          'state',
          'state_type',
          'host_name',
          'downtime_depth',
          'acknowledgement'
        ],
      });
      final response = await _dio!
          .post(url, data: body, options: dio.Options(headers: headers))
          .timeout(Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data =
          response.data is String ? jsonDecode(response.data) : response.data;
      final results = (data['results'] as List?) ?? const [];
      if (results.isEmpty) return null;
      final attrs = results.first['attrs'] as Map<String, dynamic>?;
      return attrs;
    } catch (_) {
      return null;
    }
  }

  /// Fetch current service attrs for all services on a host.
  Future<List<Map<String, dynamic>>> _fetchHostServicesAttrs(
      String host) async {
    try {
      if (_dio == null) return const [];
      final url =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/services';
      final credentials =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-HTTP-Method-Override': 'GET',
      };
      // Normalize host and use match() to support FQDN/short name mismatches.
      final baseHost = host.split('.').first;
      final body = jsonEncode({
        'filter': 'match("${baseHost}*", host.name)',
        'attrs': [
          'name',
          'state',
          'host_name',
          'downtime_depth',
          'acknowledgement'
        ],
      });
      final response = await _dio!
          .post(url, data: body, options: dio.Options(headers: headers))
          .timeout(Duration(seconds: 20));
      if (response.statusCode != 200) return const [];
      final data =
          response.data is String ? jsonDecode(response.data) : response.data;
      final results = (data['results'] as List?) ?? const [];
      final list = <Map<String, dynamic>>[];
      for (final serviceData in results) {
        final attrs = serviceData['attrs'] as Map<String, dynamic>?;
        if (attrs != null) list.add(attrs);
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Returns true if there is an active downtime for the given host/service.
  /// For a service, both service-level and host-level downtimes count as active.
  Future<bool> _hasActiveDowntime(String host, {String? service}) async {
    try {
      if (_dio == null) return false;
      final url =
          '${config.scheme}://${config.host}:${config.port}/v1/objects/downtimes';
      final credentials =
          base64Encode(utf8.encode('${config.username}:${config.password}'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-HTTP-Method-Override': 'GET',
      };
      // Filter by host to keep payload small. Match possible FQDN variants using match().
      // Normalize to short host name so it matches both short and FQDN entries.
      // Example: match("integrasjoner*", host_name)
      final baseHost = host.split('.').first;
      final filter = 'match("${baseHost}*", host_name)';
      final body = jsonEncode({
        'filter': filter,
        'attrs': [
          'host_name',
          'service_name',
          'start_time',
          'end_time',
          'entry_time',
          'fixed',
          'duration'
        ],
      });
      final response = await _dio!
          .post(url, data: body, options: dio.Options(headers: headers))
          .timeout(Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      final data =
          response.data is String ? jsonDecode(response.data) : response.data;
      final results = (data['results'] as List?) ?? const [];
      if (results.isEmpty) return false;
      final nowEpoch = DateTime.now().millisecondsSinceEpoch / 1000.0;
      bool activeForService = false;
      for (final item in results) {
        final attrs = item['attrs'] as Map<String, dynamic>?;
        if (attrs == null) continue;
        final startTime = (attrs['start_time'] is num)
            ? (attrs['start_time'] as num).toDouble()
            : (attrs['start_time'] is String)
                ? double.tryParse(attrs['start_time'] as String)
                : null;
        final endTime = (attrs['end_time'] is num)
            ? (attrs['end_time'] as num).toDouble()
            : (attrs['end_time'] is String)
                ? double.tryParse(attrs['end_time'] as String)
                : null;
        // Consider active if now is within [start, end).
        final started = startTime == null ? true : (startTime <= nowEpoch);
        final notEnded = endTime == null ? true : (endTime > nowEpoch);
        final isActive = started && notEnded;
        if (!isActive) continue;
        final svcName = (attrs['service_name'] ?? '').toString().trim();
        if (service == null || service.isEmpty) {
          // Host-level query; any active downtime on host counts.
          if (isActive) return true;
        } else {
          // Service-specific; host-level downtime has empty service_name.
          if (svcName.isEmpty && isActive) {
            return true; // host-level downtime covers service
          }
          if (svcName == service && isActive) activeForService = true;
        }
      }
      return activeForService;
    } catch (e) {
      try {
        session.log('Downtime check failed for $host/${service ?? ''}: $e',
            level: LogLevel.debug);
      } catch (_) {}
      // On error, be conservative and return true only if we explicitly know;
      // here we failed, so return false to avoid blocking alerts indefinitely.
      return false;
    }
  }

  /// After downtime ends, if the service is still non-OK and not acknowledged, trigger an alert.
  Future<void> _checkAndTriggerAfterDowntime(String host, String service,
      {bool forceBroadcast = false}) async {
    try {
      if (!_shouldBroadcastForHost(host)) return;
      final key = _canonicalKey(host, service);
      int? state;
      int? stateType;
      bool acknowledged = false;
      int downtimeDepth = 0;

      final attrs = await _fetchServiceAttrs(host, service);
      if (attrs != null) {
        state = (attrs['state'] as num?)?.toInt();
        stateType = (attrs['state_type'] as num?)?.toInt();
        final ackRaw = attrs['acknowledgement'];
        if (ackRaw is bool) {
          acknowledged = ackRaw;
        } else if (ackRaw is num) {
          acknowledged = ackRaw.toDouble() != 0.0;
        } else if (ackRaw is String) {
          final n = num.tryParse(ackRaw);
          acknowledged = n != null ? n != 0 : (ackRaw.toLowerCase() == 'true');
        } else {
          acknowledged = false;
        }
        downtimeDepth = (attrs['downtime_depth'] as num?)?.toInt() ?? 0;
      } else {
        // If we cannot fetch current attributes, do not attempt a post-downtime broadcast.
        // This avoids false alerts while downtime may still be active or attributes lag.
        session.log(
            'Post-downtime check: attrs unavailable for ${_hostServiceLabel(host, service)} -> will retry later',
            level: LogLevel.debug);
        return;
      }

      if (state == null) return;

      // If still in downtime according to Icinga's attrs, skip this attempt (we will retry).
      if (downtimeDepth > 0) {
        session.log(
            'Post-downtime check: still in downtime for ${_hostServiceLabel(host, service)} (state=$state, stateType=${stateType ?? 'n/a'}, depth=$downtimeDepth) -> will retry if scheduled',
            level: LogLevel.debug);
        return;
      }

      // Double-check: ensure there is no active downtime entry for this host/service.
      // This prevents false alerts when downtime_depth briefly reports 0 but a downtime still exists.
      final stillHasDowntime = await _hasActiveDowntime(host, service: service);
      if (stillHasDowntime) {
        session.log(
            'Post-downtime check: active downtime still present for ${_hostServiceLabel(host, service)} -> not alerting yet',
            level: LogLevel.debug);
        return;
      }

      if (state > 0 && !acknowledged) {
        final label =
            state == 2 ? 'CRITICAL' : (state == 1 ? 'WARNING' : 'STATE:$state');
        final emoji = state == 2 ? '🚨' : '⚠️';
        // Avoid duplicate alerts across retries by gating on state change for this key,
        // unless we are forcing a broadcast from the reconciliation job.
        if (forceBroadcast || _shouldBroadcastForKey(key, state)) {
          final msg = stateType == 1
              ? '$emoji ALERT $label: ${_hostServiceLabel(host, service)}'
              : '$emoji ALERT $label: ${_hostServiceLabel(host, service)} (post-downtime)';
          LogBroadcaster.broadcastLog(msg);
          // Persist state and history
          await _persistState(key, host, service, state);
          unawaited(_persistHistory(key, host, service, state, null));
        } else {
          session.log(
              'Post-downtime check: duplicate state $state for ${_hostServiceLabel(host, service)} -> no broadcast',
              level: LogLevel.debug);
        }
      } else {
        session.log(
            'Post-downtime check: no alert for ${_hostServiceLabel(host, service)} (state=$state, stateType=${stateType ?? 'n/a'}, ack=$acknowledged, depth=$downtimeDepth)',
            level: LogLevel.debug);
      }
    } catch (e) {
      try {
        session.log('Post-downtime trigger failed for $host/$service: $e',
            level: LogLevel.debug);
      } catch (_) {}
    }
  }

  /// Handle a downtime ending for either a service or an entire host.
  Future<void> _handleDowntimeEnded(Map<String, dynamic> downtime) async {
    final hs = _extractHostServiceFromDowntime(downtime);
    if (hs == null) return;
    final host = hs.$1;
    final service = hs.$2;

    // Schedule a series of checks to account for Icinga API delays.
    // This is more robust than a single fixed delay.
    final delays = [
      const Duration(seconds: 1),
      const Duration(seconds: 3),
      const Duration(seconds: 7),
      const Duration(seconds: 15),
    ];

    void scheduleChecks(String h, String s) {
      for (final delay in delays) {
        Timer(delay, () {
          unawaited(_checkAndTriggerAfterDowntime(h, s));
        });
      }
    }

    if (service != null && service.isNotEmpty) {
      // For a specific service, schedule multiple checks.
      scheduleChecks(host, service);
    } else {
      // For a host-level downtime, find all services and schedule checks for each.
      final services = await _fetchHostServicesAttrs(host);
      for (final attrs in services) {
        final svc = (attrs['name'] ?? '').toString();
        if (svc.isNotEmpty) {
          scheduleChecks(host, svc);
        }
      }
    }
  }

  /// Decide whether to broadcast a recovery (state=0) even if we didn't
  /// previously broadcast the alert state (e.g., only soft criticals).
  ///
  /// Logic:
  /// - If the last seen persisted state (from DB) was non-OK, broadcast.
  /// - Otherwise fall back to the last broadcast state check.
  bool _shouldBroadcastRecovery(String key) {
    final lastSeen = _persistedStates[key]?.lastState;
    final lastBroadcast = _lastBroadcastState[key];
    if (lastSeen != null && lastSeen != 0) {
      session.log(
          'Broadcasting recovery for $key based on last seen persisted state=$lastSeen -> 0',
          level: LogLevel.debug);
      _lastBroadcastState[key] = 0;
      _lastBroadcastAt[key] = DateTime.now();
      return true;
    }

    if (lastBroadcast != 0) {
      session.log(
          'Broadcasting recovery for $key based on last broadcast state=$lastBroadcast -> 0',
          level: LogLevel.debug);
      _lastBroadcastState[key] = 0;
      _lastBroadcastAt[key] = DateTime.now();
      return true;
    }

    session.log(
        'Skip recovery broadcast for $key (lastSeen=${lastSeen ?? 'null'}, lastBroadcast=${lastBroadcast ?? 'null'})',
        level: LogLevel.debug);
    return false;
  }

  /// Convert a check_result map or state string/exit code to an integer state code.
  /// 0 = OK, 1 = WARNING, 2 = CRITICAL, 3 = UNKNOWN
  // NOTE: _stateCodeFromCheckResult was removed because it was unused.

  // All specific handlers moved to handlers.dart

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
        _connectWithDio();
      }
    });
  }

  /// Alternative event stream connection using Dio. This can be more robust
  /// in some environments (proxies, TLS, header handling) and gives us
  /// explicit control over timeouts.
  Future<void> _connectWithDio() async {
    if (_isShuttingDown) return;

    try {
      session.log(
          'Iicinga2EventListener(Dio): Connecting to Icinga2 at ${config.scheme}://${config.host}:${config.port}',
          level: LogLevel.info);

      final options = dio.BaseOptions(
        baseUrl: '${config.scheme}://${config.host}:${config.port}',
        connectTimeout: Duration(seconds: config.timeout),
        receiveTimeout:
            Duration(seconds: config.streamInactivitySeconds + config.timeout),
        sendTimeout: Duration(seconds: config.timeout),
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Connection': 'keep-alive',
        },
      );

      // Create Dio with optional bad cert handling
      final d = dio.Dio(options);
      final adapter = dio_io.IOHttpClientAdapter();
      adapter.createHttpClient = () {
        final client = HttpClient();
        if (config.skipCertificateVerification) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        return client;
      };
      d.httpClientAdapter = adapter;

      _dio = d;

      // Test status quickly
      try {
        final r = await _dio!
            .get('/v1/status')
            .timeout(Duration(seconds: config.timeout));
        session.log('Iicinga2EventListener(Dio): /v1/status ${r.statusCode}',
            level: LogLevel.debug);
      } catch (e) {
        session.log('Iicinga2EventListener(Dio): status check failed: $e',
            level: LogLevel.debug);
      }

      final requestBody = <String, dynamic>{
        'queue': config.queue,
        'types': config.types,
        if (config.filter.isNotEmpty) 'filter': config.filter,
      };

      session.log(
          'Iicinga2EventListener(Dio): Subscribing to /v1/events queue="${config.queue}" filter="${config.filter}"',
          level: LogLevel.debug);

      final response = await _dio!.post<dio.ResponseBody>(
        '/v1/events',
        data: jsonEncode(requestBody),
        options: dio.Options(
          responseType: dio.ResponseType.stream,
          followRedirects: true,
          receiveTimeout: Duration(
              seconds: config.streamInactivitySeconds + config.timeout),
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        session.log(
            'Iicinga2EventListener(Dio): Failed to connect stream: ${response.statusCode}',
            level: LogLevel.error);
        throw Exception('Event stream connection failed');
      }

      _retryCount = 0;

      final stream = response.data!.stream
          .map((chunk) => utf8.decode(chunk))
          .transform(const LineSplitter())
          .timeout(Duration(seconds: config.streamInactivitySeconds),
              onTimeout: (sink) {
        session.log(
            'Iicinga2EventListener(Dio): Stream inactivity timeout; reconnecting',
            level: LogLevel.warning);
        try {
          sink.close();
        } catch (_) {}
      });

      await for (final line in stream) {
        if (_isShuttingDown) break;
        if (line.trim().isEmpty) continue;
        try {
          final event = jsonDecode(line);
          _lastEventAt = DateTime.now();
          _handleEvent(event);
        } catch (e) {
          session.log('Dio stream parse error: $e', level: LogLevel.warning);
        }
      }

      if (config.reconnectEnabled && !_isShuttingDown) {
        _scheduleReconnect();
      }
    } catch (e) {
      session.log('Iicinga2EventListener(Dio): Connection error: $e',
          level: LogLevel.error);
      if (config.reconnectEnabled && !_isShuttingDown) {
        _scheduleReconnect();
      }
    }
  }

// (Removed custom ResponseBodyStreamWrapper; using dio.ResponseBody instead.)

  /// Stop the event listener and clean up resources
  /// Cancels any pending reconnect timer and closes the HTTP client.
  Future<void> stop() async {
    _isShuttingDown = true;

    // Stop retention timer when shutting down so it doesn't fire after stop.
    _stopRetentionJob();

    // Stop recovery backfill timer as well
    try {
      _recoveryBackfillTimer?.cancel();
    } catch (_) {}
    _recoveryBackfillTimer = null;

    // Stop problem state reconciliation timer as well
    try {
      _problemStateReconciliationTimer?.cancel();
    } catch (_) {}
    _problemStateReconciliationTimer = null;

    if (_reconnectTimer?.isActive ?? false) {
      _reconnectTimer?.cancel();
    }
    _reconnectTimer = null;

    // Dio will be GC'd; no explicit close required

    session.log('Icinga2EventListener: Stopped', level: LogLevel.info);
  }
}

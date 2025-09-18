import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:vaktmesteren_server/src/web/widgets/log_viewer_page.dart';
import 'package:vaktmesteren_server/src/generated/protocol.dart';
import 'package:serverpod/serverpod.dart';

class RouteLogViewer extends WidgetRoute {
  @override
  Future<Widget> build(Session session, HttpRequest request) async {
    // Server-side: attempt to load recent alert history so the initial HTML
    // contains recent OK/ALERTs. This is best-effort and won't fail page
    // rendering if the DB or ORM isn't available.
    List<Map<String, dynamic>> alertRows = [];
    try {
      final threeDaysAgo = DateTime.now().toUtc().subtract(Duration(days: 3));
      final rows = await AlertHistory.db.find(
        session,
        where: (t) => t.createdAt >= threeDaysAgo,
        limit: 200,
        orderBy: (t) => t.createdAt,
        orderDescending: true,
      );
      // Filter server-side to show entries from grsoft.no domain hosts.
      // This includes hosts like ghrunner.grsoft.no, pve1.grsoft.no, etc.
      final filtered = rows.where((r) {
        try {
          final host = r.host.toLowerCase().trim();
          return host.endsWith('.grsoft.no');
        } catch (_) {
          return false;
        }
      }).toList();
      alertRows = filtered.map((r) => r.toJson()).toList();
    } catch (e) {
      try {
        session.log('RouteLogViewer: failed to load alert history: $e',
            level: LogLevel.debug);
      } catch (_) {}
    }

    final page = LogViewerPage();
    try {
      page.values['initialAlertHistory'] =
          Uri.encodeComponent(jsonEncode(alertRows));
    } catch (_) {
      page.values['initialAlertHistory'] = '';
    }

    // Embed logo as data URL if available so no extra HTTP request is needed.
    try {
      final logoFile = File('assets/logo.png');
      if (await logoFile.exists()) {
        final bytes = await logoFile.readAsBytes();
        final b64 = base64Encode(bytes);
        page.values['logoDataUrl'] = 'data:image/png;base64,$b64';
      } else {
        page.values['logoDataUrl'] = '';
      }
    } catch (_) {
      page.values['logoDataUrl'] = '';
    }
    return page;
  }
}

class LogBroadcaster {
  static final StreamController<String> _logController =
      StreamController<String>.broadcast();

  // Track the number of currently connected websocket subscribers for debugging
  // and to help diagnose duplicate broadcasts.
  static int _subscriberCount = 0;

  static void _addSubscriber() {
    _subscriberCount++;
    // Subscriber counting kept for diagnostics; prefer session logging when
    // available at call sites. Silent here to avoid global prints.
  }

  static void _removeSubscriber() {
    if (_subscriberCount > 0) _subscriberCount--;
    // Silent - use session.log at call sites for structured logging.
  }

  // Keep a small in-memory buffer of recent logs so the polling endpoint
  // can return something useful if needed.
  static final List<String> _recentLogs = <String>[];
  static const int _recentLogsMax = 200;
  // Dedupe identical messages within a window to avoid repeated
  // broadcasts (regardless of the originating listener). Keyed by the
  // message text; stores last broadcast DateTime.
  static final Map<String, DateTime> _lastMessageAt = {};
  // Serverpod instance used for creating sessions to persist logs.
  // Persistence will be wired after generated ORM is available.

  /// Initialize the broadcaster's persistence using Serverpod's DB.
  /// This will create the persistence table if missing and load the most
  /// recent non-transient log messages into the in-memory buffer.
  static Future<void> init(Serverpod pod) async {
    // Persisted storage will be wired up using Serverpod's ORM once the
    // `PersistedAlertState`/`WebLog` models are generated via
    // `serverpod generate` and migrations have been applied. Until then,
    // keep the in-memory recent buffer active and skip direct SQL.
    // TODO: Load persisted logs using generated ORM here.
  }

  static void broadcastLog(String message) {
    // Defensive filter: some code paths may emit alert-style messages for
    // hosts we don't want broadcast to the realtime UI. Ensure we only
    // broadcast ALERT/RECOVERY/WARNING/CRITICAL messages that originate
    // from the `integrasjoner` host so the frontend doesn't show unrelated
    // hosts like pve3.*.
    final lower = message.toLowerCase();
    if (lower.contains('alert') ||
        lower.contains('recovery') ||
        lower.contains('warning') ||
        lower.contains('critical')) {
      // Try to extract a host token from message. Common formats used in
      // this codebase include "...: host/service - output" or
      // "...: host/service" and "host/service". We'll look for the
      // last whitespace-separated token containing a '/' and treat the
      // left side as the host.
      final parts = message.split(RegExp(r'\s+'));
      for (var i = parts.length - 1; i >= 0; i--) {
        final token = parts[i];
        if (token.contains('/')) {
          final hostPart = token
              .split('/')
              .first
              .split(':')
              .first
              .split('-')
              .first
              .trim()
              .toLowerCase();
          final baseHost = hostPart.split('.').first;
          if (baseHost != 'integrasjoner') {
            // Drop this broadcast silently.
            return;
          }
          break;
        }
      }
    }

    // Dedupe by message content: skip identical messages within 15 seconds.
    final now = DateTime.now();
    final lastAt = _lastMessageAt[message];
    if (lastAt != null && now.difference(lastAt).inSeconds < 15) {
      // Skip broadcasting rapid duplicate message
      return;
    }

    // Add to stream
    _lastMessageAt[message] = now;
    _logController.add(message);

    // Log to console for easier debugging
    // Intentionally no console printing here; use session.log where a
    // Session is available to avoid analyzer avoid_print warnings.

    // Maintain recent logs buffer
    try {
      _recentLogs.add(message);
      if (_recentLogs.length > _recentLogsMax) {
        _recentLogs.removeRange(0, _recentLogs.length - _recentLogsMax);
      }
    } catch (e) {
      // ignore errors in buffer maintenance
    }

    // Persist to DB if initialized. Use a background session per-insert so
    // we don't depend on any particular request session lifetime.
    // Persistence via Serverpod ORM is disabled until generated models are
    // available. This avoids using raw SQL APIs that vary between Serverpod
    // versions and prevents analyzer errors. After running
    // `serverpod generate` and applying migrations, implement ORM-based
    // inserts here.
  }

  /// Broadcast a transient message to currently connected clients without
  /// adding it to the recent buffer. Useful for manual test messages that
  /// shouldn't be replayed to clients who connect later.
  static void broadcastTransient(String message) {
    try {
      _logController.add(message);
    } catch (_) {}
    // No direct printing here; call sites may log via session.
  }
}

/// A simple polling route used as a fallback when EventSource isn't available
/// or fails to connect. Returns the recent log messages as JSON.
class RouteLogPoll extends Route {
  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    request.response.headers
        .set('Content-Type', 'application/json; charset=utf-8');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Headers',
        'Accept, Cache-Control, Content-Type, Authorization');
    request.response.headers
        .set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return true;
    }

    try {
      session.log(
          'RouteLogPoll: returning ${LogBroadcaster._recentLogs.length} recent logs and recent alert history',
          level: LogLevel.debug);

      // Attempt to load recent alert history (best-effort). If AlertHistory
      // ORM isn't available yet or DB is unreachable, fall back to empty list.
      List<Map<String, dynamic>> alertRows = [];
      try {
        final threeDaysAgo = DateTime.now().toUtc().subtract(Duration(days: 3));
        final rows = await AlertHistory.db.find(
          session,
          where: (t) => t.createdAt >= threeDaysAgo,
          limit: 200,
          orderBy: (t) => t.createdAt,
          orderDescending: true,
        );
        final filtered = rows.where((r) {
          try {
            final host = r.host.toLowerCase().trim();
            return host.endsWith('.grsoft.no');
          } catch (_) {
            return false;
          }
        }).toList();
        alertRows = filtered.map((r) => r.toJson()).toList();
      } catch (e) {
        // ignore DB errors here - return recent logs anyway
        session.log('RouteLogPoll: could not load alert history: $e',
            level: LogLevel.debug);
      }

      final payload = {
        'logs': List<String>.from(LogBroadcaster._recentLogs),
        'alertHistory': alertRows,
      };
      request.response.write(jsonEncode(payload));
      await request.response.close();
      return true;
    } catch (e) {
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': e.toString()}));
        await request.response.close();
      } catch (_) {}
      return true;
    }
  }
}

/// Test route to manually trigger a log broadcast (useful for debugging from browser)
class RouteLogTest extends Route {
  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    try {
      final msg =
          '🧪 Manual test message from /logs/test at ${DateTime.now().toIso8601String()}';
      // Use transient broadcast so test messages are not stored in the replay buffer
      // and won't be re-sent to clients who connect after the test was sent.
      LogBroadcaster.broadcastTransient(msg);
      request.response.headers.set('Content-Type', 'text/plain; charset=utf-8');
      request.response.write('Triggered test log');
      await request.response.close();
      return true;
    } catch (e) {
      try {
        request.response.statusCode = 500;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
      return true;
    }
  }
}

/// A WebSocket route to provide realtime logs via WebSocket as an alternative
/// to Server-Sent Events. This can be more reliable in some environments and
/// avoids intermediate buffering issues.
class RouteLogWebSocket extends Route {
  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    // Only handle WebSocket upgrade requests here
    try {
      final upgradeHeader = request.headers.value('upgrade') ?? '';
      if (upgradeHeader.toLowerCase() != 'websocket') {
        request.response.statusCode = HttpStatus.badRequest;
        request.response
            .write('This endpoint only supports WebSocket upgrades');
        await request.response.close();
        return true;
      }
    } catch (_) {
      // If headers can't be read, still attempt upgrade but fail gracefully
    }

    try {
      final t0 = DateTime.now();
      final socket = await WebSocketTransformer.upgrade(
        request,
        // Disable permessage-deflate to avoid any proxy negotiation delays
        compression: CompressionOptions.compressionOff,
      );
      final dt = DateTime.now().difference(t0);
      final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      final port = request.connectionInfo?.remotePort ?? 0;

      // Use a safe logger wrapper for long-lived async callbacks so we don't
      // attempt to log on the original request Session after it has been
      // closed by Serverpod. session.log can throw if the session is closed,
      // so we catch and fallback to stderr to avoid unhandled zone errors.
      void safeLog(String message, {LogLevel level = LogLevel.info}) {
        try {
          session.log(message, level: level);
        } catch (_) {
          try {
            stderr.writeln(message);
          } catch (_) {
            // ignore
          }
        }
      }

      safeLog('WebSocket: New connection from $remote:$port',
          level: LogLevel.info);
      safeLog('WebSocket: Upgrade completed in ${dt.inMilliseconds} ms',
          level: LogLevel.debug);

      // Set a periodic ping to keep intermediaries from idling out the socket
      try {
        // Control-frame ping at a relatively short interval helps keep many
        // intermediaries (LBs, proxies) from timing out idle connections.
        socket.pingInterval = const Duration(seconds: 20);
      } catch (_) {}

      // In addition to control-frame pings, send an application-level JSON
      // heartbeat. Some intermediaries do not consider WS pings as activity,
      // but any data frame will refresh idle timers. Also lets the client
      // update its "last update" timestamp.
      Timer? appHeartbeat;
      try {
        appHeartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
          try {
            socket.add(jsonEncode({
              'type': 'ping',
              'ts': DateTime.now().toIso8601String(),
            }));
          } catch (_) {
            // Ignore send errors; socket.done handler will clean up.
          }
        });
      } catch (_) {}

      // Track subscribers for debugging
      LogBroadcaster._addSubscriber();

      // Send an initial connected message
      try {
        socket.add(jsonEncode(
            {'type': 'connected', 'message': 'Connected to log websocket'}));
      } catch (_) {}

      // Send recent logs
      try {
        for (var l in LogBroadcaster._recentLogs) {
          socket.add(jsonEncode({'type': 'log', 'message': l}));
        }
      } catch (_) {}

      // Subscribe to live logs
      final subscription =
          LogBroadcaster._logController.stream.listen((message) {
        try {
          final preview = (message.length > 200)
              ? '${message.substring(0, 200)}...'
              : message;
          safeLog('WebSocket: Sending log to client (preview): $preview',
              level: LogLevel.debug);
          socket.add(jsonEncode({'type': 'log', 'message': message}));
        } catch (e) {
          safeLog('WebSocket: Error sending message: $e',
              level: LogLevel.error);
        }
      });

      // Drain any incoming client messages (e.g., client-side keepalives)
      // so the socket doesn't accumulate unread frames. We currently treat
      // all incoming messages as no-ops but may extend this in future.
      try {
        // ignore: cancel_subscriptions
        final incomingListener = socket.listen(
          (data) {
            // If client sends a JSON keepalive, we may echo back a pong to
            // update its timestamp. For now, just ignore.
            // Optionally validate payload size/type to avoid misuse.
          },
          onError: (Object e, StackTrace st) {
            safeLog('WebSocket: Socket error: $e', level: LogLevel.error);
          },
          cancelOnError: true,
        );
        // Ensure we cancel the listener when socket closes
        // (socket.done future below also executes).
        // ignore: unawaited_futures
        socket.done.whenComplete(() {
          try {
            incomingListener.cancel();
          } catch (_) {}
        });
      } catch (_) {}

      // ignore: unawaited_futures
      socket.done.then((_) {
        final cc = socket.closeCode;
        final cr = socket.closeReason;
        safeLog(
            'WebSocket: Client disconnected from $remote:$port (code=${cc ?? 'n/a'}, reason=${cr ?? 'n/a'})',
            level: LogLevel.info);
        try {
          subscription.cancel();
        } catch (_) {}
        try {
          appHeartbeat?.cancel();
        } catch (_) {}
        // Update subscriber count
        LogBroadcaster._removeSubscriber();
      });

      return true;
    } catch (e) {
      session.log('WebSocket: Upgrade failed: $e', level: LogLevel.error);
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
      return true;
    }
  }
}

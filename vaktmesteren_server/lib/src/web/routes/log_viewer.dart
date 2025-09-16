import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:vaktmesteren_server/src/web/widgets/log_viewer_page.dart';
import 'package:serverpod/serverpod.dart';

class RouteLogViewer extends WidgetRoute {
  @override
  Future<Widget> build(Session session, HttpRequest request) async {
    return LogViewerPage();
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
    try {
      print('LogBroadcaster: subscriber connected, total=$_subscriberCount');
    } catch (_) {}
  }

  static void _removeSubscriber() {
    if (_subscriberCount > 0) _subscriberCount--;
    try {
      print('LogBroadcaster: subscriber disconnected, total=$_subscriberCount');
    } catch (_) {}
  }

  // Keep a small in-memory buffer of recent logs so the polling endpoint
  // can return something useful if needed.
  static final List<String> _recentLogs = <String>[];
  static const int _recentLogsMax = 200;

  static void broadcastLog(String message) {
    // Add to stream
    _logController.add(message);

    // Log to console for easier debugging
    try {
      final preview =
          message.length > 120 ? message.substring(0, 120) + '...' : message;
      print('Broadcasting log to buffer: ${preview}');
    } catch (_) {}

    // Maintain recent logs buffer
    try {
      _recentLogs.add(message);
      if (_recentLogs.length > _recentLogsMax) {
        _recentLogs.removeRange(0, _recentLogs.length - _recentLogsMax);
      }
    } catch (e) {
      // ignore errors in buffer maintenance
    }
  }

  /// Broadcast a transient message to currently connected clients without
  /// adding it to the recent buffer. Useful for manual test messages that
  /// shouldn't be replayed to clients who connect later.
  static void broadcastTransient(String message) {
    try {
      _logController.add(message);
    } catch (_) {}
    try {
      final preview =
          message.length > 120 ? message.substring(0, 120) + '...' : message;
      print('Broadcasting transient log: ${preview}');
    } catch (_) {}
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
      print(
          'RouteLogPoll: returning ${LogBroadcaster._recentLogs.length} recent logs');
      final payload = {'logs': List<String>.from(LogBroadcaster._recentLogs)};
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
        request.response.write('Error: ' + e.toString());
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
      final socket = await WebSocketTransformer.upgrade(request);
      final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      final port = request.connectionInfo?.remotePort ?? 0;
      print('WebSocket: New connection from $remote:$port');

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
              ? message.substring(0, 200) + '...'
              : message;
          print('WebSocket: Sending log to client (preview): ${preview}');
          socket.add(jsonEncode({'type': 'log', 'message': message}));
        } catch (e) {
          print('WebSocket: Error sending message: $e');
        }
      });

      socket.done.then((_) {
        print('WebSocket: Client disconnected from $remote:$port');
        try {
          subscription.cancel();
        } catch (_) {}
        // Update subscriber count
        LogBroadcaster._removeSubscriber();
      });

      return true;
    } catch (e) {
      print('WebSocket: Upgrade failed: $e');
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
      return true;
    }
  }
}

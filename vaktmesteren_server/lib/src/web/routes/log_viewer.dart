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

class RouteLogStream extends Route {
  static final StreamController<String> _logController =
      StreamController<String>.broadcast();

  static void broadcastLog(String message) {
    _logController.add(message);
  }

  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    // Set headers for Server-Sent Events
    request.response.headers.set('Content-Type', 'text/event-stream');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers
        .set('Access-Control-Allow-Headers', 'Cache-Control');

    // Send initial connection message
    request.response.write('data: ${jsonEncode({
          'type': 'connected',
          'message': 'Connected to log stream'
        })}\n\n');
    await request.response.flush();

    // Subscribe to log stream
    late StreamSubscription<String> subscription;
    subscription = _logController.stream.listen((message) {
      try {
        request.response.write(
            'data: ${jsonEncode({'type': 'log', 'message': message})}\n\n');
        request.response.flush();
      } catch (e) {
        // Client might have disconnected
        subscription.cancel();
      }
    });

    // Handle client disconnect
    late Timer timer;
    request.response.done.then((_) {
      subscription.cancel();
      timer.cancel();
    });

    // Keep connection alive
    timer = Timer.periodic(Duration(seconds: 30), (_) {
      try {
        request.response.write('data: ${jsonEncode({'type': 'ping'})}\n\n');
        request.response.flush();
      } catch (e) {
        timer.cancel();
      }
    });

    // Wait for client to disconnect
    await request.response.done;
    timer.cancel();
    subscription.cancel();

    return true;
  }
}

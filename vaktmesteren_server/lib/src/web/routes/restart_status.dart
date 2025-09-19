import 'dart:convert';
import 'dart:io';
import 'package:serverpod/serverpod.dart';

/// JSON API route returning restart service statistics and pending retries
class RouteRestartStatus extends Route {
  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    // Only allow GET requests
    if (request.method != 'GET') {
      request.response.statusCode = 405;
      request.response.headers.set('Content-Type', 'application/json');
      await request.response.close();
      return true;
    }

    try {
      Map<String, dynamic> response = {
        'timestamp': DateTime.now().toIso8601String(),
        'restartStats': 'Not implemented yet',
        'pendingRetries': 'Not implemented yet',
        'message':
            'Restart status endpoint is working. Full implementation requires access to restart service.',
      };

      request.response.statusCode = 200;
      request.response.headers.set('Content-Type', 'application/json');
      request.response.headers.set('Cache-Control', 'no-cache');

      request.response.write(jsonEncode(response));
      await request.response.close();

      return true;
    } catch (e) {
      session.log('RouteRestartStatus error: $e', level: LogLevel.error);

      request.response.statusCode = 500;
      request.response.headers.set('Content-Type', 'application/json');
      request.response.write(jsonEncode({
        'error': 'Internal server error',
        'timestamp': DateTime.now().toIso8601String(),
      }));
      await request.response.close();
      return true;
    }
  }
}

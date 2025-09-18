import 'dart:convert';
import 'dart:io';
import 'package:serverpod/serverpod.dart';
import 'package:vaktmesteren_server/src/generated/protocol.dart';
import 'package:vaktmesteren_server/src/web/widgets/alert_history_page.dart';

/// JSON API route returning paginated alert history.
class RouteAlertHistoryJson extends Route {
  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    try {
      final query = request.uri.queryParameters;
      final limit = int.tryParse(query['limit'] ?? '') ?? 100;
      final offset = int.tryParse(query['offset'] ?? '') ?? 0;
      final stateFilter =
          query.containsKey('state') ? int.tryParse(query['state']!) : null;

      final threeDaysAgo = DateTime.now().toUtc().subtract(Duration(days: 3));

      session.log(
          'Alert history API called: limit=$limit, offset=$offset, stateFilter=$stateFilter',
          level: LogLevel.info);

      final rows = await AlertHistory.db.find(
        session,
        where: (t) => (stateFilter != null)
            ? ((t.createdAt >= threeDaysAgo) & t.state.equals(stateFilter))
            : (t.createdAt >= threeDaysAgo),
        limit: limit,
        offset: offset,
        orderBy: (t) => t.createdAt,
        orderDescending: true,
      );

      session.log('Found ${rows.length} alert history rows',
          level: LogLevel.info);

      final payload = {
        'rows': rows.map((r) => r.toJson()).toList(),
        'count': rows.length,
      };

      request.response.headers
          .set('Content-Type', 'application/json; charset=utf-8');
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

/// Widget route to display the alert history page.
class RouteAlertHistoryPage extends WidgetRoute {
  @override
  Future<Widget> build(Session session, HttpRequest request) async {
    final page = AlertHistoryPage();

    // Embed logo as data URL if available so it can be used as favicon too.
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

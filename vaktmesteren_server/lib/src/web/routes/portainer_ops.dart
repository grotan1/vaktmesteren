import 'dart:io';
import 'dart:convert';
import 'package:serverpod/serverpod.dart';
import 'package:vaktmesteren_server/src/ops/config/portainer_config_loader.dart';

/// Internal-only route to perform Portainer ops. This route is intentionally
/// restricted to internal/private networks (loopback and RFC1918 ranges).
class RoutePortainerOpsCheckService extends Route {
  bool _isPrivateAddress(String addr) {
    if (addr == '127.0.0.1' || addr == '::1') return true;
    try {
      final parts = addr.split('.').map(int.parse).toList();
      if (parts.length == 4) {
        final a = parts[0];
        final b = parts[1];
        // 10.0.0.0/8
        if (a == 10) return true;
        // 172.16.0.0/12
        if (a == 172 && b >= 16 && b <= 31) return true;
        // 192.168.0.0/16
        if (a == 192 && b == 168) return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<bool> handleCall(Session session, HttpRequest request) async {
    // Only allow internal/private addresses
    final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    if (!_isPrivateAddress(remote)) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write(jsonEncode({'error': 'forbidden'}));
      await request.response.close();
      return true;
    }

    // Only POST allowed
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set('Allow', 'POST');
      await request.response.close();
      return true;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final configPath = data['config'] ?? 'config/portainer_ci_cd.yaml';
      final serviceId = data['service_id'];
      final serviceName = data['service_name'];
      final endpointId = data['endpoint_id'];

      final config = PortainerConfig.fromYamlFile(configPath);
      final client = await config.createClient();
      final eid = endpointId is int ? endpointId : config.endpointId;

      Map<String, dynamic>? service;
      if (serviceId != null) {
        service = await client.getService(eid, serviceId as int);
      } else if (serviceName != null) {
        final res = await client.get('/api/endpoints/$eid/docker/services');
        if (res.statusCode != 200) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(jsonEncode({
            'running': false,
            'reason': 'Portainer API returned ${res.statusCode}',
            'body': res.body,
          }));
          await request.response.close();
          return true;
        }
        final list = jsonDecode(res.body) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final spec = item['Spec'];
            if (spec is Map<String, dynamic>) {
              final name = spec['Name'] ?? item['Name'];
              if (name == serviceName) {
                service = Map<String, dynamic>.from(item);
                break;
              }
            }
          }
        }
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        request.response
            .write(jsonEncode({'error': 'missing service_id or service_name'}));
        await request.response.close();
        return true;
      }

      if (service == null) {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(
            jsonEncode({'running': false, 'reason': 'service-not-found'}));
        await request.response.close();
        return true;
      }

      int desired = 0;
      try {
        desired = service['Spec']?['Mode']?['Replicated']?['Replicas'] ?? 0;
      } catch (_) {}

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'running': true,
        'service': {
          'id': service['ID'],
          'name': service['Spec']?['Name'] ?? service['Name'],
          'desired_replicas': desired,
        }
      }));
      await request.response.close();
      return true;
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': e.toString()}));
        await request.response.close();
        return true;
      } catch (_) {
        return true;
      }
    }
  }
}

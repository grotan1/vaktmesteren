import 'dart:convert';
import 'package:serverpod/serverpod.dart';
import 'package:vaktmesteren_server/src/ops/config/portainer_config_loader.dart';

class PortainerOpsEndpoint extends Endpoint {
  // No internal token used — endpoint intentionally open.

  /// Check whether a service exists in Portainer.
  ///
  /// This endpoint is intentionally left open (no auth) per operator request.
  Future<Map<String, dynamic>> checkService(Session session,
      {int? serviceId,
      String? serviceName,
      String? configPath,
      int? endpointId}) async {
    final cfgPath = configPath ?? 'config/external/portainer_ci_cd.yaml';
    final cfg = PortainerConfig.fromYamlFile(cfgPath);
    final client = await cfg.createClient();
    final eid = endpointId ?? cfg.endpointId;

    Map<String, dynamic>? service;
    if (serviceId != null) {
      service = await client.getService(eid, serviceId);
    } else if (serviceName != null) {
      final res = await client.get('/api/endpoints/$eid/docker/services');
      if (res.statusCode != 200) {
        return {
          'running': false,
          'reason': 'portainer-error',
          'status': res.statusCode,
          'body': res.body,
        };
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final spec = item['Spec'];
          final name =
              spec is Map<String, dynamic> ? spec['Name'] : item['Name'];
          if (name == serviceName) {
            service = Map<String, dynamic>.from(item);
            break;
          }
        }
      }
    } else {
      throw ArgumentError('serviceId or serviceName required');
    }

    if (service == null) {
      return {'running': false, 'reason': 'service-not-found'};
    }

    int desired = 0;
    try {
      desired = service['Spec']?['Mode']?['Replicated']?['Replicas'] ?? 0;
    } catch (_) {}

    return {
      'running': true,
      'service': {
        'id': service['ID'],
        'name': service['Spec']?['Name'] ?? service['Name'],
        'desired_replicas': desired,
      }
    };
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:vaktmesteren_server/src/ops/portainer_config_loader.dart';

void usage() {
  print('''
Usage: portainer_cli.dart <command> [options]

Commands:
  check-service    Check whether a service exists in Portainer

Options:
  --config <path>       Path to config YAML (default: config/portainer_ci_cd.yaml)
  --endpoint <id>       Endpoint id (overrides config endpoint_id)
  --service-id <id>     Numeric service id to check
  --service-name <name> Service name to look up

Examples:
  dart run bin/portainer_cli.dart check-service --service-name my-service
  dart run bin/portainer_cli.dart check-service --service-id 1234
''');
}

Future<int> main(List<String> args) async {
  if (args.isEmpty) {
    usage();
    return 64;
  }

  final command = args[0];
  final opts = _parseArgs(args.sublist(1));
  final configPath = opts['config'] ?? 'config/portainer_ci_cd.yaml';

  PortainerConfig config;
  try {
    config = PortainerConfig.fromYamlFile(configPath);
  } catch (e) {
    stderr.writeln(jsonEncode({
      'running': false,
      'reason': 'Failed to load config: $e',
      'timestamp': DateTime.now().toIso8601String()
    }));
    return 2;
  }

  final client = await config.createClient();
  final endpointId =
      int.tryParse(opts['endpoint']?.toString() ?? '') ?? config.endpointId;

  if (command == 'check-service') {
    final serviceIdArg = opts['service-id'];
    final serviceName = opts['service-name'];

    try {
      Map<String, dynamic>? service;
      if (serviceIdArg != null) {
        final sid = int.tryParse(serviceIdArg.toString());
        if (sid == null) {
          stderr.writeln(jsonEncode({
            'running': false,
            'reason': 'Invalid --service-id value',
            'timestamp': DateTime.now().toIso8601String()
          }));
          return 3;
        }
        service = await client.getService(endpointId, sid);
      } else if (serviceName != null) {
        // Fetch services list and try to find by name
        final res =
            await client.get('/api/endpoints/$endpointId/docker/services');
        if (res.statusCode != 200) {
          stderr.writeln(jsonEncode({
            'running': false,
            'reason':
                'Portainer API returned ${res.statusCode} while listing services',
            'body': res.body,
            'timestamp': DateTime.now().toIso8601String()
          }));
          return 4;
        }
        final list = jsonDecode(res.body) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final spec = item['Spec'];
            if (spec is Map<String, dynamic>) {
              final name =
                  spec['Name'] ?? spec['Labels']?['com.docker.stack.namespace'];
              if (name == serviceName || item['Name'] == serviceName) {
                service = Map<String, dynamic>.from(item);
                break;
              }
            }
          }
        }
      } else {
        stderr.writeln(jsonEncode({
          'running': false,
          'reason': 'Either --service-id or --service-name must be provided',
          'timestamp': DateTime.now().toIso8601String()
        }));
        return 64;
      }

      if (service == null) {
        stdout.writeln(jsonEncode({
          'running': false,
          'reason': 'service-not-found',
          'timestamp': DateTime.now().toIso8601String()
        }));
        return 2;
      }

      // Basic sanity: service exists. Optionally inspect replication mode.
      int desired = 0;
      try {
        desired = service['Spec']?['Mode']?['Replicated']?['Replicas'] ?? 0;
      } catch (_) {}

      stdout.writeln(jsonEncode({
        'running': true,
        'service': {
          'id': service['ID'],
          'name': service['Spec']?['Name'] ?? service['Name'],
          'desired_replicas': desired,
        },
        'timestamp': DateTime.now().toIso8601String()
      }));
      return 0;
    } catch (e) {
      stderr.writeln(jsonEncode({
        'running': false,
        'reason': 'exception',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String()
      }));
      return 3;
    }
  }

  usage();
  return 64;
}

Map<String, dynamic> _parseArgs(List<String> args) {
  final map = <String, dynamic>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--config' && i + 1 < args.length) {
      map['config'] = args[++i];
    } else if (a == '--endpoint' && i + 1 < args.length) {
      map['endpoint'] = args[++i];
    } else if (a == '--service-id' && i + 1 < args.length) {
      map['service-id'] = args[++i];
    } else if (a == '--service-name' && i + 1 < args.length) {
      map['service-name'] = args[++i];
    } else if (a == '--help' || a == '-h') {
      map['help'] = true;
    }
  }
  return map;
}

import 'dart:io';
import 'package:yaml/yaml.dart';
import 'portainer_client.dart';

class PortainerConfig {
  final String baseUrl;
  final int endpointId;
  final String? token;
  final String? internalToken;

  PortainerConfig({
    required this.baseUrl,
    required this.endpointId,
    this.token,
    this.internalToken,
  });

  factory PortainerConfig.fromYamlFile(String path) {
    final file = File(path);
    final content = file.readAsStringSync();
    final doc = loadYaml(content) as YamlMap;
    final p = doc['portainer'] as YamlMap;
    return PortainerConfig(
      baseUrl: p['base_url'] ?? p['url'],
      endpointId: p['endpoint_id'] ?? 1,
      token: p['token'],
      internalToken: p['internal_token'] ?? p['internalToken'],
    );
  }

  Future<PortainerClient> createClient() async {
    if (token != null && token!.isNotEmpty) {
      return PortainerClient.withToken(baseUrl, token!);
    }
    throw Exception(
        'No valid Portainer auth configured in config file. Please provide token.');
  }
}

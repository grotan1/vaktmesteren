import 'package:yaml/yaml.dart';
import 'dart:io';

void main() async {
  try {
    print('Testing YAML parsing...');
    final content = await File('config/ssh_restart.yaml').readAsString();
    print('File read successfully, content length: ${content.length}');
    
    final yaml = loadYaml(content);
    print('YAML parsed successfully: ${yaml.runtimeType}');
    
    print('enabled: ${yaml['enabled']}');
    print('logOnly: ${yaml['logOnly']}');
    print('connections: ${yaml['connections']?.length ?? 0}');
    print('rules: ${yaml['rules']?.length ?? 0}');
    
    if (yaml['connections'] != null) {
      print('Connection names:');
      for (final key in yaml['connections'].keys) {
        print('  - $key');
      }
    }
    
    if (yaml['rules'] != null) {
      print('Rules:');
      for (int i = 0; i < yaml['rules'].length; i++) {
        final rule = yaml['rules'][i];
        print('  Rule $i: ${rule['icingaServicePattern']} -> ${rule['systemdServiceName']}');
      }
    }
    
  } catch (e, stackTrace) {
    print('Error: $e');
    print('Stack trace: $stackTrace');
  }
}
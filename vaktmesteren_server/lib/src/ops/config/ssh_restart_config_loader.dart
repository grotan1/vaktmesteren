import 'dart:io';
import 'package:serverpod/serverpod.dart';
import 'package:yaml/yaml.dart';
import '../models/restart_rule.dart';

/// Configuration loader for SSH restart system
class SshRestartConfigLoader {
  /// Load SSH restart configuration from YAML file
  static Future<SshRestartConfig> loadConfig(
    Session session, {
    String configPath = 'config/external/ssh_restart.yaml',
  }) async {
    try {
      session.log('Loading SSH restart config from: $configPath',
          level: LogLevel.info);

      final configFile = File(configPath);

      if (!await configFile.exists()) {
        session.log('SSH restart config file not found: $configPath',
            level: LogLevel.warning);

        // Return default config if file doesn't exist
        return const SshRestartConfig(
          connections: {},
          rules: [],
          enabled: false,
          logOnly: true,
        );
      }

      final configContent = await configFile.readAsString();
      final yamlMap = loadYaml(configContent) as Map;

      session.log('SSH restart config loaded successfully',
          level: LogLevel.info);

      return SshRestartConfig.fromMap(Map<String, dynamic>.from(yamlMap));
    } catch (e, stackTrace) {
      session.log(
        'Failed to load SSH restart config: $e\nStack trace: $stackTrace',
        level: LogLevel.error,
      );

      // Return safe default config on error
      return const SshRestartConfig(
        connections: {},
        rules: [],
        enabled: false,
        logOnly: true,
      );
    }
  }

  /// Load environment-specific config
  static Future<SshRestartConfig> loadEnvironmentConfig(
    Session session,
    String environment, {
    String configDir = 'config/external',
  }) async {
    final configPath = '$configDir/ssh_restart_$environment.yaml';

    session.log('Loading SSH restart config for environment: $environment',
        level: LogLevel.info);

    return await loadConfig(session, configPath: configPath);
  }

  /// Validate configuration
  static List<String> validateConfig(SshRestartConfig config) {
    final errors = <String>[];

    // Validate connections
    for (final entry in config.connections.entries) {
      final name = entry.key;
      final connection = entry.value;

      if (connection.host.isEmpty) {
        errors.add('Connection "$name": host cannot be empty');
      }

      if (connection.username.isEmpty) {
        errors.add('Connection "$name": username cannot be empty');
      }

      if (connection.privateKeyPath == null && connection.password == null) {
        errors.add(
            'Connection "$name": must specify either privateKeyPath or password');
      }

      if (connection.port <= 0 || connection.port > 65535) {
        errors.add('Connection "$name": invalid port ${connection.port}');
      }
    }

    // Validate rules
    for (int i = 0; i < config.rules.length; i++) {
      final rule = config.rules[i];

      // icingaServicePattern is now optional (pattern matching disabled)
      // Only validate if it's provided for backward compatibility
      if (rule.icingaServicePattern != null &&
          rule.icingaServicePattern!.isEmpty) {
        errors.add('Rule $i: icingaServicePattern cannot be empty if provided');
      }

      if (rule.systemdServiceName.isEmpty) {
        errors.add('Rule $i: systemdServiceName cannot be empty');
      }

      if (rule.sshConnectionName.isEmpty) {
        errors.add('Rule $i: sshConnectionName cannot be empty');
      }

      // Check if referenced connection exists
      if (!config.connections.containsKey(rule.sshConnectionName)) {
        errors.add(
            'Rule $i: SSH connection "${rule.sshConnectionName}" not found');
      }

      if (rule.maxRestarts <= 0) {
        errors.add('Rule $i: maxRestarts must be positive');
      }

      if (rule.cooldownPeriod.isNegative) {
        errors.add('Rule $i: cooldownPeriod cannot be negative');
      }
    }

    return errors;
  }

  /// Generate example configuration file
  static String generateExampleConfig() {
    return '''
# SSH Restart Configuration
# This configuration defines how to restart Linux services via SSH when Icinga2 alerts trigger

# Global settings
enabled: true
logOnly: true  # Set to false to enable real SSH execution (use with caution!)

# SSH Connection definitions
connections:
  web-server-1:
    host: "192.168.1.10"
    port: 22
    username: "monitoring"
    privateKeyPath: "/etc/ssh/monitoring_key"
    # password: "alternative_to_key"  # Use either privateKeyPath or password, not both
    timeoutSeconds: 30

  database-server:
    host: "db.example.com"
    port: 2222
    username: "sysadmin"
    privateKeyPath: "/etc/ssh/db_monitoring_key"
    timeoutSeconds: 45

# Restart rules - define which Icinga2 services trigger which systemd restarts
rules:
  - icingaServicePattern: "nginx"           # Match Icinga2 service names containing "nginx"
    systemdServiceName: "nginx"             # Restart this systemd service
    sshConnectionName: "web-server-1"       # On this SSH connection
    enabled: true
    maxRestarts: 3                   # Allow 3 restart attempts (resets when state changes)
    cooldownMinutes: 10                     # Wait 10 minutes between restarts
    preChecks:                              # Commands to run before restart
      - "sudo nginx -t"                     # Test nginx config
    postChecks:                             # Commands to run after restart
      - "sudo systemctl is-active nginx"    # Verify service is running

  - icingaServicePattern: "mysql"
    systemdServiceName: "mysql"
    sshConnectionName: "database-server"
    enabled: true
    maxRestarts: 2                   # Conservative for databases (resets when state changes)
    cooldownMinutes: 15
    preChecks:
      - "sudo mysqladmin ping"              # Check if MySQL is responsive
    postChecks:
      - "sudo systemctl is-active mysql"
      - "sudo mysqladmin ping"

  - icingaServicePattern: "webapp"
    systemdServiceName: "myapp"
    sshConnectionName: "web-server-1"
    enabled: false                          # Disabled rule (for testing)
    maxRestarts: 5
    cooldownMinutes: 5
''';
  }

  /// Save example configuration to file
  static Future<void> createExampleConfig(String path) async {
    final file = File(path);
    await file.writeAsString(generateExampleConfig());
  }
}

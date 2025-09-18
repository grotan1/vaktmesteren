import 'ssh_connection.dart';

/// Defines a rule for restarting services based on Icinga2 alerts
class RestartRule {
  final String icingaServicePattern; // Pattern to match Icinga2 service names
  final String systemdServiceName; // Name of systemd service to restart
  final String sshConnectionName; // Name of SSH connection to use
  final bool enabled;
  final int maxRestartsPerHour;
  final Duration cooldownPeriod;
  final List<String> preChecks; // Commands to run before restart
  final List<String> postChecks; // Commands to run after restart

  const RestartRule({
    required this.icingaServicePattern,
    required this.systemdServiceName,
    required this.sshConnectionName,
    this.enabled = true,
    this.maxRestartsPerHour = 3,
    this.cooldownPeriod = const Duration(minutes: 10),
    this.preChecks = const [],
    this.postChecks = const [],
  });

  factory RestartRule.fromMap(Map<String, dynamic> map) {
    return RestartRule(
      icingaServicePattern: map['icingaServicePattern'] as String,
      systemdServiceName: map['systemdServiceName'] as String,
      sshConnectionName: map['sshConnectionName'] as String,
      enabled: map['enabled'] as bool? ?? true,
      maxRestartsPerHour: map['maxRestartsPerHour'] as int? ?? 3,
      cooldownPeriod: Duration(
        minutes: map['cooldownMinutes'] as int? ?? 10,
      ),
      preChecks: (map['preChecks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      postChecks: (map['postChecks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'icingaServicePattern': icingaServicePattern,
      'systemdServiceName': systemdServiceName,
      'sshConnectionName': sshConnectionName,
      'enabled': enabled,
      'maxRestartsPerHour': maxRestartsPerHour,
      'cooldownMinutes': cooldownPeriod.inMinutes,
      'preChecks': preChecks,
      'postChecks': postChecks,
    };
  }

  /// Check if this rule matches an Icinga2 service name
  bool matchesService(String icingaServiceName) {
    // Simple pattern matching - could be enhanced with regex
    return icingaServiceName.contains(icingaServicePattern);
  }

  /// Get the systemctl restart command
  String get restartCommand => 'sudo systemctl restart $systemdServiceName';

  /// Get the systemctl status command
  String get statusCommand => 'sudo systemctl status $systemdServiceName';

  @override
  String toString() =>
      'RestartRule($icingaServicePattern -> $systemdServiceName on $sshConnectionName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestartRule &&
          runtimeType == other.runtimeType &&
          icingaServicePattern == other.icingaServicePattern &&
          systemdServiceName == other.systemdServiceName &&
          sshConnectionName == other.sshConnectionName;

  @override
  int get hashCode =>
      Object.hash(icingaServicePattern, systemdServiceName, sshConnectionName);
}

/// Configuration for the SSH restart system
class SshRestartConfig {
  final Map<String, SshConnection> connections;
  final List<RestartRule> rules;
  final bool enabled;
  final bool logOnly; // If true, only log commands instead of executing

  const SshRestartConfig({
    required this.connections,
    required this.rules,
    this.enabled = true,
    this.logOnly = true, // Default to log-only mode for safety
  });

  factory SshRestartConfig.fromMap(Map<String, dynamic> map) {
    // Handle YamlMap by converting to regular Map
    final connectionsData = map['connections'];
    final connectionsMap = connectionsData != null
        ? Map<String, dynamic>.from(connectionsData as Map)
        : <String, dynamic>{};
    final connections = <String, SshConnection>{};

    for (final entry in connectionsMap.entries) {
      connections[entry.key] = SshConnection.fromMap(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    final rulesData = map['rules'] as List<dynamic>? ?? [];
    final rules = rulesData
        .map((e) => RestartRule.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    final enabled = map['enabled'] as bool? ?? true;
    final logOnly = map['logOnly'] as bool? ?? true;

    return SshRestartConfig(
      connections: connections,
      rules: rules,
      enabled: enabled,
      logOnly: logOnly,
    );
  }

  /// Find restart rules that match an Icinga2 service
  List<RestartRule> findMatchingRules(String icingaServiceName) {
    return rules
        .where((rule) => rule.enabled && rule.matchesService(icingaServiceName))
        .toList();
  }

  /// Get SSH connection by name
  SshConnection? getConnection(String name) {
    return connections[name];
  }

  @override
  String toString() =>
      'SshRestartConfig(${connections.length} connections, ${rules.length} rules, enabled=$enabled, logOnly=$logOnly)';
}

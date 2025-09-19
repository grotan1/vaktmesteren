import 'ssh_connection.dart';

/// Defines a rule for restarting services based on Icinga2 alerts
class RestartRule {
  final String?
      icingaServicePattern; // Pattern to match Icinga2 service names (deprecated - only used for backward compatibility)
  final String systemdServiceName; // Name of systemd service to restart
  final String
      sshConnectionName; // Name of SSH connection to use (defaults to "auto")
  final bool enabled;
  final int
      maxRestarts; // Maximum restart attempts (resets when Icinga state changes from CRITICAL to OK)
  final Duration cooldownPeriod;
  final List<String> preChecks; // Commands to run before restart
  final List<String> postChecks; // Commands to run after restart

  const RestartRule({
    this.icingaServicePattern,
    required this.systemdServiceName,
    this.sshConnectionName = "auto",
    this.enabled = true,
    this.maxRestarts =
        3, // Default: allow 3 restart attempts (resets on state change)
    this.cooldownPeriod = const Duration(minutes: 10),
    this.preChecks = const [],
    this.postChecks = const [],
  });

  factory RestartRule.fromMap(Map<String, dynamic> map) {
    return RestartRule(
      icingaServicePattern: map['icingaServicePattern'] as String?,
      systemdServiceName: map['systemdServiceName'] as String,
      sshConnectionName: map['sshConnectionName'] as String? ?? "auto",
      enabled: map['enabled'] as bool? ?? true,
      maxRestarts: map['maxRestarts'] as int? ??
          map['maxRestartsPerHour'] as int? ??
          3, // Backward compatibility: accept old field name
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
      'maxRestarts': maxRestarts,
      'cooldownMinutes': cooldownPeriod.inMinutes,
      'preChecks': preChecks,
      'postChecks': postChecks,
    };
  }

  /// Check if this rule matches an Icinga2 service name
  /// DISABLED: Pattern matching is no longer supported - only auto-detection via systemd_unit_unit
  bool matchesService(String icingaServiceName) {
    // Pattern matching disabled - only use auto-detection via systemd_unit_unit
    return false;
  }

  /// Get the systemctl restart command
  String get restartCommand => 'sudo systemctl restart $systemdServiceName';

  /// Get the systemctl status command (for detailed status information)
  String get statusCommand => 'sudo systemctl status $systemdServiceName';

  /// Get the systemctl is-active command (for reliable running state check)
  String get isActiveCommand => 'sudo systemctl is-active $systemdServiceName';

  /// Get the systemctl is-enabled command (to check if service is enabled)
  String get isEnabledCommand =>
      'sudo systemctl is-enabled $systemdServiceName';

  /// Get the systemctl enable command (to enable the service)
  String get enableCommand => 'sudo systemctl enable $systemdServiceName';

  @override
  String toString() =>
      'RestartRule(${icingaServicePattern ?? "auto-detect"} -> $systemdServiceName on $sshConnectionName)';

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

  /// Find restart rules that match a systemd service name
  /// Used for auto-detected services from systemd_unit_unit variable
  RestartRule? findRuleBySystemdService(String systemdServiceName) {
    return rules
        .where((rule) =>
            rule.enabled && rule.systemdServiceName == systemdServiceName)
        .firstOrNull;
  }

  /// Get SSH connection by name
  SshConnection? getConnection(String name) {
    return connections[name];
  }

  /// Get SSH connection by hostname (from Icinga2 host_name)
  /// This allows automatic connection selection based on the target host
  SshConnection? getConnectionByHost(String hostName) {
    // First try exact hostname match
    for (final connection in connections.values) {
      if (connection.host == hostName) {
        return connection;
      }
    }

    // If no exact match, try to find by connection name matching hostname
    // This handles cases where connection name matches the hostname
    return connections[hostName];
  }

  @override
  String toString() =>
      'SshRestartConfig(${connections.length} connections, ${rules.length} rules, enabled=$enabled, logOnly=$logOnly)';
}

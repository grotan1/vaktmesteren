/// SSH client configuration
class SshConfig {
  final bool enabled;
  final int maxConnections;
  final Duration connectionTimeout;
  final Duration commandTimeout;
  final int maxRetries;
  final Duration retryDelay;
  final bool verifyHostKeys;
  final String? knownHostsPath;
  final bool logCommands;
  final bool logConnectionEvents;

  const SshConfig({
    this.enabled = false,
    this.maxConnections = 10,
    this.connectionTimeout = const Duration(seconds: 30),
    this.commandTimeout = const Duration(minutes: 5),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.verifyHostKeys = true,
    this.knownHostsPath,
    this.logCommands = true,
    this.logConnectionEvents = true,
  });

  factory SshConfig.fromMap(Map<String, dynamic> map) {
    return SshConfig(
      enabled: map['enabled'] as bool? ?? false,
      maxConnections: map['maxConnections'] as int? ?? 10,
      connectionTimeout: Duration(
        seconds: map['connectionTimeoutSeconds'] as int? ?? 30,
      ),
      commandTimeout: Duration(
        seconds: map['commandTimeoutSeconds'] as int? ?? 300,
      ),
      maxRetries: map['maxRetries'] as int? ?? 3,
      retryDelay: Duration(
        seconds: map['retryDelaySeconds'] as int? ?? 2,
      ),
      verifyHostKeys: map['verifyHostKeys'] as bool? ?? true,
      knownHostsPath: map['knownHostsPath'] as String?,
      logCommands: map['logCommands'] as bool? ?? true,
      logConnectionEvents: map['logConnectionEvents'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'maxConnections': maxConnections,
      'connectionTimeoutSeconds': connectionTimeout.inSeconds,
      'commandTimeoutSeconds': commandTimeout.inSeconds,
      'maxRetries': maxRetries,
      'retryDelaySeconds': retryDelay.inSeconds,
      'verifyHostKeys': verifyHostKeys,
      'knownHostsPath': knownHostsPath,
      'logCommands': logCommands,
      'logConnectionEvents': logConnectionEvents,
    };
  }

  @override
  String toString() =>
      'SshConfig(enabled=$enabled, maxConnections=$maxConnections)';
}

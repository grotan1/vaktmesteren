/// SSH connection configuration for remote Linux servers
class SshConnection {
  final String host;
  final int port;
  final String username;
  final String? privateKeyPath;
  final String? password;
  final Duration timeout;
  final String name; // Friendly name for logging

  const SshConnection({
    required this.host,
    this.port = 22,
    required this.username,
    this.privateKeyPath,
    this.password,
    this.timeout = const Duration(seconds: 30),
    required this.name,
  });

  factory SshConnection.fromMap(String name, Map<String, dynamic> map) {
    return SshConnection(
      name: name,
      host: map['host'] as String,
      port: map['port'] as int? ?? 22,
      username: map['username'] as String,
      privateKeyPath: map['privateKeyPath'] as String?,
      password: map['password'] as String?,
      timeout: Duration(
        seconds: map['timeoutSeconds'] as int? ?? 30,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'privateKeyPath': privateKeyPath,
      'password': password,
      'timeoutSeconds': timeout.inSeconds,
    };
  }

  /// Get connection string for logging (without sensitive data)
  String get connectionString => '$username@$host:$port';

  /// Check if this connection uses key-based authentication
  bool get usesKeyAuth => privateKeyPath != null;

  @override
  String toString() => 'SshConnection($name: $connectionString)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshConnection &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          name == other.name;

  @override
  int get hashCode => Object.hash(host, port, username, name);
}

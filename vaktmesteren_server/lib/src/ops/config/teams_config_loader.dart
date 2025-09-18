import 'dart:io';
import 'package:serverpod/serverpod.dart';
import 'package:yaml/yaml.dart';
import '../models/teams_config.dart';

/// Configuration loader for Teams notification system
class TeamsConfigLoader {
  /// Load Teams notification configuration from YAML file
  static Future<TeamsConfig> loadConfig(
    Session session, {
    String configPath = 'config/teams_notifications.yaml',
  }) async {
    try {
      session.log('Loading Teams notification config from: $configPath',
          level: LogLevel.info);

      final configFile = File(configPath);

      if (!await configFile.exists()) {
        session.log('Teams notification config file not found: $configPath',
            level: LogLevel.warning);

        // Return default config if file doesn't exist
        return _getDefaultConfig();
      }

      final configContent = await configFile.readAsString();
      final yamlMap = loadYaml(configContent) as Map;

      session.log('Teams notification config loaded successfully',
          level: LogLevel.info);

      final config = TeamsConfig.fromMap(Map<String, dynamic>.from(yamlMap));

      // Validate configuration
      await _validateConfig(config, session);

      return config;
    } catch (e, stackTrace) {
      session.log(
        'Failed to load Teams notification config: $e\\nStack trace: $stackTrace',
        level: LogLevel.error,
      );

      // Return safe default config on error
      return _getDefaultConfig();
    }
  }

  /// Get default configuration when file is missing or invalid
  static TeamsConfig _getDefaultConfig() {
    return const TeamsConfig(
      enabled: false,
      logOnly: true,
      webhooks: {},
      notificationRules: [],
      messageTemplates: {},
      advanced: AdvancedConfig(),
    );
  }

  /// Validate the loaded configuration
  static Future<void> _validateConfig(
      TeamsConfig config, Session session) async {
    if (!config.enabled) {
      session.log('Teams notifications are disabled in config',
          level: LogLevel.info);
      return;
    }

    // Validate webhooks
    for (final webhook in config.webhooks.values) {
      if (!_isValidWebhookUrl(webhook.url)) {
        session.log(
            'Invalid Teams webhook URL for ${webhook.name}: ${webhook.url}',
            level: LogLevel.warning);
      }
    }

    // Validate notification rules
    for (final rule in config.notificationRules) {
      final invalidChannels = rule.channels
          .where((channel) => !config.webhooks.containsKey(channel))
          .toList();

      if (invalidChannels.isNotEmpty) {
        session.log(
          'Notification rule "${rule.name}" references invalid channels: ${invalidChannels.join(", ")}',
          level: LogLevel.warning,
        );
      }
    }

    // Validate webhook URLs if enabled
    if (config.advanced.validateWebhookUrls) {
      await _validateWebhookUrls(config, session);
    }

    session.log('Teams configuration validation completed',
        level: LogLevel.info);
  }

  /// Check if a webhook URL looks valid
  static bool _isValidWebhookUrl(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);
      return uri.hasScheme &&
          uri.hasAuthority &&
          (uri.scheme == 'https') &&
          (uri.host.contains('webhook.office.com') ||
              uri.host.contains('outlook.office.com'));
    } catch (e) {
      return false;
    }
  }

  /// Validate webhook URLs by testing connectivity
  static Future<void> _validateWebhookUrls(
      TeamsConfig config, Session session) async {
    final httpClient = HttpClient();

    try {
      for (final webhook in config.webhooks.values) {
        if (!webhook.enabled) continue;

        try {
          session.log('Validating webhook for ${webhook.name}...',
              level: LogLevel.debug);

          final uri = Uri.parse(webhook.url);
          final request = await httpClient.postUrl(uri);

          request.headers.set('Content-Type', 'application/json');
          request.headers.set('User-Agent', 'Vaktmesteren-Teams-Notifier/1.0');

          // Only validate URL structure, don't actually send test message
          // to avoid spam during configuration validation

          session.log('Webhook URL for ${webhook.name} appears valid',
              level: LogLevel.debug);
        } catch (e) {
          session.log(
            'Failed to validate webhook for ${webhook.name}: $e',
            level: LogLevel.warning,
          );
        }
      }
    } finally {
      httpClient.close();
    }
  }

  /// Load and merge environment-specific overrides
  static Future<TeamsConfig> loadConfigWithOverrides(
    Session session, {
    String baseConfigPath = 'config/teams_notifications.yaml',
    String? environmentConfigPath,
  }) async {
    // Load base configuration
    final baseConfig = await loadConfig(session, configPath: baseConfigPath);

    // If no environment override specified, return base config
    if (environmentConfigPath == null ||
        !await File(environmentConfigPath).exists()) {
      return baseConfig;
    }

    try {
      session.log('Loading Teams config overrides from: $environmentConfigPath',
          level: LogLevel.info);

      final overrideFile = File(environmentConfigPath);
      final overrideContent = await overrideFile.readAsString();
      final overrideYamlMap = loadYaml(overrideContent) as Map;
      final overrideConfig =
          TeamsConfig.fromMap(Map<String, dynamic>.from(overrideYamlMap));

      // Merge configurations (override config takes precedence)
      return _mergeConfigs(baseConfig, overrideConfig);
    } catch (e) {
      session.log(
        'Failed to load Teams config overrides, using base config: $e',
        level: LogLevel.warning,
      );
      return baseConfig;
    }
  }

  /// Merge two configurations, with override config taking precedence
  static TeamsConfig _mergeConfigs(TeamsConfig base, TeamsConfig override) {
    // For now, override completely replaces base
    // In the future, could implement smarter merging logic
    return override;
  }

  /// Reload configuration at runtime
  static Future<TeamsConfig> reloadConfig(
    Session session, {
    String configPath = 'config/teams_notifications.yaml',
  }) async {
    session.log('Reloading Teams notification configuration...',
        level: LogLevel.info);
    return loadConfig(session, configPath: configPath);
  }

  /// Get configuration summary for logging
  static String getConfigSummary(TeamsConfig config) {
    if (!config.enabled) {
      return 'Teams notifications: DISABLED';
    }

    final activeWebhooks =
        config.webhooks.values.where((w) => w.enabled).length;
    final activeRules = config.notificationRules.where((r) => r.enabled).length;

    return 'Teams notifications: ENABLED ($activeWebhooks webhooks, $activeRules rules, logOnly=${config.logOnly})';
  }
}

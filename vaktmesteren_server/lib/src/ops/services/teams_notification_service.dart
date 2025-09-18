import 'package:serverpod/serverpod.dart';
import '../models/teams_config.dart';
import '../clients/teams_client.dart';
import '../config/teams_config_loader.dart';

/// Service for processing and sending Teams notifications based on Icinga2 alerts
class TeamsNotificationService {
  final Session _session;
  TeamsConfig? _config;
  TeamsClient? _client;
  final RateLimitTracker _rateLimitTracker = RateLimitTracker();

  TeamsNotificationService(this._session);

  /// Initialize the Teams notification service
  Future<void> initialize({String? configPath}) async {
    try {
      _session.log('Initializing Teams notification service...',
          level: LogLevel.info);

      // Load configuration
      _config = await TeamsConfigLoader.loadConfig(
        _session,
        configPath: configPath ?? 'config/teams_notifications.yaml',
      );

      if (_config == null || !_config!.enabled) {
        _session.log('Teams notifications are disabled', level: LogLevel.info);
        return;
      }

      // Initialize client
      _client = TeamsClient(_session, _config!.advanced);

      _session.log(
        TeamsConfigLoader.getConfigSummary(_config!),
        level: LogLevel.info,
      );

      _session.log('Teams notification service initialized successfully',
          level: LogLevel.info);
    } catch (e, stackTrace) {
      _session.log(
        'Failed to initialize Teams notification service: $e\\nStack trace: $stackTrace',
        level: LogLevel.error,
      );
    }
  }

  /// Process an alert and send Teams notifications if applicable
  Future<void> processAlert({
    required String severity,
    required String host,
    String? service,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    if (_config == null || !_config!.enabled || _client == null) {
      return;
    }

    try {
      _session.log(
        'Processing Teams notification for: $severity alert - $host${service != null ? "/$service" : ""}',
        level: LogLevel.debug,
      );

      // Find matching webhooks based on configuration rules
      final matchingWebhooks =
          _config!.findMatchingWebhooks(severity, host, service);

      if (matchingWebhooks.isEmpty) {
        _session.log(
          'No Teams webhooks match the alert criteria for $host${service != null ? "/$service" : ""} ($severity)',
          level: LogLevel.debug,
        );
        return;
      }

      // Send notifications to matching webhooks
      var sentCount = 0;
      var totalCount = 0;

      for (final webhook in matchingWebhooks) {
        totalCount++;

        if (await _shouldSendNotification(webhook, severity, host, service)) {
          final success = await _sendNotification(
            webhook: webhook,
            severity: severity,
            host: host,
            service: service,
            message: message,
            metadata: metadata,
          );

          if (success) {
            sentCount++;
            _recordNotificationSent(webhook, host, service);
          }
        } else {
          _session.log(
            'Skipping Teams notification to ${webhook.name} due to rate limiting or cooldown',
            level: LogLevel.debug,
          );
        }
      }

      if (sentCount > 0) {
        _session.log(
          '📨 Sent Teams notifications: $sentCount/$totalCount webhooks for $host${service != null ? "/$service" : ""} ($severity)',
          level: LogLevel.info,
        );
      } else if (totalCount > 0) {
        _session.log(
          '⏸️ Teams notifications skipped: $totalCount webhooks for $host${service != null ? "/$service" : ""} (rate limited or cooldown)',
          level: LogLevel.info,
        );
      }
    } catch (e, stackTrace) {
      _session.log(
        'Error processing Teams notification: $e\\nStack trace: $stackTrace',
        level: LogLevel.error,
      );
    }
  }

  /// Check if notification should be sent based on rate limiting and cooldown
  Future<bool> _shouldSendNotification(
    WebhookConfig webhook,
    String severity,
    String host,
    String? service,
  ) async {
    if (_config == null) return false;

    // Check rate limiting per channel
    if (!_rateLimitTracker.canSendToChannel(
        webhook.channelId, _config!.rateLimitPerMinute)) {
      _session.log(
        'Rate limit exceeded for Teams channel ${webhook.name}',
        level: LogLevel.debug,
      );
      return false;
    }

    // Check cooldown for this specific alert
    final alertKey = RateLimitTracker.getAlertKey(host, service);
    if (_rateLimitTracker.isInCooldown(alertKey, _config!.cooldownMinutes)) {
      // Only skip cooldown for recovery messages if rule allows it
      final matchingRules = _config!.notificationRules
          .where((rule) => rule.matchesAlert(severity, host, service))
          .toList();

      final allowRecoveryBypass = severity.toUpperCase() == 'RECOVERY' &&
          matchingRules.any((rule) => !rule.respectCooldown);

      if (!allowRecoveryBypass) {
        _session.log(
          'Alert $alertKey is in cooldown period for Teams notifications',
          level: LogLevel.debug,
        );
        return false;
      }
    }

    return true;
  }

  /// Send notification to a specific webhook
  Future<bool> _sendNotification({
    required WebhookConfig webhook,
    required String severity,
    required String host,
    String? service,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    if (_client == null || _config == null) return false;

    // Get appropriate message template
    final template = _getMessageTemplate(severity);

    try {
      final success = await _client!.sendNotification(
        webhook: webhook,
        severity: severity,
        host: host,
        service: service,
        message: message,
        template: template,
        logOnly: _config!.logOnly,
      );

      if (success) {
        _session.log(
          'Teams notification sent to ${webhook.name}: $severity alert for $host${service != null ? "/$service" : ""}',
          level: LogLevel.debug,
        );
      } else {
        _session.log(
          'Failed to send Teams notification to ${webhook.name}',
          level: LogLevel.warning,
        );
      }

      return success;
    } catch (e) {
      _session.log(
        'Exception sending Teams notification to ${webhook.name}: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  /// Get appropriate message template for severity
  MessageTemplate? _getMessageTemplate(String severity) {
    if (_config?.messageTemplates == null) return null;

    final severityKey = severity.toLowerCase();
    return _config!.messageTemplates[severityKey] ??
        _config!.messageTemplates['default'];
  }

  /// Record that a notification was sent (for rate limiting and cooldown)
  void _recordNotificationSent(
      WebhookConfig webhook, String host, String? service) {
    if (_config == null) return;

    // Record for rate limiting
    _rateLimitTracker.recordMessageSent(webhook.channelId);

    // Record for cooldown
    final alertKey = RateLimitTracker.getAlertKey(host, service);
    _rateLimitTracker.recordAlertSent(alertKey);
  }

  /// Test all configured webhooks
  Future<Map<String, bool>> testAllWebhooks() async {
    final results = <String, bool>{};

    if (_config == null || _client == null) {
      _session.log('Teams service not initialized, cannot test webhooks',
          level: LogLevel.warning);
      return results;
    }

    _session.log('Testing all configured Teams webhooks...',
        level: LogLevel.info);

    for (final webhook in _config!.webhooks.values) {
      if (!webhook.enabled) {
        _session.log('Skipping disabled webhook: ${webhook.name}',
            level: LogLevel.debug);
        results[webhook.name] = false;
        continue;
      }

      try {
        _session.log('Testing webhook: ${webhook.name}', level: LogLevel.debug);
        final success = await _client!.testWebhook(webhook);
        results[webhook.name] = success;

        if (success) {
          _session.log('✅ Webhook test successful: ${webhook.name}',
              level: LogLevel.info);
        } else {
          _session.log('❌ Webhook test failed: ${webhook.name}',
              level: LogLevel.warning);
        }
      } catch (e) {
        _session.log('Exception testing webhook ${webhook.name}: $e',
            level: LogLevel.error);
        results[webhook.name] = false;
      }
    }

    final successCount = results.values.where((success) => success).length;
    _session.log(
      'Teams webhook testing completed: $successCount/${results.length} successful',
      level: LogLevel.info,
    );

    return results;
  }

  /// Reload configuration at runtime
  Future<void> reloadConfiguration({String? configPath}) async {
    try {
      _session.log('Reloading Teams notification configuration...',
          level: LogLevel.info);

      // Close existing client
      _client?.close();

      // Reload configuration
      await initialize(configPath: configPath);

      _session.log('Teams notification configuration reloaded successfully',
          level: LogLevel.info);
    } catch (e, stackTrace) {
      _session.log(
        'Failed to reload Teams configuration: $e\\nStack trace: $stackTrace',
        level: LogLevel.error,
      );
    }
  }

  /// Get service status information
  Map<String, dynamic> getStatus() {
    return {
      'enabled': _config?.enabled ?? false,
      'logOnly': _config?.logOnly ?? true,
      'webhookCount': _config?.webhooks.length ?? 0,
      'activeWebhookCount':
          _config?.webhooks.values.where((w) => w.enabled).length ?? 0,
      'ruleCount': _config?.notificationRules.length ?? 0,
      'activeRuleCount':
          _config?.notificationRules.where((r) => r.enabled).length ?? 0,
      'rateLimitPerMinute': _config?.rateLimitPerMinute ?? 0,
      'cooldownMinutes': _config?.cooldownMinutes ?? 0,
    };
  }

  /// Send a manual test notification
  Future<bool> sendTestNotification({
    required String webhookName,
    String? customMessage,
  }) async {
    if (_config == null || _client == null) {
      _session.log('Teams service not initialized', level: LogLevel.warning);
      return false;
    }

    final webhook = _config!.webhooks[webhookName];
    if (webhook == null) {
      _session.log('Webhook not found: $webhookName', level: LogLevel.warning);
      return false;
    }

    _session.log('Sending manual test notification to: $webhookName',
        level: LogLevel.info);

    return await _client!.sendNotification(
      webhook: webhook,
      severity: 'INFO',
      host: 'test-host',
      service: 'manual-test',
      message: customMessage ??
          'Manual test notification from Vaktmesteren Teams service',
      template: _getMessageTemplate('info'),
      logOnly: false, // Always send real test notifications
    );
  }

  /// Cleanup resources
  void dispose() {
    _client?.close();
    _client = null;
    _config = null;
  }
}

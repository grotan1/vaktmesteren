import 'dart:convert';
import 'dart:io';
import 'package:serverpod/serverpod.dart';
import '../models/teams_config.dart';

/// HTTP client for sending notifications to Microsoft Teams webhooks
class TeamsClient {
  final Session _session;
  final AdvancedConfig _config;
  late final HttpClient _httpClient;

  TeamsClient(this._session, this._config) {
    _httpClient = HttpClient();
    _httpClient.connectionTimeout =
        Duration(seconds: _config.webhookTimeoutSeconds);
  }

  /// Send a notification to Teams webhook
  Future<bool> sendNotification({
    required WebhookConfig webhook,
    required String severity,
    required String host,
    String? service,
    String? message,
    MessageTemplate? template,
    bool logOnly = false,
  }) async {
    try {
      // Create message payload
      final messagePayload = _createMessagePayload(
        severity: severity,
        host: host,
        service: service,
        message: message,
        template: template,
        webhook: webhook,
      );

      if (logOnly) {
        _session.log(
          '📨 SIMULATING Teams notification to ${webhook.name}: $severity alert for $host${service != null ? "/$service" : ""}',
          level: LogLevel.info,
        );

        if (_config.logWebhookPayloads) {
          _session.log(
            'Teams webhook payload (SIMULATION): ${jsonEncode(messagePayload)}',
            level: LogLevel.debug,
          );
        }

        return true; // Simulate success
      }

      // Send actual webhook request
      return await _sendWebhookRequest(webhook, messagePayload);
    } catch (e, stackTrace) {
      _session.log(
        'Failed to send Teams notification to ${webhook.name}: $e\\nStack trace: $stackTrace',
        level: LogLevel.error,
      );
      return false;
    }
  }

  /// Send webhook request with retry logic
  Future<bool> _sendWebhookRequest(
      WebhookConfig webhook, Map<String, dynamic> payload) async {
    var attempt = 0;
    var delaySeconds = _config.retryDelaySeconds;

    while (attempt < _config.retryAttempts) {
      attempt++;

      try {
        _session.log(
          'Sending Teams notification to ${webhook.name} (attempt $attempt/${_config.retryAttempts})',
          level: LogLevel.debug,
        );

        final success = await _performWebhookRequest(webhook, payload);

        if (success) {
          _session.log(
            '✅ Teams notification sent successfully to ${webhook.name}',
            level: LogLevel.info,
          );
          return true;
        } else if (attempt < _config.retryAttempts) {
          _session.log(
            '⚠️ Teams notification failed to ${webhook.name}, retrying in ${delaySeconds}s (attempt $attempt/${_config.retryAttempts})',
            level: LogLevel.warning,
          );

          await Future.delayed(Duration(seconds: delaySeconds));
          delaySeconds =
              (delaySeconds * _config.retryBackoffMultiplier).round();
        }
      } catch (e) {
        _session.log(
          'Teams webhook request error (attempt $attempt): $e',
          level: LogLevel.error,
        );

        if (attempt < _config.retryAttempts) {
          await Future.delayed(Duration(seconds: delaySeconds));
          delaySeconds =
              (delaySeconds * _config.retryBackoffMultiplier).round();
        }
      }
    }

    _session.log(
      '❌ Failed to send Teams notification to ${webhook.name} after ${_config.retryAttempts} attempts',
      level: LogLevel.error,
    );
    return false;
  }

  /// Perform the actual HTTP request to Teams webhook
  Future<bool> _performWebhookRequest(
      WebhookConfig webhook, Map<String, dynamic> payload) async {
    HttpClientRequest? request;
    HttpClientResponse? response;

    try {
      final uri = Uri.parse(webhook.url);
      request = await _httpClient.postUrl(uri);

      // Set headers
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('User-Agent', 'Vaktmesteren-Teams-Notifier/1.0');

      // Send payload
      final jsonPayload = jsonEncode(payload);
      request.write(jsonPayload);

      if (_config.logWebhookPayloads) {
        _session.log(
          'Teams webhook payload to ${webhook.name}: $jsonPayload',
          level: LogLevel.debug,
        );
      }

      // Get response
      response = await request.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      } else {
        final responseBody = await response.transform(utf8.decoder).join();
        _session.log(
          'Teams webhook returned status ${response.statusCode}: $responseBody',
          level: LogLevel.warning,
        );
        return false;
      }
    } finally {
      await response?.detachSocket();
    }
  }

  /// Create message payload for Teams webhook
  Map<String, dynamic> _createMessagePayload({
    required String severity,
    required String host,
    String? service,
    String? message,
    MessageTemplate? template,
    required WebhookConfig webhook,
  }) {
    final now = DateTime.now();
    final serviceName = service ?? 'Host Check';

    if (_config.useAdaptiveCards && template != null) {
      return _createAdaptiveCardPayload(
        severity: severity,
        host: host,
        service: serviceName,
        message: message,
        template: template,
        timestamp: now,
      );
    } else {
      return _createSimpleMessagePayload(
        severity: severity,
        host: host,
        service: serviceName,
        message: message,
        template: template,
        timestamp: now,
      );
    }
  }

  /// Create Adaptive Card payload for rich formatting
  Map<String, dynamic> _createAdaptiveCardPayload({
    required String severity,
    required String host,
    required String service,
    String? message,
    MessageTemplate? template,
    required DateTime timestamp,
  }) {
    final cardBody = <Map<String, dynamic>>[];

    // Title block
    cardBody.add({
      'type': 'TextBlock',
      'text': template?.title ?? _getDefaultTitle(severity),
      'weight': 'Bolder',
      'size': 'Medium',
      'color': _getSeverityColor(severity),
    });

    // Alert details
    final facts = <Map<String, dynamic>>[];

    if (template?.includeFields.contains('host') ?? true) {
      facts.add({'title': 'Host', 'value': host});
    }

    if (template?.includeFields.contains('service') ?? true) {
      facts.add({'title': 'Service', 'value': service});
    }

    if (message != null &&
        (template?.includeFields.contains('message') ?? true)) {
      facts.add({'title': 'Message', 'value': message});
    }

    if (template?.includeFields.contains('timestamp') ?? true) {
      facts.add({'title': 'Time', 'value': _formatTimestamp(timestamp)});
    }

    if (facts.isNotEmpty) {
      cardBody.add({
        'type': 'FactSet',
        'facts': facts,
      });
    }

    // Custom message
    if (template?.customMessage.isNotEmpty ?? false) {
      cardBody.add({
        'type': 'TextBlock',
        'text': template!.customMessage,
        'wrap': true,
        'style': 'emphasis',
      });
    }

    // Platform info
    if (_config.includePlatformInfo) {
      cardBody.add({
        'type': 'TextBlock',
        'text': 'Sent by Vaktmesteren monitoring system',
        'size': 'Small',
        'color': 'Accent',
        'isSubtle': true,
      });
    }

    final adaptiveCard = AdaptiveCard(body: cardBody);

    return {
      'type': 'message',
      'attachments': [
        {
          'contentType': 'application/vnd.microsoft.card.adaptive',
          'content': adaptiveCard.toJson(),
        }
      ],
    };
  }

  /// Create simple message payload for basic formatting
  Map<String, dynamic> _createSimpleMessagePayload({
    required String severity,
    required String host,
    required String service,
    String? message,
    MessageTemplate? template,
    required DateTime timestamp,
  }) {
    final sections = <Map<String, dynamic>>[];

    // Main section
    final mainSection = <String, dynamic>{
      'activityTitle': template?.title ?? _getDefaultTitle(severity),
      'activitySubtitle': 'Alert from Vaktmesteren monitoring',
      'facts': <Map<String, dynamic>>[],
    };

    // Add facts
    if (template?.includeFields.contains('host') ?? true) {
      mainSection['facts'].add({'name': 'Host', 'value': host});
    }

    if (template?.includeFields.contains('service') ?? true) {
      mainSection['facts'].add({'name': 'Service', 'value': service});
    }

    if (message != null &&
        (template?.includeFields.contains('message') ?? true)) {
      mainSection['facts'].add({'name': 'Message', 'value': message});
    }

    if (template?.includeFields.contains('timestamp') ?? true) {
      mainSection['facts']
          .add({'name': 'Time', 'value': _formatTimestamp(timestamp)});
    }

    // Custom message
    if (template?.customMessage.isNotEmpty ?? false) {
      mainSection['text'] = template!.customMessage;
    }

    sections.add(mainSection);

    final teamsMessage = TeamsMessage(
      summary: '${_getSeverityEmoji(severity)} $severity: $host/$service',
      themeColor: template?.color ?? _getDefaultColor(severity),
      sections: sections,
    );

    return teamsMessage.toJson();
  }

  /// Get default title for severity
  String _getDefaultTitle(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return '🚨 CRITICAL ALERT';
      case 'WARNING':
        return '⚠️ WARNING ALERT';
      case 'RECOVERY':
        return '✅ SERVICE RECOVERED';
      case 'OK':
        return '✅ SERVICE OK';
      default:
        return '📢 ALERT NOTIFICATION';
    }
  }

  /// Get emoji for severity
  String _getSeverityEmoji(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return '🚨';
      case 'WARNING':
        return '⚠️';
      case 'RECOVERY':
      case 'OK':
        return '✅';
      default:
        return '📢';
    }
  }

  /// Get color for severity
  String _getSeverityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return 'Attention';
      case 'WARNING':
        return 'Warning';
      case 'RECOVERY':
      case 'OK':
        return 'Good';
      default:
        return 'Accent';
    }
  }

  /// Get default color for severity
  String _getDefaultColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return 'FF0000'; // Red
      case 'WARNING':
        return 'FFA500'; // Orange
      case 'RECOVERY':
      case 'OK':
        return '00FF00'; // Green
      default:
        return '0078D4'; // Blue
    }
  }

  /// Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    return timestamp.toLocal().toString().substring(0, 19);
  }

  /// Test webhook connectivity
  Future<bool> testWebhook(WebhookConfig webhook) async {
    try {
      final testPayload = _createSimpleMessagePayload(
        severity: 'INFO',
        host: 'test-host',
        service: 'configuration-test',
        message: 'Teams webhook configuration test - please ignore',
        template: null,
        timestamp: DateTime.now(),
      );

      return await _performWebhookRequest(webhook, testPayload);
    } catch (e) {
      _session.log('Webhook test failed for ${webhook.name}: $e',
          level: LogLevel.error);
      return false;
    }
  }

  /// Close HTTP client
  void close() {
    _httpClient.close();
  }
}

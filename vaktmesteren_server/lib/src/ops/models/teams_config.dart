/// Data models for Microsoft Teams notification configuration and messages
class TeamsConfig {
  final bool enabled;
  final bool logOnly;
  final int rateLimitPerMinute;
  final int cooldownMinutes;
  final Map<String, WebhookConfig> webhooks;
  final List<NotificationRule> notificationRules;
  final Map<String, MessageTemplate> messageTemplates;
  final AdvancedConfig advanced;

  const TeamsConfig({
    required this.enabled,
    this.logOnly = false,
    this.rateLimitPerMinute = 10,
    this.cooldownMinutes = 5,
    required this.webhooks,
    required this.notificationRules,
    required this.messageTemplates,
    required this.advanced,
  });

  factory TeamsConfig.fromMap(Map<String, dynamic> map) {
    // Handle webhooks
    final webhooksData = map['webhooks'];
    final webhooksMap = webhooksData != null
        ? Map<String, dynamic>.from(webhooksData as Map)
        : <String, dynamic>{};
    final webhooks = <String, WebhookConfig>{};

    for (final entry in webhooksMap.entries) {
      webhooks[entry.key] = WebhookConfig.fromMap(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    // Handle notification rules
    final rulesData = map['notificationRules'] as List<dynamic>? ?? [];
    final rules = rulesData
        .map((e) =>
            NotificationRule.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Handle message templates
    final templatesData = map['messageTemplates'];
    final templatesMap = templatesData != null
        ? Map<String, dynamic>.from(templatesData as Map)
        : <String, dynamic>{};
    final templates = <String, MessageTemplate>{};

    for (final entry in templatesMap.entries) {
      templates[entry.key] = MessageTemplate.fromMap(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    // Handle advanced config
    final advancedData = map['advanced'] as Map<String, dynamic>? ?? {};
    final advanced = AdvancedConfig.fromMap(advancedData);

    return TeamsConfig(
      enabled: map['enabled'] as bool? ?? true,
      logOnly: map['logOnly'] as bool? ?? false,
      rateLimitPerMinute: map['rateLimitPerMinute'] as int? ?? 10,
      cooldownMinutes: map['cooldownMinutes'] as int? ?? 5,
      webhooks: webhooks,
      notificationRules: rules,
      messageTemplates: templates,
      advanced: advanced,
    );
  }

  /// Find webhook configs that match notification rules for given alert
  List<WebhookConfig> findMatchingWebhooks(
      String severity, String host, String? service) {
    final matchingWebhooks = <WebhookConfig>[];

    for (final rule in notificationRules) {
      if (rule.matchesAlert(severity, host, service)) {
        for (final channelName in rule.channels) {
          final webhook = webhooks[channelName];
          if (webhook != null &&
              webhook.enabled &&
              webhook.matchesAlert(severity, host, service)) {
            matchingWebhooks.add(webhook);
          }
        }
      }
    }

    return matchingWebhooks;
  }

  @override
  String toString() =>
      'TeamsConfig(${webhooks.length} webhooks, ${notificationRules.length} rules, enabled=$enabled, logOnly=$logOnly)';
}

/// Configuration for a Teams webhook endpoint
class WebhookConfig {
  final String name;
  final String channelId;
  final String url;
  final bool enabled;
  final List<String> severityFilter;
  final List<String> hostFilter;
  final List<String> serviceFilter;

  const WebhookConfig({
    required this.name,
    required this.channelId,
    required this.url,
    this.enabled = true,
    this.severityFilter = const [],
    this.hostFilter = const [],
    this.serviceFilter = const [],
  });

  factory WebhookConfig.fromMap(String channelId, Map<String, dynamic> map) {
    return WebhookConfig(
      name: map['name'] as String? ?? channelId,
      channelId: channelId,
      url: map['url'] as String,
      enabled: map['enabled'] as bool? ?? true,
      severityFilter:
          (map['severityFilter'] as List<dynamic>?)?.cast<String>() ?? [],
      hostFilter: (map['hostFilter'] as List<dynamic>?)?.cast<String>() ?? [],
      serviceFilter:
          (map['serviceFilter'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// Check if this webhook should receive notifications for the given alert
  bool matchesAlert(String severity, String host, String? service) {
    // Check severity filter
    if (severityFilter.isNotEmpty && !severityFilter.contains(severity)) {
      return false;
    }

    // Check host filter
    if (hostFilter.isNotEmpty && !hostFilter.contains(host)) {
      return false;
    }

    // Check service filter
    if (serviceFilter.isNotEmpty &&
        service != null &&
        !serviceFilter.any((pattern) => service.contains(pattern))) {
      return false;
    }

    return true;
  }

  @override
  String toString() => 'WebhookConfig($name, enabled=$enabled)';
}

/// Rules for when to send notifications
class NotificationRule {
  final String name;
  final bool enabled;
  final List<String> severities;
  final List<String> channels;
  final List<String> servicePatterns;
  final List<String> hostPatterns;
  final bool triggerOnStateChange;
  final bool respectCooldown;
  final bool requiresPreviousAlert;

  const NotificationRule({
    required this.name,
    this.enabled = true,
    required this.severities,
    required this.channels,
    this.servicePatterns = const [],
    this.hostPatterns = const [],
    this.triggerOnStateChange = true,
    this.respectCooldown = true,
    this.requiresPreviousAlert = false,
  });

  factory NotificationRule.fromMap(Map<String, dynamic> map) {
    return NotificationRule(
      name: map['name'] as String,
      enabled: map['enabled'] as bool? ?? true,
      severities: (map['severities'] as List<dynamic>?)?.cast<String>() ?? [],
      channels: (map['channels'] as List<dynamic>?)?.cast<String>() ?? [],
      servicePatterns:
          (map['servicePatterns'] as List<dynamic>?)?.cast<String>() ?? [],
      hostPatterns:
          (map['hostPatterns'] as List<dynamic>?)?.cast<String>() ?? [],
      triggerOnStateChange: map['triggerOnStateChange'] as bool? ?? true,
      respectCooldown: map['respectCooldown'] as bool? ?? true,
      requiresPreviousAlert: map['requiresPreviousAlert'] as bool? ?? false,
    );
  }

  /// Check if this rule applies to the given alert
  bool matchesAlert(String severity, String host, String? service) {
    if (!enabled) return false;

    // Check severity
    if (!severities.contains(severity)) return false;

    // Check host patterns
    if (hostPatterns.isNotEmpty &&
        !hostPatterns.any((pattern) => host.contains(pattern))) {
      return false;
    }

    // Check service patterns
    if (servicePatterns.isNotEmpty &&
        service != null &&
        !servicePatterns.any((pattern) => service.contains(pattern))) {
      return false;
    }

    return true;
  }

  @override
  String toString() =>
      'NotificationRule($name, enabled=$enabled, ${severities.length} severities)';
}

/// Template for formatting Teams messages
class MessageTemplate {
  final String title;
  final String color;
  final List<String> includeFields;
  final String customMessage;

  const MessageTemplate({
    required this.title,
    required this.color,
    this.includeFields = const [],
    this.customMessage = '',
  });

  factory MessageTemplate.fromMap(Map<String, dynamic> map) {
    return MessageTemplate(
      title: map['title'] as String? ?? 'Alert Notification',
      color: map['color'] as String? ?? '0078D4',
      includeFields:
          (map['includeFields'] as List<dynamic>?)?.cast<String>() ?? [],
      customMessage: map['customMessage'] as String? ?? '',
    );
  }

  @override
  String toString() => 'MessageTemplate($title, color=$color)';
}

/// Advanced configuration settings
class AdvancedConfig {
  final int retryAttempts;
  final int retryDelaySeconds;
  final double retryBackoffMultiplier;
  final int webhookTimeoutSeconds;
  final bool useAdaptiveCards;
  final bool includePlatformInfo;
  final bool includeAlertHistory;
  final bool validateWebhookUrls;
  final bool logWebhookPayloads;

  const AdvancedConfig({
    this.retryAttempts = 3,
    this.retryDelaySeconds = 5,
    this.retryBackoffMultiplier = 2.0,
    this.webhookTimeoutSeconds = 30,
    this.useAdaptiveCards = true,
    this.includePlatformInfo = true,
    this.includeAlertHistory = false,
    this.validateWebhookUrls = true,
    this.logWebhookPayloads = false,
  });

  factory AdvancedConfig.fromMap(Map<String, dynamic> map) {
    return AdvancedConfig(
      retryAttempts: map['retryAttempts'] as int? ?? 3,
      retryDelaySeconds: map['retryDelaySeconds'] as int? ?? 5,
      retryBackoffMultiplier:
          (map['retryBackoffMultiplier'] as num?)?.toDouble() ?? 2.0,
      webhookTimeoutSeconds: map['webhookTimeoutSeconds'] as int? ?? 30,
      useAdaptiveCards: map['useAdaptiveCards'] as bool? ?? true,
      includePlatformInfo: map['includePlatformInfo'] as bool? ?? true,
      includeAlertHistory: map['includeAlertHistory'] as bool? ?? false,
      validateWebhookUrls: map['validateWebhookUrls'] as bool? ?? true,
      logWebhookPayloads: map['logWebhookPayloads'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'AdvancedConfig(retries=$retryAttempts, timeout=${webhookTimeoutSeconds}s)';
}

/// Teams message payload structure
class TeamsMessage {
  final String type;
  final String summary;
  final String themeColor;
  final List<Map<String, dynamic>> sections;

  const TeamsMessage({
    this.type = 'MessageCard',
    required this.summary,
    required this.themeColor,
    required this.sections,
  });

  Map<String, dynamic> toJson() {
    return {
      '@type': type,
      '@context': 'https://schema.org/extensions',
      'summary': summary,
      'themeColor': themeColor,
      'sections': sections,
    };
  }
}

/// Adaptive card structure for rich Teams messages
class AdaptiveCard {
  final String type;
  final String version;
  final List<Map<String, dynamic>> body;
  final List<Map<String, dynamic>>? actions;

  const AdaptiveCard({
    this.type = 'AdaptiveCard',
    this.version = '1.4',
    required this.body,
    this.actions,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'type': type,
      '\$schema': 'http://adaptivecards.io/schemas/adaptive-card.json',
      'version': version,
      'body': body,
    };

    if (actions != null && actions!.isNotEmpty) {
      json['actions'] = actions!;
    }

    return json;
  }
}

/// Rate limiting tracker for Teams notifications
class RateLimitTracker {
  final Map<String, List<DateTime>> _channelHistory = {};
  final Map<String, DateTime> _alertCooldowns = {};

  /// Check if sending to a channel is within rate limits
  bool canSendToChannel(String channelId, int rateLimitPerMinute) {
    final now = DateTime.now();
    final history = _channelHistory[channelId] ?? [];

    // Remove entries older than 1 minute
    history
        .removeWhere((timestamp) => now.difference(timestamp).inMinutes >= 1);

    // Check if we're under the rate limit
    return history.length < rateLimitPerMinute;
  }

  /// Record a message sent to a channel
  void recordMessageSent(String channelId) {
    final now = DateTime.now();
    _channelHistory.putIfAbsent(channelId, () => []).add(now);
  }

  /// Check if an alert is in cooldown period
  bool isInCooldown(String alertKey, int cooldownMinutes) {
    final lastSent = _alertCooldowns[alertKey];
    if (lastSent == null) return false;

    final now = DateTime.now();
    return now.difference(lastSent).inMinutes < cooldownMinutes;
  }

  /// Record an alert notification sent
  void recordAlertSent(String alertKey) {
    _alertCooldowns[alertKey] = DateTime.now();
  }

  /// Get alert key for cooldown tracking
  static String getAlertKey(String host, String? service) {
    return service != null ? '$host:$service' : host;
  }
}

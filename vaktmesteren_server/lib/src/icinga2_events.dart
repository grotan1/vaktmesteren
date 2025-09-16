/// Base class for all Icinga2 events
abstract class Icinga2Event {
  final String type;
  final String host;
  final String? service;

  Icinga2Event({
    required this.type,
    required this.host,
    this.service,
  });

  /// Factory method to create the appropriate event type from JSON
  static Icinga2Event fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;

    switch (type) {
      case 'CheckResult':
        return CheckResultEvent.fromJson(json);
      case 'StateChange':
        return StateChangeEvent.fromJson(json);
      case 'Notification':
        return NotificationEvent.fromJson(json);
      case 'AcknowledgementSet':
        return AcknowledgementSetEvent.fromJson(json);
      case 'AcknowledgementCleared':
        return AcknowledgementClearedEvent.fromJson(json);
      case 'CommentAdded':
        return CommentAddedEvent.fromJson(json);
      case 'CommentRemoved':
        return CommentRemovedEvent.fromJson(json);
      case 'DowntimeAdded':
        return DowntimeAddedEvent.fromJson(json);
      case 'DowntimeRemoved':
        return DowntimeRemovedEvent.fromJson(json);
      case 'DowntimeStarted':
        return DowntimeStartedEvent.fromJson(json);
      case 'DowntimeTriggered':
        return DowntimeTriggeredEvent.fromJson(json);
      case 'ObjectCreated':
        return ObjectCreatedEvent.fromJson(json);
      case 'ObjectModified':
        return ObjectModifiedEvent.fromJson(json);
      case 'ObjectDeleted':
        return ObjectDeletedEvent.fromJson(json);
      default:
        return UnknownEvent.fromJson(json);
    }
  }
}

/// CheckResult event
class CheckResultEvent extends Icinga2Event {
  final Map<String, dynamic> checkResult;
  final int downtimeDepth;
  final bool acknowledgement;

  CheckResultEvent({
    required super.host,
    super.service,
    required this.checkResult,
    required this.downtimeDepth,
    required this.acknowledgement,
  }) : super(type: 'CheckResult');

  factory CheckResultEvent.fromJson(Map<String, dynamic> json) {
    return CheckResultEvent(
      host: json['host'] as String,
      service: json['service'] as String?,
      checkResult: json['check_result'] as Map<String, dynamic>,
      downtimeDepth: (json['downtime_depth'] as num?)?.toInt() ?? 0,
      acknowledgement: json['acknowledgement'] as bool? ?? false,
    );
  }
}

/// StateChange event
class StateChangeEvent extends Icinga2Event {
  final int state;
  final int stateType;
  final Map<String, dynamic> checkResult;
  final int downtimeDepth;
  final bool acknowledgement;

  StateChangeEvent({
    required super.host,
    super.service,
    required this.state,
    required this.stateType,
    required this.checkResult,
    required this.downtimeDepth,
    required this.acknowledgement,
  }) : super(type: 'StateChange');

  factory StateChangeEvent.fromJson(Map<String, dynamic> json) {
    return StateChangeEvent(
      host: json['host'] as String,
      service: json['service'] as String?,
      state: (json['state'] as num).toInt(),
      stateType: (json['state_type'] as num).toInt(),
      checkResult: json['check_result'] as Map<String, dynamic>,
      downtimeDepth: (json['downtime_depth'] as num?)?.toInt() ?? 0,
      acknowledgement: json['acknowledgement'] as bool? ?? false,
    );
  }
}

/// Notification event
class NotificationEvent extends Icinga2Event {
  final String command;
  final List<String> users;
  final String notificationType;
  final String? author;
  final String? text;
  final Map<String, dynamic> checkResult;

  NotificationEvent({
    required super.host,
    super.service,
    required this.command,
    required this.users,
    required this.notificationType,
    this.author,
    this.text,
    required this.checkResult,
  }) : super(type: 'Notification');

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    return NotificationEvent(
      host: json['host'] as String,
      service: json['service'] as String?,
      command: json['command'] as String,
      users: List<String>.from(json['users'] ?? []),
      notificationType: json['notification_type'] as String,
      author: json['author'] as String?,
      text: json['text'] as String?,
      checkResult: json['check_result'] as Map<String, dynamic>,
    );
  }
}

/// AcknowledgementSet event
class AcknowledgementSetEvent extends Icinga2Event {
  final int state;
  final int stateType;
  final String author;
  final String comment;
  final int acknowledgementType;
  final bool notify;
  final num? expiry;

  AcknowledgementSetEvent({
    required super.host,
    super.service,
    required this.state,
    required this.stateType,
    required this.author,
    required this.comment,
    required this.acknowledgementType,
    required this.notify,
    this.expiry,
  }) : super(type: 'AcknowledgementSet');

  factory AcknowledgementSetEvent.fromJson(Map<String, dynamic> json) {
    return AcknowledgementSetEvent(
      host: json['host'] as String,
      service: json['service'] as String?,
      state: (json['state'] as num).toInt(),
      stateType: (json['state_type'] as num).toInt(),
      author: json['author'] as String,
      comment: json['comment'] as String,
      acknowledgementType: (json['acknowledgement_type'] as num).toInt(),
      notify: json['notify'] as bool? ?? false,
      expiry: json['expiry'] as num?,
    );
  }
}

/// AcknowledgementCleared event
class AcknowledgementClearedEvent extends Icinga2Event {
  final int state;
  final int stateType;

  AcknowledgementClearedEvent({
    required super.host,
    super.service,
    required this.state,
    required this.stateType,
  }) : super(type: 'AcknowledgementCleared');

  factory AcknowledgementClearedEvent.fromJson(Map<String, dynamic> json) {
    return AcknowledgementClearedEvent(
      host: json['host'] as String,
      service: json['service'] as String?,
      state: (json['state'] as num).toInt(),
      stateType: (json['state_type'] as num).toInt(),
    );
  }
}

/// CommentAdded event
class CommentAddedEvent extends Icinga2Event {
  final Map<String, dynamic> comment;

  CommentAddedEvent({
    required this.comment,
  }) : super(type: 'CommentAdded', host: '', service: null);

  factory CommentAddedEvent.fromJson(Map<String, dynamic> json) {
    return CommentAddedEvent(
      comment: json['comment'] as Map<String, dynamic>,
    );
  }
}

/// CommentRemoved event
class CommentRemovedEvent extends Icinga2Event {
  final Map<String, dynamic> comment;

  CommentRemovedEvent({
    required this.comment,
  }) : super(type: 'CommentRemoved', host: '', service: null);

  factory CommentRemovedEvent.fromJson(Map<String, dynamic> json) {
    return CommentRemovedEvent(
      comment: json['comment'] as Map<String, dynamic>,
    );
  }
}

/// DowntimeAdded event
class DowntimeAddedEvent extends Icinga2Event {
  final Map<String, dynamic> downtime;

  DowntimeAddedEvent({
    required this.downtime,
  }) : super(type: 'DowntimeAdded', host: '', service: null);

  factory DowntimeAddedEvent.fromJson(Map<String, dynamic> json) {
    return DowntimeAddedEvent(
      downtime: json['downtime'] as Map<String, dynamic>,
    );
  }
}

/// DowntimeRemoved event
class DowntimeRemovedEvent extends Icinga2Event {
  final Map<String, dynamic> downtime;

  DowntimeRemovedEvent({
    required this.downtime,
  }) : super(type: 'DowntimeRemoved', host: '', service: null);

  factory DowntimeRemovedEvent.fromJson(Map<String, dynamic> json) {
    return DowntimeRemovedEvent(
      downtime: json['downtime'] as Map<String, dynamic>,
    );
  }
}

/// DowntimeStarted event
class DowntimeStartedEvent extends Icinga2Event {
  final Map<String, dynamic> downtime;

  DowntimeStartedEvent({
    required this.downtime,
  }) : super(type: 'DowntimeStarted', host: '', service: null);

  factory DowntimeStartedEvent.fromJson(Map<String, dynamic> json) {
    return DowntimeStartedEvent(
      downtime: json['downtime'] as Map<String, dynamic>,
    );
  }
}

/// DowntimeTriggered event
class DowntimeTriggeredEvent extends Icinga2Event {
  final Map<String, dynamic> downtime;

  DowntimeTriggeredEvent({
    required this.downtime,
  }) : super(type: 'DowntimeTriggered', host: '', service: null);

  factory DowntimeTriggeredEvent.fromJson(Map<String, dynamic> json) {
    return DowntimeTriggeredEvent(
      downtime: json['downtime'] as Map<String, dynamic>,
    );
  }
}

/// ObjectCreated event
class ObjectCreatedEvent extends Icinga2Event {
  final String objectType;
  final String objectName;

  ObjectCreatedEvent({
    required this.objectType,
    required this.objectName,
  }) : super(type: 'ObjectCreated', host: '', service: null);

  factory ObjectCreatedEvent.fromJson(Map<String, dynamic> json) {
    return ObjectCreatedEvent(
      objectType: json['object_type'] as String,
      objectName: json['object_name'] as String,
    );
  }
}

/// ObjectModified event
class ObjectModifiedEvent extends Icinga2Event {
  final String objectType;
  final String objectName;

  ObjectModifiedEvent({
    required this.objectType,
    required this.objectName,
  }) : super(type: 'ObjectModified', host: '', service: null);

  factory ObjectModifiedEvent.fromJson(Map<String, dynamic> json) {
    return ObjectModifiedEvent(
      objectType: json['object_type'] as String,
      objectName: json['object_name'] as String,
    );
  }
}

/// ObjectDeleted event
class ObjectDeletedEvent extends Icinga2Event {
  final String objectType;
  final String objectName;

  ObjectDeletedEvent({
    required this.objectType,
    required this.objectName,
  }) : super(type: 'ObjectDeleted', host: '', service: null);

  factory ObjectDeletedEvent.fromJson(Map<String, dynamic> json) {
    return ObjectDeletedEvent(
      objectType: json['object_type'] as String,
      objectName: json['object_name'] as String,
    );
  }
}

/// Unknown event type (fallback)
class UnknownEvent extends Icinga2Event {
  final Map<String, dynamic> rawData;

  UnknownEvent({
    required super.type,
    required this.rawData,
  }) : super(host: '', service: null);

  factory UnknownEvent.fromJson(Map<String, dynamic> json) {
    return UnknownEvent(
      type: json['type'] as String,
      rawData: json,
    );
  }
}

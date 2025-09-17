part of '../icinga2_event_listener.dart';

// Handlers moved here for readability. They retain access to private members
// through library privacy and receive the listener instance as `s`.

Future<void> handleCheckResult(
  Icinga2EventListener s,
  CheckResultEvent event,
) async {
  final rawState = event.checkResult['state'];
  final exitCode = event.checkResult['exit_code'] ?? -1;
  final output = event.checkResult['output'] ?? '';

  int stateCode;
  if (rawState is num) {
    stateCode = rawState.toInt();
  } else if (rawState is String) {
    switch (rawState.toUpperCase()) {
      case 'OK':
        stateCode = 0;
        break;
      case 'WARNING':
        stateCode = 1;
        break;
      case 'CRITICAL':
        stateCode = 2;
        break;
      case 'UNKNOWN':
      default:
        stateCode = 3;
    }
  } else {
    stateCode = (exitCode >= 0)
        ? (exitCode == 2 ? 2 : (exitCode == 1 ? 1 : (exitCode == 0 ? 0 : 3)))
        : 3;
  }

  final stateType = event.checkResult['state_type'] ?? (exitCode == 2 ? 1 : 0);
  final isHardState = stateType == 1;
  final isInDowntime = (event.checkResult['downtime_depth'] ?? 0) > 0;
  final isAcknowledged = event.checkResult['acknowledgement'] ?? false;
  final shouldAlert = isHardState && !isInDowntime && !isAcknowledged;
  final canonical = s._canonicalKey(event.host, event.service);

  s.session.log(
      'CheckResult decision for $canonical: stateCode=$stateCode exitCode=$exitCode isHard=$isHardState shouldAlert=$shouldAlert',
      level: LogLevel.debug);

  var didBroadcast = false;

  if (stateCode == 2 && shouldAlert) {
    s.session.log(
        '🚨 ALERT CRITICAL: ${s._hostServiceLabel(event.host, event.service)} - $output',
        level: LogLevel.error);
    if (!s._shouldBroadcastForHost(event.host)) {
      s.session.log('Skipping broadcast for $canonical: host filter mismatch',
          level: LogLevel.debug);
    } else if (s._shouldBroadcastForKey(canonical, 2)) {
      LogBroadcaster.broadcastLog(
          '🚨 ALERT CRITICAL: ${s._hostServiceLabel(event.host, event.service)} - $output');
      didBroadcast = true;
    }
  } else if (stateCode == 1 && shouldAlert) {
    s.session.log(
        '⚠️ ALERT WARNING: ${s._hostServiceLabel(event.host, event.service)} - $output',
        level: LogLevel.warning);
    if (!s._shouldBroadcastForHost(event.host)) {
      s.session.log('Skipping broadcast for $canonical: host filter mismatch',
          level: LogLevel.debug);
    } else if (s._shouldBroadcastForKey(canonical, 1)) {
      LogBroadcaster.broadcastLog(
          '⚠️ ALERT WARNING: ${s._hostServiceLabel(event.host, event.service)} - $output');
      didBroadcast = true;
    }
  } else if (stateCode == 0) {
    s.session.log(
        '✅ ALERT RECOVERY: ${s._hostServiceLabel(event.host, event.service)}',
        level: LogLevel.info);
    if (!s._shouldBroadcastForHost(event.host)) {
      s.session.log('Skipping broadcast for $canonical: host filter mismatch',
          level: LogLevel.debug);
    } else if (s._shouldBroadcastForKey(canonical, 0) ||
        s._shouldBroadcastRecovery(canonical)) {
      LogBroadcaster.broadcastLog(
          '✅ ALERT RECOVERY: ${s._hostServiceLabel(event.host, event.service)}');
      didBroadcast = true;
    }
    try {
      s._lastBroadcastState[canonical] = 0;
      s.session.log('Recorded recovery state for $canonical -> 0',
          level: LogLevel.debug);
    } catch (_) {}
  } else if (isInDowntime || isAcknowledged) {
    final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
    s.session.log(
        'ALERT SUPPRESSED ($reason): ${s._hostServiceLabel(event.host, event.service)} - $output',
        level: LogLevel.info);
  } else if (stateCode == 2 && !isHardState) {
    s.session.log(
        'SOFT CRITICAL: ${s._hostServiceLabel(event.host, event.service)} - $output',
        level: LogLevel.warning);
  } else if (stateCode == 1 && !isHardState) {
    s.session.log(
        'SOFT WARNING: ${s._hostServiceLabel(event.host, event.service)} - $output',
        level: LogLevel.info);
  } else {
    s.session.log(
        'UNKNOWN: ${s._hostServiceLabel(event.host, event.service)} - $output',
        level: LogLevel.warning);
  }

  try {
    await s._persistState(canonical, event.host, event.service, stateCode);
    if (didBroadcast) {
      unawaited(s._persistHistory(canonical, event.host, event.service,
          stateCode, output == '' ? null : output));
    }
  } catch (e) {
    s.session.log('Failed to persist state/history for $canonical: $e',
        level: LogLevel.error);
  }
}

Future<void> handleStateChange(
  Icinga2EventListener s,
  StateChangeEvent event,
) async {
  final stateNames = {
    0: 'OK',
    1: 'WARNING',
    2: 'CRITICAL',
    3: 'UNKNOWN',
    99: 'PENDING'
  };
  final stateTypeNames = {0: 'SOFT', 1: 'HARD'};
  final stateName = stateNames[event.state] ?? 'UNKNOWN';
  final stateTypeName = stateTypeNames[event.stateType] ?? 'UNKNOWN';
  final isHardState = event.stateType == 1;
  final isInDowntime = event.downtimeDepth > 0;
  final isAcknowledged = event.acknowledgement;
  final shouldAlert = isHardState && !isInDowntime && !isAcknowledged;
  final canonical = s._canonicalKey(event.host, event.service);

  s.session.log(
      'StateChange decision for $canonical: state=${event.state} type=${event.stateType} isHard=$isHardState shouldAlert=$shouldAlert',
      level: LogLevel.debug);
  var didBroadcast = false;

  if (event.state == 2 && shouldAlert) {
    final logMessage =
        '🚨 ALERT CRITICAL: ${s._hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)';
    s.session.log(logMessage, level: LogLevel.error);
    if (!s._shouldBroadcastForHost(event.host)) {
      s.session.log('Skipping broadcast for $canonical: host filter mismatch',
          level: LogLevel.debug);
    } else if (s._shouldBroadcastForKey(canonical, event.state)) {
      LogBroadcaster.broadcastLog(logMessage);
      didBroadcast = true;
    }
  } else if (event.state == 1 && shouldAlert) {
    final logMessage =
        '⚠️ ALERT WARNING: ${s._hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)';
    s.session.log(logMessage, level: LogLevel.warning);
    if (!s._shouldBroadcastForHost(event.host)) {
      s.session.log('Skipping broadcast for $canonical: host filter mismatch',
          level: LogLevel.debug);
    } else if (s._shouldBroadcastForKey(canonical, event.state)) {
      LogBroadcaster.broadcastLog(logMessage);
      didBroadcast = true;
    }
  } else if (event.state == 0) {
    final logMessage =
        '✅ ALERT RECOVERY: ${s._hostServiceLabel(event.host, event.service)} recovered to $stateName ($stateTypeName)';
    s.session.log(logMessage, level: LogLevel.info);
    if (!s._shouldBroadcastForHost(event.host)) {
      s.session.log('Skipping broadcast for $canonical: host filter mismatch',
          level: LogLevel.debug);
    } else if (s._shouldBroadcastForKey(canonical, event.state) ||
        s._shouldBroadcastRecovery(canonical)) {
      LogBroadcaster.broadcastLog(logMessage);
      didBroadcast = true;
    }
  } else if (isInDowntime || isAcknowledged) {
    final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
    final logMessage =
        '🔕 ALERT SUPPRESSED ($reason): ${s._hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)';
    s.session.log(logMessage, level: LogLevel.info);
    // Broadcast suppressed info for visibility, but DO NOT update last-broadcast state,
    // otherwise a later real alert after downtime would be skipped as duplicate.
    if (s._shouldBroadcastForHost(event.host) &&
        !s._shouldThrottleSuppressed(canonical)) {
      LogBroadcaster.broadcastLog(logMessage);
      // Only track last broadcast time for throttling; do not set state.
      s._lastBroadcastAt[canonical] = DateTime.now();
    }

    // If a problem is currently suppressed due to downtime/ack, schedule a re-check shortly.
    // This helps when operators delete a downtime and the end-event isn't received or is delayed.
    if (event.state > 0 && event.service != null) {
      final h = event.host;
      final svc = event.service!;
      // re-check a bit later to catch cleared downtime_depth
      Timer(const Duration(seconds: 5), () {
        unawaited(s._checkAndTriggerAfterDowntime(h, svc));
      });
      Timer(const Duration(seconds: 12), () {
        unawaited(s._checkAndTriggerAfterDowntime(h, svc));
      });
    }
  } else {
    s.session.log(
        'STATE CHANGE (Soft): ${s._hostServiceLabel(event.host, event.service)} changed to $stateName ($stateTypeName)',
        level: LogLevel.info);
  }

  try {
    await s._persistState(canonical, event.host, event.service, event.state);
    if (didBroadcast) {
      unawaited(s._persistHistory(
          canonical, event.host, event.service, event.state, null));
    }
  } catch (e) {
    s.session.log('Failed to persist state/history for $canonical: $e',
        level: LogLevel.error);
  }
}

void handleNotification(Icinga2EventListener s, NotificationEvent event) {
  final notificationType = event.notificationType;
  final users = event.users.join(', ');
  final command = event.command;
  final stateType = event.checkResult['state_type'] ?? 1;
  final isHardState = stateType == 1;
  final isInDowntime = (event.checkResult['downtime_depth'] ?? 0) > 0;
  final isAcknowledged = event.checkResult['acknowledgement'] ?? false;
  final shouldAlert = isHardState && !isInDowntime && !isAcknowledged;

  s.session.log(
      'NOTIFICATION: $notificationType sent to $users via $command for ${s._hostServiceLabel(event.host, event.service)} (State: ${isHardState ? 'HARD' : 'SOFT'})',
      level: LogLevel.info);

  if (shouldAlert &&
      (notificationType.contains('PROBLEM') ||
          notificationType.contains('CRITICAL'))) {
    s.session.log(
        '🚨 PROBLEM NOTIFICATION: Immediate attention required for ${s._hostServiceLabel(event.host, event.service)}',
        level: LogLevel.warning);
    s.session.log(
        'PROBLEM NOTIFICATION: ${s._hostServiceLabel(event.host, event.service)} needs immediate attention!',
        level: LogLevel.warning);
  } else if (shouldAlert &&
      (notificationType.contains('RECOVERY') ||
          notificationType.contains('OK'))) {
    s.session.log(
        '✅ RECOVERY NOTIFICATION: ${s._hostServiceLabel(event.host, event.service)} has recovered',
        level: LogLevel.info);
    s.session.log(
        'RECOVERY NOTIFICATION: ${s._hostServiceLabel(event.host, event.service)} is back OK',
        level: LogLevel.info);
  } else if (isInDowntime || isAcknowledged) {
    final reason = isInDowntime ? 'DOWNTIME' : 'ACKNOWLEDGED';
    s.session.log(
        'NOTIFICATION SUPPRESSED ($reason): $notificationType for ${s._hostServiceLabel(event.host, event.service)}',
        level: LogLevel.info);
    s.session.log(
        'NOTIFICATION SUPPRESSED ($reason): ${s._hostServiceLabel(event.host, event.service)} - $notificationType',
        level: LogLevel.info);
  } else if (!isHardState) {
    s.session.log(
        'SOFT STATE NOTIFICATION: ${s._hostServiceLabel(event.host, event.service)} - $notificationType (not escalating)',
        level: LogLevel.info);
  }
}

void handleAcknowledgementSet(
    Icinga2EventListener s, AcknowledgementSetEvent event) {
  final author = event.author;
  final comment = event.comment;
  s.session.log(
      'ACKNOWLEDGEMENT SET: ${s._hostServiceLabel(event.host, event.service)} acknowledged by $author: $comment',
      level: LogLevel.info);
}

void handleAcknowledgementCleared(
    Icinga2EventListener s, AcknowledgementClearedEvent event) {
  s.session.log(
      'ACKNOWLEDGEMENT CLEARED: ${s._hostServiceLabel(event.host, event.service)} acknowledgement removed',
      level: LogLevel.info);
}

void handleCommentAdded(Icinga2EventListener s, CommentAddedEvent event) {
  s.session
      .log('Processing comment added: ${event.comment}', level: LogLevel.debug);
}

void handleCommentRemoved(Icinga2EventListener s, CommentRemovedEvent event) {
  s.session.log('Processing comment removed: ${event.comment}',
      level: LogLevel.debug);
}

void handleDowntimeAdded(Icinga2EventListener s, DowntimeAddedEvent event) {
  s.session.log('Processing downtime added: ${event.downtime}',
      level: LogLevel.debug);
}

void handleDowntimeRemoved(Icinga2EventListener s, DowntimeRemovedEvent event) {
  s.session.log('Processing downtime removed: ${event.downtime}',
      level: LogLevel.debug);
  // When downtime ends, if the service/host is still non-OK, we should trigger an alert now.
  unawaited(s._handleDowntimeEnded(event.downtime));
}

void handleDowntimeStarted(Icinga2EventListener s, DowntimeStartedEvent event) {
  s.session.log('Processing downtime started: ${event.downtime}',
      level: LogLevel.debug);
}

void handleDowntimeTriggered(
    Icinga2EventListener s, DowntimeTriggeredEvent event) {
  s.session.log('Processing downtime triggered: ${event.downtime}',
      level: LogLevel.debug);
  // Some environments emit DowntimeTriggered when an active downtime entry is removed/expired.
  // Run the same post-downtime check to be safe.
  unawaited(s._handleDowntimeEnded(event.downtime));
}

void handleObjectCreated(Icinga2EventListener s, ObjectCreatedEvent event) {
  s.session.log(
      'Processing object created: ${event.objectType} ${event.objectName}',
      level: LogLevel.debug);
}

void handleObjectModified(Icinga2EventListener s, ObjectModifiedEvent event) {
  s.session.log(
      'Processing object modified: ${event.objectType} ${event.objectName}',
      level: LogLevel.debug);
}

void handleObjectDeleted(Icinga2EventListener s, ObjectDeletedEvent event) {
  s.session.log(
      'Processing object deleted: ${event.objectType} ${event.objectName}',
      level: LogLevel.debug);
}

void handleUnknownEvent(Icinga2EventListener s, UnknownEvent event) {
  s.session.log('Processing unknown event type: ${event.type}',
      level: LogLevel.debug);
  s.session.log('Raw data: ${event.rawData}', level: LogLevel.debug);
}

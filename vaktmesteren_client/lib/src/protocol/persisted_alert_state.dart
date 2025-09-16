/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod_client/serverpod_client.dart' as _i1;

abstract class PersistedAlertState implements _i1.SerializableModel {
  PersistedAlertState._({
    this.id,
    required this.host,
    this.service,
    required this.canonicalKey,
    required this.lastState,
    required this.lastUpdated,
  });

  factory PersistedAlertState({
    int? id,
    required String host,
    String? service,
    required String canonicalKey,
    required int lastState,
    required DateTime lastUpdated,
  }) = _PersistedAlertStateImpl;

  factory PersistedAlertState.fromJson(Map<String, dynamic> jsonSerialization) {
    return PersistedAlertState(
      id: jsonSerialization['id'] as int?,
      host: jsonSerialization['host'] as String,
      service: jsonSerialization['service'] as String?,
      canonicalKey: jsonSerialization['canonicalKey'] as String,
      lastState: jsonSerialization['lastState'] as int,
      lastUpdated:
          _i1.DateTimeJsonExtension.fromJson(jsonSerialization['lastUpdated']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String host;

  String? service;

  String canonicalKey;

  int lastState;

  DateTime lastUpdated;

  /// Returns a shallow copy of this [PersistedAlertState]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  PersistedAlertState copyWith({
    int? id,
    String? host,
    String? service,
    String? canonicalKey,
    int? lastState,
    DateTime? lastUpdated,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'host': host,
      if (service != null) 'service': service,
      'canonicalKey': canonicalKey,
      'lastState': lastState,
      'lastUpdated': lastUpdated.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PersistedAlertStateImpl extends PersistedAlertState {
  _PersistedAlertStateImpl({
    int? id,
    required String host,
    String? service,
    required String canonicalKey,
    required int lastState,
    required DateTime lastUpdated,
  }) : super._(
          id: id,
          host: host,
          service: service,
          canonicalKey: canonicalKey,
          lastState: lastState,
          lastUpdated: lastUpdated,
        );

  /// Returns a shallow copy of this [PersistedAlertState]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  PersistedAlertState copyWith({
    Object? id = _Undefined,
    String? host,
    Object? service = _Undefined,
    String? canonicalKey,
    int? lastState,
    DateTime? lastUpdated,
  }) {
    return PersistedAlertState(
      id: id is int? ? id : this.id,
      host: host ?? this.host,
      service: service is String? ? service : this.service,
      canonicalKey: canonicalKey ?? this.canonicalKey,
      lastState: lastState ?? this.lastState,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

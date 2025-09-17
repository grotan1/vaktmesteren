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

abstract class AlertHistory implements _i1.SerializableModel {
  AlertHistory._({
    this.id,
    required this.host,
    this.service,
    required this.canonicalKey,
    required this.state,
    this.message,
    required this.createdAt,
  });

  factory AlertHistory({
    int? id,
    required String host,
    String? service,
    required String canonicalKey,
    required int state,
    String? message,
    required DateTime createdAt,
  }) = _AlertHistoryImpl;

  factory AlertHistory.fromJson(Map<String, dynamic> jsonSerialization) {
    return AlertHistory(
      id: jsonSerialization['id'] as int?,
      host: jsonSerialization['host'] as String,
      service: jsonSerialization['service'] as String?,
      canonicalKey: jsonSerialization['canonicalKey'] as String,
      state: jsonSerialization['state'] as int,
      message: jsonSerialization['message'] as String?,
      createdAt:
          _i1.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String host;

  String? service;

  String canonicalKey;

  int state;

  String? message;

  DateTime createdAt;

  /// Returns a shallow copy of this [AlertHistory]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  AlertHistory copyWith({
    int? id,
    String? host,
    String? service,
    String? canonicalKey,
    int? state,
    String? message,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'host': host,
      if (service != null) 'service': service,
      'canonicalKey': canonicalKey,
      'state': state,
      if (message != null) 'message': message,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AlertHistoryImpl extends AlertHistory {
  _AlertHistoryImpl({
    int? id,
    required String host,
    String? service,
    required String canonicalKey,
    required int state,
    String? message,
    required DateTime createdAt,
  }) : super._(
          id: id,
          host: host,
          service: service,
          canonicalKey: canonicalKey,
          state: state,
          message: message,
          createdAt: createdAt,
        );

  /// Returns a shallow copy of this [AlertHistory]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  AlertHistory copyWith({
    Object? id = _Undefined,
    String? host,
    Object? service = _Undefined,
    String? canonicalKey,
    int? state,
    Object? message = _Undefined,
    DateTime? createdAt,
  }) {
    return AlertHistory(
      id: id is int? ? id : this.id,
      host: host ?? this.host,
      service: service is String? ? service : this.service,
      canonicalKey: canonicalKey ?? this.canonicalKey,
      state: state ?? this.state,
      message: message is String? ? message : this.message,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

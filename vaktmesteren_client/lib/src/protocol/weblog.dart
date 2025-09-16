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

abstract class WebLog implements _i1.SerializableModel {
  WebLog._({
    this.id,
    required this.createdAt,
    required this.message,
    required this.transient,
  });

  factory WebLog({
    int? id,
    required DateTime createdAt,
    required String message,
    required bool transient,
  }) = _WebLogImpl;

  factory WebLog.fromJson(Map<String, dynamic> jsonSerialization) {
    return WebLog(
      id: jsonSerialization['id'] as int?,
      createdAt:
          _i1.DateTimeJsonExtension.fromJson(jsonSerialization['createdAt']),
      message: jsonSerialization['message'] as String,
      transient: jsonSerialization['transient'] as bool,
    );
  }

  int? id;

  DateTime createdAt;

  String message;

  bool transient;

  /// Returns a shallow copy of this [WebLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  WebLog copyWith({
    int? id,
    DateTime? createdAt,
    String? message,
    bool? transient,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'createdAt': createdAt.toJson(),
      'message': message,
      'transient': transient,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _WebLogImpl extends WebLog {
  _WebLogImpl({
    int? id,
    required DateTime createdAt,
    required String message,
    required bool transient,
  }) : super._(
          id: id,
          createdAt: createdAt,
          message: message,
          transient: transient,
        );

  /// Returns a shallow copy of this [WebLog]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  WebLog copyWith({
    Object? id = _Undefined,
    DateTime? createdAt,
    String? message,
    bool? transient,
  }) {
    return WebLog(
      id: id is int? ? id : this.id,
      createdAt: createdAt ?? this.createdAt,
      message: message ?? this.message,
      transient: transient ?? this.transient,
    );
  }
}

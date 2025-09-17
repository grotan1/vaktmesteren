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
import 'alert_history.dart' as _i2;
import 'persisted_alert_state.dart' as _i3;
import 'weblog.dart' as _i4;
export 'alert_history.dart';
export 'persisted_alert_state.dart';
export 'weblog.dart';
export 'client.dart';

class Protocol extends _i1.SerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;
    if (t == _i2.AlertHistory) {
      return _i2.AlertHistory.fromJson(data) as T;
    }
    if (t == _i3.PersistedAlertState) {
      return _i3.PersistedAlertState.fromJson(data) as T;
    }
    if (t == _i4.WebLog) {
      return _i4.WebLog.fromJson(data) as T;
    }
    if (t == _i1.getType<_i2.AlertHistory?>()) {
      return (data != null ? _i2.AlertHistory.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i3.PersistedAlertState?>()) {
      return (data != null ? _i3.PersistedAlertState.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i4.WebLog?>()) {
      return (data != null ? _i4.WebLog.fromJson(data) : null) as T;
    }
    if (t == Map<String, dynamic>) {
      return (data as Map).map((k, v) =>
          MapEntry(deserialize<String>(k), deserialize<dynamic>(v))) as T;
    }
    return super.deserialize<T>(data, t);
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;
    if (data is _i2.AlertHistory) {
      return 'AlertHistory';
    }
    if (data is _i3.PersistedAlertState) {
      return 'PersistedAlertState';
    }
    if (data is _i4.WebLog) {
      return 'WebLog';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'AlertHistory') {
      return deserialize<_i2.AlertHistory>(data['data']);
    }
    if (dataClassName == 'PersistedAlertState') {
      return deserialize<_i3.PersistedAlertState>(data['data']);
    }
    if (dataClassName == 'WebLog') {
      return deserialize<_i4.WebLog>(data['data']);
    }
    return super.deserializeByClassName(data);
  }
}

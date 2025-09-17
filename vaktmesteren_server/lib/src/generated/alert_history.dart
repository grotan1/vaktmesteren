/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _i1;

abstract class AlertHistory
    implements _i1.TableRow<int?>, _i1.ProtocolSerialization {
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

  static final t = AlertHistoryTable();

  static const db = AlertHistoryRepository._();

  @override
  int? id;

  String host;

  String? service;

  String canonicalKey;

  int state;

  String? message;

  DateTime createdAt;

  @override
  _i1.Table<int?> get table => t;

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
  Map<String, dynamic> toJsonForProtocol() {
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

  static AlertHistoryInclude include() {
    return AlertHistoryInclude._();
  }

  static AlertHistoryIncludeList includeList({
    _i1.WhereExpressionBuilder<AlertHistoryTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertHistoryTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertHistoryTable>? orderByList,
    AlertHistoryInclude? include,
  }) {
    return AlertHistoryIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AlertHistory.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(AlertHistory.t),
      include: include,
    );
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

class AlertHistoryTable extends _i1.Table<int?> {
  AlertHistoryTable({super.tableRelation}) : super(tableName: 'alert_history') {
    host = _i1.ColumnString(
      'host',
      this,
    );
    service = _i1.ColumnString(
      'service',
      this,
    );
    canonicalKey = _i1.ColumnString(
      'canonicalKey',
      this,
    );
    state = _i1.ColumnInt(
      'state',
      this,
    );
    message = _i1.ColumnString(
      'message',
      this,
    );
    createdAt = _i1.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final _i1.ColumnString host;

  late final _i1.ColumnString service;

  late final _i1.ColumnString canonicalKey;

  late final _i1.ColumnInt state;

  late final _i1.ColumnString message;

  late final _i1.ColumnDateTime createdAt;

  @override
  List<_i1.Column> get columns => [
        id,
        host,
        service,
        canonicalKey,
        state,
        message,
        createdAt,
      ];
}

class AlertHistoryInclude extends _i1.IncludeObject {
  AlertHistoryInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<int?> get table => AlertHistory.t;
}

class AlertHistoryIncludeList extends _i1.IncludeList {
  AlertHistoryIncludeList._({
    _i1.WhereExpressionBuilder<AlertHistoryTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AlertHistory.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<int?> get table => AlertHistory.t;
}

class AlertHistoryRepository {
  const AlertHistoryRepository._();

  /// Returns a list of [AlertHistory]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<AlertHistory>> find(
    _i1.Session session, {
    _i1.WhereExpressionBuilder<AlertHistoryTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<AlertHistoryTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertHistoryTable>? orderByList,
    _i1.Transaction? transaction,
  }) async {
    return session.db.find<AlertHistory>(
      where: where?.call(AlertHistory.t),
      orderBy: orderBy?.call(AlertHistory.t),
      orderByList: orderByList?.call(AlertHistory.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
    );
  }

  /// Returns the first matching [AlertHistory] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<AlertHistory?> findFirstRow(
    _i1.Session session, {
    _i1.WhereExpressionBuilder<AlertHistoryTable>? where,
    int? offset,
    _i1.OrderByBuilder<AlertHistoryTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<AlertHistoryTable>? orderByList,
    _i1.Transaction? transaction,
  }) async {
    return session.db.findFirstRow<AlertHistory>(
      where: where?.call(AlertHistory.t),
      orderBy: orderBy?.call(AlertHistory.t),
      orderByList: orderByList?.call(AlertHistory.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
    );
  }

  /// Finds a single [AlertHistory] by its [id] or null if no such row exists.
  Future<AlertHistory?> findById(
    _i1.Session session,
    int id, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.findById<AlertHistory>(
      id,
      transaction: transaction,
    );
  }

  /// Inserts all [AlertHistory]s in the list and returns the inserted rows.
  ///
  /// The returned [AlertHistory]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  Future<List<AlertHistory>> insert(
    _i1.Session session,
    List<AlertHistory> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insert<AlertHistory>(
      rows,
      transaction: transaction,
    );
  }

  /// Inserts a single [AlertHistory] and returns the inserted row.
  ///
  /// The returned [AlertHistory] will have its `id` field set.
  Future<AlertHistory> insertRow(
    _i1.Session session,
    AlertHistory row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<AlertHistory>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [AlertHistory]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<AlertHistory>> update(
    _i1.Session session,
    List<AlertHistory> rows, {
    _i1.ColumnSelections<AlertHistoryTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<AlertHistory>(
      rows,
      columns: columns?.call(AlertHistory.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AlertHistory]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AlertHistory> updateRow(
    _i1.Session session,
    AlertHistory row, {
    _i1.ColumnSelections<AlertHistoryTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<AlertHistory>(
      row,
      columns: columns?.call(AlertHistory.t),
      transaction: transaction,
    );
  }

  /// Deletes all [AlertHistory]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<AlertHistory>> delete(
    _i1.Session session,
    List<AlertHistory> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<AlertHistory>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [AlertHistory].
  Future<AlertHistory> deleteRow(
    _i1.Session session,
    AlertHistory row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AlertHistory>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<AlertHistory>> deleteWhere(
    _i1.Session session, {
    required _i1.WhereExpressionBuilder<AlertHistoryTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<AlertHistory>(
      where: where(AlertHistory.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.Session session, {
    _i1.WhereExpressionBuilder<AlertHistoryTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<AlertHistory>(
      where: where?.call(AlertHistory.t),
      limit: limit,
      transaction: transaction,
    );
  }
}

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

abstract class PersistedAlertState
    implements _i1.TableRow<int?>, _i1.ProtocolSerialization {
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

  static final t = PersistedAlertStateTable();

  static const db = PersistedAlertStateRepository._();

  @override
  int? id;

  String host;

  String? service;

  String canonicalKey;

  int lastState;

  DateTime lastUpdated;

  @override
  _i1.Table<int?> get table => t;

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
  Map<String, dynamic> toJsonForProtocol() {
    return {
      if (id != null) 'id': id,
      'host': host,
      if (service != null) 'service': service,
      'canonicalKey': canonicalKey,
      'lastState': lastState,
      'lastUpdated': lastUpdated.toJson(),
    };
  }

  static PersistedAlertStateInclude include() {
    return PersistedAlertStateInclude._();
  }

  static PersistedAlertStateIncludeList includeList({
    _i1.WhereExpressionBuilder<PersistedAlertStateTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PersistedAlertStateTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PersistedAlertStateTable>? orderByList,
    PersistedAlertStateInclude? include,
  }) {
    return PersistedAlertStateIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PersistedAlertState.t),
      orderDescending: orderDescending,
      orderByList: orderByList?.call(PersistedAlertState.t),
      include: include,
    );
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

class PersistedAlertStateTable extends _i1.Table<int?> {
  PersistedAlertStateTable({super.tableRelation})
      : super(tableName: 'persisted_alert_state') {
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
    lastState = _i1.ColumnInt(
      'lastState',
      this,
    );
    lastUpdated = _i1.ColumnDateTime(
      'lastUpdated',
      this,
    );
  }

  late final _i1.ColumnString host;

  late final _i1.ColumnString service;

  late final _i1.ColumnString canonicalKey;

  late final _i1.ColumnInt lastState;

  late final _i1.ColumnDateTime lastUpdated;

  @override
  List<_i1.Column> get columns => [
        id,
        host,
        service,
        canonicalKey,
        lastState,
        lastUpdated,
      ];
}

class PersistedAlertStateInclude extends _i1.IncludeObject {
  PersistedAlertStateInclude._();

  @override
  Map<String, _i1.Include?> get includes => {};

  @override
  _i1.Table<int?> get table => PersistedAlertState.t;
}

class PersistedAlertStateIncludeList extends _i1.IncludeList {
  PersistedAlertStateIncludeList._({
    _i1.WhereExpressionBuilder<PersistedAlertStateTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderDescending,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(PersistedAlertState.t);
  }

  @override
  Map<String, _i1.Include?> get includes => include?.includes ?? {};

  @override
  _i1.Table<int?> get table => PersistedAlertState.t;
}

class PersistedAlertStateRepository {
  const PersistedAlertStateRepository._();

  /// Returns a list of [PersistedAlertState]s matching the given query parameters.
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
  Future<List<PersistedAlertState>> find(
    _i1.Session session, {
    _i1.WhereExpressionBuilder<PersistedAlertStateTable>? where,
    int? limit,
    int? offset,
    _i1.OrderByBuilder<PersistedAlertStateTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PersistedAlertStateTable>? orderByList,
    _i1.Transaction? transaction,
  }) async {
    return session.db.find<PersistedAlertState>(
      where: where?.call(PersistedAlertState.t),
      orderBy: orderBy?.call(PersistedAlertState.t),
      orderByList: orderByList?.call(PersistedAlertState.t),
      orderDescending: orderDescending,
      limit: limit,
      offset: offset,
      transaction: transaction,
    );
  }

  /// Returns the first matching [PersistedAlertState] matching the given query parameters.
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
  Future<PersistedAlertState?> findFirstRow(
    _i1.Session session, {
    _i1.WhereExpressionBuilder<PersistedAlertStateTable>? where,
    int? offset,
    _i1.OrderByBuilder<PersistedAlertStateTable>? orderBy,
    bool orderDescending = false,
    _i1.OrderByListBuilder<PersistedAlertStateTable>? orderByList,
    _i1.Transaction? transaction,
  }) async {
    return session.db.findFirstRow<PersistedAlertState>(
      where: where?.call(PersistedAlertState.t),
      orderBy: orderBy?.call(PersistedAlertState.t),
      orderByList: orderByList?.call(PersistedAlertState.t),
      orderDescending: orderDescending,
      offset: offset,
      transaction: transaction,
    );
  }

  /// Finds a single [PersistedAlertState] by its [id] or null if no such row exists.
  Future<PersistedAlertState?> findById(
    _i1.Session session,
    int id, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.findById<PersistedAlertState>(
      id,
      transaction: transaction,
    );
  }

  /// Inserts all [PersistedAlertState]s in the list and returns the inserted rows.
  ///
  /// The returned [PersistedAlertState]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  Future<List<PersistedAlertState>> insert(
    _i1.Session session,
    List<PersistedAlertState> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insert<PersistedAlertState>(
      rows,
      transaction: transaction,
    );
  }

  /// Inserts a single [PersistedAlertState] and returns the inserted row.
  ///
  /// The returned [PersistedAlertState] will have its `id` field set.
  Future<PersistedAlertState> insertRow(
    _i1.Session session,
    PersistedAlertState row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.insertRow<PersistedAlertState>(
      row,
      transaction: transaction,
    );
  }

  /// Updates all [PersistedAlertState]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  Future<List<PersistedAlertState>> update(
    _i1.Session session,
    List<PersistedAlertState> rows, {
    _i1.ColumnSelections<PersistedAlertStateTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.update<PersistedAlertState>(
      rows,
      columns: columns?.call(PersistedAlertState.t),
      transaction: transaction,
    );
  }

  /// Updates a single [PersistedAlertState]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<PersistedAlertState> updateRow(
    _i1.Session session,
    PersistedAlertState row, {
    _i1.ColumnSelections<PersistedAlertStateTable>? columns,
    _i1.Transaction? transaction,
  }) async {
    return session.db.updateRow<PersistedAlertState>(
      row,
      columns: columns?.call(PersistedAlertState.t),
      transaction: transaction,
    );
  }

  /// Deletes all [PersistedAlertState]s in the list and returns the deleted rows.
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  Future<List<PersistedAlertState>> delete(
    _i1.Session session,
    List<PersistedAlertState> rows, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.delete<PersistedAlertState>(
      rows,
      transaction: transaction,
    );
  }

  /// Deletes a single [PersistedAlertState].
  Future<PersistedAlertState> deleteRow(
    _i1.Session session,
    PersistedAlertState row, {
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteRow<PersistedAlertState>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  Future<List<PersistedAlertState>> deleteWhere(
    _i1.Session session, {
    required _i1.WhereExpressionBuilder<PersistedAlertStateTable> where,
    _i1.Transaction? transaction,
  }) async {
    return session.db.deleteWhere<PersistedAlertState>(
      where: where(PersistedAlertState.t),
      transaction: transaction,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _i1.Session session, {
    _i1.WhereExpressionBuilder<PersistedAlertStateTable>? where,
    int? limit,
    _i1.Transaction? transaction,
  }) async {
    return session.db.count<PersistedAlertState>(
      where: where?.call(PersistedAlertState.t),
      limit: limit,
      transaction: transaction,
    );
  }
}

import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Server data kept on the phone so the worker screens still open without
/// signal. Rows are keyed by user so a shared phone never shows someone else's
/// data, and the whole table is wiped on sign-out.
class CachedRecords extends Table {
  TextColumn get userId => text()();

  /// What the row is, e.g. `task` (my-queue item) or `task_detail`.
  TextColumn get scope => text()();
  TextColumn get recordKey => text()();
  TextColumn get json => text()();

  /// Server order within a scope (my-queue is already sorted by the API).
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, scope, recordKey};
}

/// Changes made offline that are safe to replay (idempotent "set" operations).
/// Clock in/out and material usage are deliberately NOT queued: the backend has
/// no idempotency key, so a replay could create duplicates.
class OutboxOps extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();

  /// Operation type, e.g. `task_status`.
  TextColumn get kind => text()();

  /// What it applies to (task id). One pending op per (kind, target): the latest wins.
  TextColumn get targetId => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// `pending` (will be retried) or `failed` (server refused; needs the user).
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Events recorded without a connection that must reach the server exactly
/// once: clock in, clock out, material used. Unlike [OutboxOps] these are never
/// merged (two clock-ins are two events) and are sent oldest first.
///
/// Each carries the time it really happened, which the server stores, so after
/// an uncertain send the server can be asked for that exact moment before the
/// event is ever sent again.
class QueuedWrites extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();

  /// `clock_in`, `clock_out` or `material_usage`.
  TextColumn get kind => text()();

  /// Writes of one stream are sent in order and one that needs attention holds
  /// the rest of its stream back (a clock-out must never be sent before its
  /// clock-in). Everything on the clock shares `time`; each usage has its own.
  TextColumn get stream => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  /// `pending` (not sent yet), `unconfirmed` (sent, no answer: ask before
  /// sending again) or `attention` (the server refused it; needs the person).
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Alerts this phone received, kept so they can be read later in the app even
/// when the server's own notification list is not available. Keyed by user so a
/// shared phone never shows someone else's alerts; wiped on sign-out.
class LocalNotifications extends Table {
  /// The server's notification id when the alert carried one (so the same alert
  /// is not listed twice), else the push message id.
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();

  /// The app screen the alert opens, already checked to be an in-app path.
  TextColumn get route => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {userId, id};
}

@DriftDatabase(
  tables: [CachedRecords, OutboxOps, QueuedWrites, LocalNotifications],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(queuedWrites);
      if (from < 3) await m.createTable(localNotifications);
    },
  );

  // ---- cache -----------------------------------------------------------

  /// Replaces every row of [scope] for [userId] with [rows], keeping their order.
  Future<void> replaceCache(
    String userId,
    String scope,
    List<({String key, String json})> rows,
  ) {
    return transaction(() async {
      await (delete(
        cachedRecords,
      )..where((r) => r.userId.equals(userId) & r.scope.equals(scope))).go();
      final now = DateTime.now();
      await batch((b) {
        b.insertAll(cachedRecords, [
          for (var i = 0; i < rows.length; i++)
            CachedRecordsCompanion.insert(
              userId: userId,
              scope: scope,
              recordKey: rows[i].key,
              json: rows[i].json,
              position: Value(i),
              fetchedAt: now,
            ),
        ]);
      });
    });
  }

  Future<void> putCache(
    String userId,
    String scope,
    String key,
    String json,
  ) async {
    await into(cachedRecords).insertOnConflictUpdate(
      CachedRecordsCompanion.insert(
        userId: userId,
        scope: scope,
        recordKey: key,
        json: json,
        fetchedAt: DateTime.now(),
      ),
    );
  }

  Future<CachedRecord?> getCache(String userId, String scope, String key) {
    return (select(cachedRecords)..where(
          (r) =>
              r.userId.equals(userId) &
              r.scope.equals(scope) &
              r.recordKey.equals(key),
        ))
        .getSingleOrNull();
  }

  Future<List<CachedRecord>> readCache(String userId, String scope) {
    return (select(cachedRecords)
          ..where((r) => r.userId.equals(userId) & r.scope.equals(scope))
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
  }

  // ---- outbox ----------------------------------------------------------

  /// Queues [payload] for ([kind], [targetId]); an older pending op for the
  /// same target is replaced because these operations just set a value.
  Future<void> enqueue({
    required String id,
    required String userId,
    required String kind,
    required String targetId,
    required String payload,
  }) {
    return transaction(() async {
      await (delete(outboxOps)..where(
            (o) =>
                o.userId.equals(userId) &
                o.kind.equals(kind) &
                o.targetId.equals(targetId),
          ))
          .go();
      await into(outboxOps).insert(
        OutboxOpsCompanion.insert(
          id: id,
          userId: userId,
          kind: kind,
          targetId: targetId,
          payload: payload,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<List<OutboxOp>> outboxFor(String userId) {
    return (select(outboxOps)
          ..where((o) => o.userId.equals(userId))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .get();
  }

  Stream<List<OutboxOp>> watchOutbox(String userId) {
    return (select(outboxOps)
          ..where((o) => o.userId.equals(userId))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .watch();
  }

  Future<void> removeOp(String id) =>
      (delete(outboxOps)..where((o) => o.id.equals(id))).go();

  /// Drops queued ops for one target (e.g. a newer direct write supersedes them).
  Future<void> removeOpsFor(String userId, String kind, String targetId) =>
      (delete(outboxOps)..where(
            (o) =>
                o.userId.equals(userId) &
                o.kind.equals(kind) &
                o.targetId.equals(targetId),
          ))
          .go();

  /// Puts a `failed` op back in the queue (the user chose to retry it).
  Future<void> markPending(String id) =>
      (update(outboxOps)..where((o) => o.id.equals(id))).write(
        const OutboxOpsCompanion(
          status: Value('pending'),
          lastError: Value(null),
        ),
      );

  Future<void> recordAttempt(String id) async {
    await customUpdate(
      'UPDATE outbox_ops SET attempts = attempts + 1 WHERE id = ?',
      variables: [Variable<String>(id)],
      updates: {outboxOps},
    );
  }

  Future<void> markFailed(String id, String error) =>
      (update(outboxOps)..where((o) => o.id.equals(id))).write(
        OutboxOpsCompanion(
          status: const Value('failed'),
          lastError: Value(error),
        ),
      );

  // ---- queued writes ----------------------------------------------------

  Future<void> addQueuedWrite({
    required String id,
    required String userId,
    required String kind,
    required String stream,
    required String payload,
  }) => into(queuedWrites).insert(
    QueuedWritesCompanion.insert(
      id: id,
      userId: userId,
      kind: kind,
      stream: stream,
      payload: payload,
      createdAt: DateTime.now(),
    ),
  );

  /// Oldest first, which is the order they happened and must be sent. Ordered
  /// by insertion (`rowid`), not by time: a stored time has one-second
  /// precision, so a clock-in and clock-out saved in the same second would
  /// otherwise have no defined order.
  Future<List<QueuedWrite>> queuedWritesFor(String userId) {
    return (select(queuedWrites)
          ..where((w) => w.userId.equals(userId))
          ..orderBy([
            (w) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
          ]))
        .get();
  }

  Stream<List<QueuedWrite>> watchQueuedWrites(String userId) {
    return (select(queuedWrites)
          ..where((w) => w.userId.equals(userId))
          ..orderBy([
            (w) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
          ]))
        .watch();
  }

  Future<void> removeQueuedWrite(String id) =>
      (delete(queuedWrites)..where((w) => w.id.equals(id))).go();

  /// Used when the person signs out and chooses to give up what is waiting.
  Future<void> removeQueuedWritesFor(String userId) =>
      (delete(queuedWrites)..where((w) => w.userId.equals(userId))).go();

  Future<void> updateQueuedPayload(String id, String payload) =>
      (update(queuedWrites)..where((w) => w.id.equals(id))).write(
        QueuedWritesCompanion(payload: Value(payload)),
      );

  Future<void> setQueuedStatus(
    String id,
    String status, {
    String? error,
    bool attempted = false,
  }) => (update(queuedWrites)..where((w) => w.id.equals(id))).write(
    QueuedWritesCompanion(
      status: Value(status),
      lastError: Value(error),
      lastAttemptAt: attempted ? Value(DateTime.now()) : const Value.absent(),
    ),
  );

  Future<void> recordQueuedAttempt(String id) async {
    await customUpdate(
      'UPDATE queued_writes SET attempts = attempts + 1, last_attempt_at = ? WHERE id = ?',
      variables: [Variable<DateTime>(DateTime.now()), Variable<String>(id)],
      updates: {queuedWrites},
    );
  }

  // ---- received alerts --------------------------------------------------

  /// Keeps an alert the phone received. A repeat of the same alert changes
  /// nothing (it keeps whether it was read).
  Future<void> saveLocalNotification({
    required String id,
    required String userId,
    required String title,
    required String body,
    String? route,
    DateTime? receivedAt,
  }) async {
    await into(localNotifications).insert(
      LocalNotificationsCompanion.insert(
        id: id,
        userId: userId,
        title: title,
        body: body,
        route: Value(route),
        receivedAt: receivedAt ?? DateTime.now(),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    // Keep the newest 100 only.
    await customUpdate(
      'DELETE FROM local_notifications WHERE user_id = ? AND rowid NOT IN '
      '(SELECT rowid FROM local_notifications WHERE user_id = ? '
      'ORDER BY received_at DESC, rowid DESC LIMIT 100)',
      variables: [Variable<String>(userId), Variable<String>(userId)],
      updates: {localNotifications},
    );
  }

  Stream<List<LocalNotification>> watchLocalNotifications(String userId) {
    return (select(localNotifications)
          ..where((n) => n.userId.equals(userId))
          ..orderBy([
            (n) => OrderingTerm.desc(n.receivedAt),
            (n) => OrderingTerm.desc(const CustomExpression<int>('rowid')),
          ]))
        .watch();
  }

  Future<void> markLocalNotificationRead(String userId, String id) =>
      (update(localNotifications)
            ..where((n) => n.userId.equals(userId) & n.id.equals(id)))
          .write(const LocalNotificationsCompanion(isRead: Value(true)));

  Future<void> markAllLocalNotificationsRead(String userId) =>
      (update(localNotifications)..where((n) => n.userId.equals(userId))).write(
        const LocalNotificationsCompanion(isRead: Value(true)),
      );

  /// Removes cached server data and queued task-status changes. Called on
  /// sign-out and session expiry.
  ///
  /// Queued writes are NOT removed here: they are the person's own unsent time
  /// and material records, so an expired session must not lose them. They stay
  /// keyed by user (nobody else sees or sends them) and go out when the same
  /// person signs back in. An explicit sign-out asks first and then uses
  /// [removeQueuedWritesFor].
  Future<void> wipe() async {
    await delete(cachedRecords).go();
    await delete(outboxOps).go();
    await delete(localNotifications).go();
  }
}

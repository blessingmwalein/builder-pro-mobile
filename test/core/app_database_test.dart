import 'package:builder_pro_mobile/core/offline/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'replaceCache keeps server order and replaces the previous rows',
    () async {
      await db.replaceCache('u1', 'task', [
        (key: 'b', json: '{"n":2}'),
        (key: 'a', json: '{"n":1}'),
      ]);
      expect((await db.readCache('u1', 'task')).map((r) => r.recordKey), [
        'b',
        'a',
      ]);

      await db.replaceCache('u1', 'task', [(key: 'c', json: '{}')]);
      expect((await db.readCache('u1', 'task')).map((r) => r.recordKey), ['c']);
    },
  );

  test('cache rows are separated by user and by scope', () async {
    await db.replaceCache('u1', 'task', [(key: 'a', json: '{}')]);
    await db.putCache('u2', 'task', 'x', '{}');
    await db.putCache('u1', 'task_detail', 'a', '{"d":1}');

    expect((await db.readCache('u1', 'task')).length, 1);
    expect((await db.readCache('u2', 'task')).single.recordKey, 'x');
    expect((await db.getCache('u1', 'task_detail', 'a'))?.json, '{"d":1}');
    expect(await db.getCache('u2', 'task_detail', 'a'), isNull);
  });

  test('putCache overwrites the same key', () async {
    await db.putCache('u1', 'task_detail', 'a', '{"v":1}');
    await db.putCache('u1', 'task_detail', 'a', '{"v":2}');
    expect((await db.getCache('u1', 'task_detail', 'a'))?.json, '{"v":2}');
  });

  test('enqueue keeps only the latest op per target', () async {
    await db.enqueue(
      id: '1',
      userId: 'u1',
      kind: 'task_status',
      targetId: 't1',
      payload: '{"status":"IN_PROGRESS"}',
    );
    await db.enqueue(
      id: '2',
      userId: 'u1',
      kind: 'task_status',
      targetId: 't1',
      payload: '{"status":"DONE"}',
    );
    await db.enqueue(
      id: '3',
      userId: 'u1',
      kind: 'task_status',
      targetId: 't2',
      payload: '{"status":"BLOCKED"}',
    );

    final ops = await db.outboxFor('u1');
    expect(ops.map((o) => o.id), ['2', '3']);
    expect(ops.first.payload, contains('DONE'));
  });

  test('outbox ops are scoped to their user', () async {
    await db.enqueue(
      id: '1',
      userId: 'u1',
      kind: 'task_status',
      targetId: 't1',
      payload: '{}',
    );
    expect(await db.outboxFor('u2'), isEmpty);
  });

  test('recordAttempt and markFailed update the op', () async {
    await db.enqueue(
      id: '1',
      userId: 'u1',
      kind: 'task_status',
      targetId: 't1',
      payload: '{}',
    );
    await db.recordAttempt('1');
    await db.recordAttempt('1');
    await db.markFailed('1', 'Task not found');

    final op = (await db.outboxFor('u1')).single;
    expect(op.attempts, 2);
    expect(op.status, 'failed');
    expect(op.lastError, 'Task not found');
  });

  test('wipe removes cache and outbox for every user', () async {
    await db.putCache('u1', 'task', 'a', '{}');
    await db.enqueue(
      id: '1',
      userId: 'u1',
      kind: 'task_status',
      targetId: 't1',
      payload: '{}',
    );
    await db.wipe();
    expect(await db.readCache('u1', 'task'), isEmpty);
    expect(await db.outboxFor('u1'), isEmpty);
  });
}

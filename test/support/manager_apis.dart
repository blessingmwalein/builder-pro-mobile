import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:dio/dio.dart' show DioExceptionType, RequestOptions;

import 'api_fixtures.dart';
import 'fake_adapter.dart';
import 'fakes.dart';
import 'fixtures.dart';

SessionState supervisorSession({List<String>? perms}) =>
    SessionState.authenticated(
      testMe(permissions: perms ?? supervisorPerms, role: 'Site Supervisor'),
    );

String isoDays(int days) =>
    DateTime.now().add(Duration(days: days)).toUtc().toIso8601String();

/// Replies for everything a supervisor's screens load. Pass replacement
/// handlers/data to change one part; anything not passed gets a sensible default.
void supervisorApis(
  TestEnv env, {
  List<Map<String, dynamic>>? pending,
  Map<String, List<Map<String, dynamic>>>? tasksByStatus,
  Reply Function(RequestOptions)? tasks,
  List<Map<String, dynamic>>? projects,
  Map<String, dynamic>? projectDetail,
  bool ownClockActive = false,
  bool approvalsOffline = false,
  bool tasksFail = false,
  bool projectsFail = false,
}) {
  env.adapter
    ..on(
      'GET',
      'time-tracking/active',
      (_) => ownClockActive
          ? Reply.json(
              timeEntryJson(
                clockInAt: DateTime.now()
                    .subtract(const Duration(hours: 1))
                    .toUtc()
                    .toIso8601String(),
              ),
            )
          : Reply.empty(),
    )
    ..on(
      'GET',
      'time-tracking/weekly-summary',
      (_) => Reply.json({'entries': []}),
    )
    ..on(
      'GET',
      'time-tracking',
      (o) => approvalsOffline
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              paged(
                pending ??
                    [
                      approvalEntryJson(id: 'e1'),
                      approvalEntryJson(
                        id: 'e2',
                        clockIn: DateTime.now().subtract(
                          const Duration(days: 2, hours: 9),
                        ),
                      ),
                      approvalEntryJson(
                        id: 'e3',
                        workerId: 'w2',
                        first: 'Rudo',
                        last: 'Banda',
                        manual: true,
                        notes: 'Forgot to clock in',
                      ),
                      approvalEntryJson(
                        id: 'live',
                        workerId: 'w3',
                        first: 'Farai',
                        last: 'Ncube',
                        open: true,
                        clockIn: DateTime.now().subtract(
                          const Duration(hours: 3),
                        ),
                      ),
                    ],
                limit: 50,
              ),
            ),
    )
    ..on(
      'GET',
      'tasks',
      tasks ??
          (o) {
            if (tasksFail) return Reply.json({'statusCode': 500}, status: 500);
            final status = o.queryParameters['status'] as String?;
            final project = o.queryParameters['projectId'] as String?;
            final defaults = <String, List<Map<String, dynamic>>>{
              'BLOCKED': [
                taskJson(id: 'tb', title: 'Fix railing', status: 'BLOCKED'),
              ],
              'IN_PROGRESS': [
                taskJson(
                  id: 'ti',
                  title: 'Pour slab',
                  status: 'IN_PROGRESS',
                  dueDate: isoDays(-3),
                ),
              ],
              'REVIEW': [],
              'TODO': [
                taskJson(
                  id: 'tt',
                  title: 'Order rebar',
                  dueDate: DateTime.now().toUtc().toIso8601String(),
                ),
              ],
            };
            final source = tasksByStatus ?? defaults;
            if (status != null) {
              return Reply.json(paged(source[status] ?? [], limit: 100));
            }
            // A project's task list (all statuses).
            return Reply.json(
              paged(
                [
                      for (final list in source.values) ...list,
                      taskJson(id: 'td', title: 'Set out site', status: 'DONE'),
                    ]
                    .where((t) => project == null || t['projectId'] == project)
                    .toList(),
                limit: 100,
              ),
            );
          },
    )
    ..on(
      'GET',
      'projects',
      (_) => projectsFail
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              paged(
                projects ??
                    [
                      projectJson(),
                      projectJson(
                        id: 'p2',
                        name: 'Borrowdale Villas',
                        code: 'BV-02',
                        status: 'ON_HOLD',
                        completion: 75,
                      ),
                    ],
                limit: 20,
              ),
            ),
    )
    ..on(
      'GET',
      'projects/p1',
      (_) => Reply.json(
        projectDetail ??
            projectJson(
              members: [
                memberJson(),
                memberJson(id: 'u3', first: 'Farai', last: 'Ncube', role: null),
              ],
            ),
      ),
    );
}

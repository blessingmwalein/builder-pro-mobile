import 'dart:async' show unawaited;

import 'package:builder_pro_mobile/app/router/app_router.dart'
    show routerProvider;
import 'package:builder_pro_mobile/core/utils/format.dart';
import 'package:builder_pro_mobile/features/projects/application/projects_providers.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

const _viewOnly = ['tasks.*', 'projects.view', 'materials.view', 'messaging.*'];

/// Supervisor replies plus a small equipment fleet. Item `e1` is in whatever
/// state a test asks for; `e2` is always available.
void _apis(
  TestEnv env, {
  String status = 'AVAILABLE',
  List<Map<String, dynamic>>? allocations,
  bool detailFails = false,
  bool projectsFail = false,
}) {
  supervisorApis(env, projectsFail: projectsFail);
  env.adapter
    ..on('GET', 'equipment', (o) {
      final wanted = o.queryParameters['status'];
      final all = [
        equipJson(status: status),
        equipJson(
          id: 'e2',
          name: 'Concrete mixer',
          category: null,
          serial: null,
        ),
        equipJson(
          id: 'e3',
          name: 'Scaffold set',
          status: 'MAINTENANCE',
          category: 'Access',
        ),
      ];
      return Reply.json(
        paged(
          wanted == null
              ? all
              : all.where((e) => e['status'] == wanted).toList(),
          limit: 20,
        ),
      );
    })
    ..on(
      'GET',
      'equipment/e1',
      (_) => detailFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              equipJson(
                detail: true,
                status: status,
                allocations:
                    allocations ??
                    (status == 'IN_USE'
                        ? [
                            allocJson(
                              end: DateTime.utc(2026, 11, 9),
                              notes: 'Slab',
                            ),
                            allocJson(
                              id: 'old',
                              project: 'Borrowdale Villas',
                              projectId: 'p2',
                              start: DateTime.utc(2026, 9, 1),
                              returnedAt: DateTime.utc(2026, 9, 20, 10),
                              by: 'u9',
                            ),
                          ]
                        : [
                            allocJson(
                              id: 'old',
                              project: 'Borrowdale Villas',
                              projectId: 'p2',
                              start: DateTime.utc(2026, 9, 1),
                              returnedAt: DateTime.utc(2026, 9, 20, 10),
                              by: 'u9',
                            ),
                          ]),
              ),
            ),
    );
}

Future<void> _openEquipment(WidgetTester tester) async {
  await tester.tap(find.text('More').last);
  await settle(tester);
  await tester.scrollUntilVisible(
    find.text('Equipment'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text('Equipment'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('Equipment'));
  await settle(tester);
}

Future<void> _openFirst(WidgetTester tester) async {
  await tester.tap(find.text('Excavator CAT 320'));
  await settle(tester);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens the platform date picker on [fieldValue], types [typed] (MM/DD/YYYY)
/// and confirms. Typing keeps the date fixed whatever today is.
Future<void> _typeDate(
  WidgetTester tester,
  String fieldValue,
  String typed,
) async {
  await tester.tap(find.widgetWithText(InkWell, fieldValue));
  await settle(tester);
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await settle(tester);
  await tester.enterText(find.byType(TextField).last, typed);
  await tester.tap(find.text('OK'));
  await settle(tester);
}

void main() {
  group('list', () {
    testWidgets('shows name, status, category and serial, and no costs', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);

      expect(find.text('Excavator CAT 320'), findsOneWidget);
      expect(find.text('Heavy plant · Serial CAT-0042'), findsOneWidget);
      expect(find.text('Available'), findsWidgets);
      expect(find.text('Maintenance'), findsWidgets);
      expect(find.text('Concrete mixer'), findsOneWidget);
      // The API sends a daily rate and a purchase cost; neither is shown.
      expect(find.textContaining('250'), findsNothing);
      expect(find.textContaining('84,000'), findsNothing);
    });

    testWidgets('a status chip filters through the server', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'IN_USE');
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);

      final chip = find.widgetWithText(ChoiceChip, 'Maintenance');
      await tester.ensureVisible(chip);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(chip);
      await settle(tester);

      expect(
        env.adapter.last('GET', 'equipment').query['status'],
        'MAINTENANCE',
      );
      expect(find.text('Scaffold set'), findsOneWidget);
      expect(find.text('Excavator CAT 320'), findsNothing);
    });

    testWidgets('an empty fleet says where equipment is added', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      env.adapter.on(
        'GET',
        'equipment',
        (_) => Reply.json(paged([], limit: 20)),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      expect(find.text('No equipment yet'), findsOneWidget);
      expect(find.text('Equipment is added on the web app.'), findsOneWidget);
    });

    testWidgets('a failed load is an error with Retry, not "no equipment"', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      env.adapter.on(
        'GET',
        'equipment',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No equipment yet'), findsNothing);
    });

    testWidgets('a role without materials.view does not get Equipment', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: [
            'tasks.*',
            'timesheets.view_own',
            'materials.log',
            'messaging.*',
          ],
        ),
        env: env,
      );
      await settle(tester);
      await tester.tap(find.text('More').last);
      await settle(tester);
      expect(find.text('Equipment'), findsNothing);
    });
  });

  group('detail', () {
    testWidgets('available: history, an Assign button and no costs', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);

      expect(find.text('Tracked excavator, 20 t'), findsOneWidget);
      expect(find.text('Assign to a project'), findsOneWidget);
      expect(find.text('Mark returned'), findsNothing);
      await _scrollTo(tester, find.text('Borrowdale Villas'));
      expect(find.textContaining('returned'), findsWidgets);
      expect(find.textContaining('250'), findsNothing);
      expect(find.textContaining('84,000'), findsNothing);
    });

    testWidgets('in use: where it is, due-back date and who assigned it', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'IN_USE');
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);

      expect(find.text('WHERE IT IS'), findsOneWidget);
      expect(find.text('Harare Tower'), findsWidgets);
      expect(
        find.textContaining('Mon 26 Oct → due back Mon 9 Nov'),
        findsWidgets,
      );
      expect(find.text('Assigned by Tendai Moyo'), findsWidgets);
      expect(find.text('Assign to a project'), findsNothing);
      expect(find.text('Mark returned'), findsOneWidget);
    });

    testWidgets(
      'Mark returned confirms with the facts, re-reads, then sends once',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, status: 'IN_USE');
        env.adapter.on(
          'POST',
          'equipment/e1/return/a1',
          (_) => Reply.json({'success': true}, status: 201),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openEquipment(tester);
        await _openFirst(tester);

        await tester.tap(find.widgetWithText(InkWell, 'Mark returned'));
        await settle(tester);
        expect(
          find.text('Mark Excavator CAT 320 as returned?'),
          findsOneWidget,
        );
        expect(
          find.textContaining('assigned to Harare Tower from Mon 26 Oct'),
          findsOneWidget,
        );
        expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 0);

        await tester.tap(find.widgetWithText(InkWell, 'Mark returned').last);
        await settle(tester);

        expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 1);
        expect(find.text('Marked as returned.'), findsOneWidget);
      },
    );

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'IN_USE');
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);

      await tester.tap(find.widgetWithText(InkWell, 'Mark returned'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a refused return says why and leaves the item', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'IN_USE');
      env.adapter.on(
        'POST',
        'equipment/e1/return/a1',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);

      await tester.tap(find.widgetWithText(InkWell, 'Mark returned'));
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Mark returned').last);
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 1);
      expect(find.widgetWithText(InkWell, 'Mark returned'), findsOneWidget);
    });

    testWidgets('a view-only role sees the item but no actions', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      for (final status in ['AVAILABLE', 'IN_USE']) {
        final e = TestEnv();
        addTearDown(e.dispose);
        _apis(e, status: status);
        await pumpApp(
          tester,
          session: supervisorSession(perms: _viewOnly),
          env: e,
        );
        await settle(tester);
        await _openEquipment(tester);
        await _openFirst(tester);
        expect(find.text('Excavator CAT 320'), findsWidgets, reason: status);
        expect(find.text('Assign to a project'), findsNothing, reason: status);
        expect(find.text('Mark returned'), findsNothing, reason: status);
        await unmount(tester);
      }
    });

    testWidgets('maintenance: no actions, and it says where that is changed', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'MAINTENANCE');
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);

      expect(find.text('Assign to a project'), findsNothing);
      expect(find.text('Mark returned'), findsNothing);
      expect(find.textContaining('changed on the web app'), findsOneWidget);
    });

    testWidgets(
      'two open assignments: no return from the phone, and a warning',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(
          env,
          status: 'IN_USE',
          allocations: [
            allocJson(),
            allocJson(id: 'a2', project: 'Borrowdale Villas', projectId: 'p2'),
          ],
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openEquipment(tester);
        await _openFirst(tester);

        expect(find.text('Mark returned'), findsNothing);
        expect(
          find.textContaining('more than one open assignment'),
          findsOneWidget,
        );
      },
    );

    testWidgets('assigning needs project access, and says so', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(perms: ['materials.*', 'messaging.*']),
        env: env,
      );
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);

      expect(find.text('Assign to a project'), findsNothing);
      expect(find.textContaining('needs access to projects'), findsOneWidget);
    });

    testWidgets('a failed load is an error with Retry', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, detailFails: true);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('assign', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(InkWell, 'Assign to a project'));
      await settle(tester);
      expect(find.text('Assign Excavator CAT 320'), findsOneWidget);
    }

    Future<void> chooseProject(WidgetTester tester, String name) async {
      await tester.tap(find.widgetWithText(InkWell, 'Choose a project'));
      await settle(tester);
      await tester.tap(find.text(name));
      await settle(tester);
    }

    testWidgets(
      'no project: stopped with a plain message before anything is sent',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openEquipment(tester);
        await _openFirst(tester);
        await openForm(tester);

        await tester.tap(find.widgetWithText(InkWell, 'Assign'));
        await settle(tester);

        expect(find.text('Choose a project'), findsWidgets);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets('sends the project, today, a return date and the note', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'equipment/e1/allocate',
        (_) => Reply.json(allocJson(), status: 201),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);
      await openForm(tester);

      await chooseProject(tester, 'Harare Tower');
      await tester.tap(find.widgetWithText(InkWell, 'No return date'));
      await settle(tester);
      await tester.tap(find.text('OK')); // today, the picker's first choice
      await settle(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Needed for the slab',
      );
      await tester.tap(find.widgetWithText(InkWell, 'Assign'));
      await settle(tester, frames: 20);

      final today = Fmt.isoDay(DateTime.now());
      expect(env.adapter.last('POST', 'equipment/e1/allocate').data, {
        'projectId': 'p1',
        'startDate': today,
        'endDate': today,
        'notes': 'Needed for the slab',
      });
      expect(find.text('Assigned to Harare Tower.'), findsOneWidget);
      expect(find.text('Assign Excavator CAT 320'), findsNothing);
    });

    testWidgets('a return date before the start date is refused', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);
      await openForm(tester);

      final year = DateTime.now().year + 1;
      await chooseProject(tester, 'Harare Tower');
      await _typeDate(tester, Fmt.day(DateTime.now()), '12/20/$year');
      await _typeDate(tester, 'No return date', '12/10/$year');
      await tester.tap(find.widgetWithText(InkWell, 'Assign'));
      await settle(tester);

      expect(
        find.textContaining('cannot be before the start date'),
        findsOneWidget,
      );
      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a return date can be cleared again', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);
      await openForm(tester);

      await tester.tap(find.widgetWithText(InkWell, 'No return date'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(find.text('Clear return date'), findsOneWidget);
      await tester.tap(find.text('Clear return date'));
      await tester.pump();
      expect(find.text('No return date'), findsOneWidget);
    });

    testWidgets(
      'the project list ignores a search left on the Projects screen',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        final c = await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        // Someone searched Projects for something. (Not awaited: a provider
        // future cannot be awaited inside the test's fake clock.)
        c.read(projectsCatalogProvider); // the Projects screen has loaded it
        await settle(tester);
        unawaited(c.read(projectsCatalogProvider.notifier).search('zzz'));
        await settle(tester);
        expect(env.adapter.last('GET', 'projects').query['search'], 'zzz');
        await _openEquipment(tester);
        await _openFirst(tester);
        await openForm(tester);

        await tester.tap(find.widgetWithText(InkWell, 'Choose a project'));
        await settle(tester);

        // The picker asked for the whole list, not for that search.
        final asked = env.adapter.last('GET', 'projects').query;
        expect(asked.containsKey('search'), isFalse);
        expect(asked['page'], 1);
        expect(find.text('Harare Tower'), findsOneWidget);
        expect(find.text('Borrowdale Villas'), findsOneWidget);
      },
    );

    testWidgets(
      'projects that cannot be loaded give an error and keep the form',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, projectsFail: true);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openEquipment(tester);
        await _openFirst(tester);
        await openForm(tester);

        await tester.tap(find.widgetWithText(InkWell, 'Choose a project'));
        await settle(tester);

        expect(find.text('Assign Excavator CAT 320'), findsOneWidget);
        expect(find.text('Harare Tower'), findsNothing);
      },
    );

    testWidgets('a server refusal keeps the form and what was chosen', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'equipment/e1/allocate',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);
      await openForm(tester);

      await chooseProject(tester, 'Borrowdale Villas');
      await tester.tap(find.widgetWithText(InkWell, 'Assign'));
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(find.textContaining('Borrowdale Villas'), findsWidgets);
      expect(env.adapter.count('POST', 'equipment/e1/allocate'), 1);
    });

    testWidgets('two taps in one frame send once', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'equipment/e1/allocate',
        (_) => Reply.json(
          allocJson(),
          status: 201,
          delay: const Duration(seconds: 2),
        ),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEquipment(tester);
      await _openFirst(tester);
      await openForm(tester);
      await chooseProject(tester, 'Harare Tower');

      await tester.tap(find.widgetWithText(InkWell, 'Assign'));
      await tester.tap(
        find.widgetWithText(InkWell, 'Assign'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(env.adapter.count('POST', 'equipment/e1/allocate'), 1);
    });

    testWidgets('an item that is no longer available is not assignable', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      // Someone else took it: a stale link or list still points at the form.
      _apis(
        env,
        status: 'IN_USE',
        allocations: [allocJson(by: 'u9')],
      );
      final c = await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      c.read(routerProvider).go('/equipment/e1/assign');
      await settle(tester);

      expect(find.text('Not available right now'), findsOneWidget);
      expect(find.text('Choose a project'), findsNothing);
    });

    testWidgets(
      'reaching the form by a link without materials.manage says so',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        final c = await pumpApp(
          tester,
          session: supervisorSession(perms: _viewOnly),
          env: env,
        );
        await settle(tester);
        c.read(routerProvider).go('/equipment/e1/assign');
        await settle(tester);

        expect(find.text('Not allowed'), findsOneWidget);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );
  });

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'IN_USE');
      final capture = ErrorCapture();
      final c = await pumpApp(
        tester,
        session: supervisorSession(),
        env: env,
        size: const Size(320, 640),
        textScale: 2.0,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await settle(tester);
      await _openEquipment(tester);
      await tester.tap(find.text('Excavator CAT 320'));
      await settle(tester);
      await _scrollTo(tester, find.text('Borrowdale Villas'));
      c.read(routerProvider).go('/equipment/e1/assign');
      await settle(tester);
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}

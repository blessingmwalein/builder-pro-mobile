import 'package:builder_pro_mobile/app/router/destinations.dart';
import 'package:builder_pro_mobile/app/router/route_guard.dart';
import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/core/permissions/permission_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

SessionState signedIn(List<String> perms) =>
    SessionState.authenticated(testMe(permissions: perms));

void main() {
  group('planNavigation (permission-driven, never role names)', () {
    test('Worker gets the four field tabs in priority order', () {
      final plan = planNavigation(PermissionEvaluator(workerPerms));
      expect(plan.bottom.map((d) => d.id), [
        'clock',
        'tasks',
        'materials',
        'messages',
      ]);
      expect(plan.homePath, '/clock');
    });

    test(
      'Accountant (finance persona): finance screens first, no field tabs',
      () {
        final plan = planNavigation(PermissionEvaluator(accountantPerms));
        expect(plan.bottom.map((d) => d.id), [
          'finance',
          'invoices',
          'quotes',
          'requests',
        ]);
        expect(plan.homePath, '/finance');
      },
    );

    test('a role with nothing the app uses lands on More', () {
      final plan = planNavigation(PermissionEvaluator(['reports.view']));
      expect(plan.bottom, isEmpty);
      expect(plan.homePath, '/more');
    });

    test(
      'a custom role with only messaging and tasks.view sees exactly those',
      () {
        final plan = planNavigation(
          PermissionEvaluator(['tasks.view', 'messaging.view']),
        );
        expect(plan.bottom.map((d) => d.id), ['tasks', 'messages']);
      },
    );

    test('overflow goes under More when there is not room', () {
      final plan = planNavigation(
        PermissionEvaluator(workerPerms),
        maxBottom: 2,
      );
      expect(plan.bottom.map((d) => d.id), ['clock', 'tasks']);
      expect(plan.overflow.map((d) => d.id), ['materials', 'messages']);
    });

    test('Owner (a manager) gets the overview screens first', () {
      final plan = planNavigation(PermissionEvaluator(ownerPerms));
      expect(plan.bottom.map((d) => d.id), [
        'today',
        'projects',
        'approvals',
        'messages',
      ]);
      expect(plan.overflow.map((d) => d.id), [
        'tasks',
        'clock',
        'materials',
        'purchasing',
        'equipment',
        'requests',
        'finance',
        'invoices',
        'quotes',
        'clients',
        'reports',
        'team',
      ]);
      expect(plan.homePath, '/today');
    });

    test(
      'Site Supervisor: overview first; own tasks, clock, materials in More',
      () {
        final plan = planNavigation(PermissionEvaluator(supervisorPerms));
        expect(plan.bottom.map((d) => d.id), [
          'today',
          'projects',
          'approvals',
          'messages',
        ]);
        // Site Supervisors hold materials.*, which the approvals inbox and the
        // procurement API both accept.
        expect(plan.overflow.map((d) => d.id), [
          'tasks',
          'clock',
          'materials',
          'purchasing',
          'equipment',
          'requests',
        ]);
      },
    );

    test('Worker never gets Today, Projects or Approvals (they hold projects.view)', () {
      final ids = planNavigation(PermissionEvaluator(workerPerms)).bottom
          .map((d) => d.id);
      expect(ids, isNot(contains('today')));
      expect(ids, isNot(contains('projects')));
      expect(ids, isNot(contains('approvals')));
    });

    test(
      'Projects needs BOTH viewing projects and a supervisory permission',
      () {
        bool has(List<String> p) =>
            planNavigation(PermissionEvaluator(p)).bottom
                .any((d) => d.id == 'projects');
        expect(has(['projects.view']), isFalse); // worker-like
        expect(
          has(['tasks.*']),
          isFalse,
        ); // supervises but cannot view projects
        expect(has(['projects.view', 'tasks.*']), isTrue);
        expect(has(['projects.*']), isTrue);
      },
    );

    test(
      "Approvals needs the approve right AND the right to see everyone's time",
      () {
        bool has(List<String> p) =>
            planNavigation(PermissionEvaluator(p)).bottom
                .any((d) => d.id == 'approvals');
        expect(
          has(['timesheets.approve']),
          isFalse,
        ); // could only list own entries
        expect(has(['timesheets.view_all']), isFalse);
        expect(has(['timesheets.approve', 'timesheets.view_all']), isTrue);
        expect(has(['timesheets.*']), isTrue);
      },
    );

    test('Accountant gets no field or supervisor overview tabs', () {
      final ids = planNavigation(
        PermissionEvaluator(accountantPerms),
        maxBottom: 20,
      ).bottom.map((d) => d.id).toList();
      for (final id in [
        'clock',
        'tasks',
        'materials',
        'today',
        'projects',
        'approvals',
      ]) {
        expect(ids, isNot(contains(id)), reason: id);
      }
    });

    test('Finance screens follow their own permissions', () {
      bool has(List<String> p, String id) => planNavigation(
        PermissionEvaluator(p),
        maxBottom: 20,
      ).bottom.any((d) => d.id == id);
      expect(has(['invoices.view'], 'invoices'), isTrue);
      expect(has(['invoices.view'], 'quotes'), isFalse);
      expect(has(['quotes.view'], 'quotes'), isTrue);
      expect(has(['financials.view'], 'finance'), isTrue);
      // The overview shows receivables to anyone who can see invoices.
      expect(has(['invoices.view'], 'finance'), isTrue);
      expect(has(['quotes.view'], 'finance'), isFalse);
      expect(has(workerPerms, 'finance'), isFalse);
      expect(has(workerPerms, 'invoices'), isFalse);
    });

    test('Requests needs one of projects.*, materials.*, financials.*', () {
      bool has(List<String> p) => planNavigation(
        PermissionEvaluator(p),
        maxBottom: 20,
      ).bottom.any((d) => d.id == 'requests');
      expect(has(['projects.*']), isTrue);
      expect(has(['materials.*']), isTrue);
      expect(has(['financials.*']), isTrue);
      expect(has(['projects.view']), isFalse);
      expect(has(workerPerms), isFalse);
    });

    test('an owner who also holds finance keys is still a manager first', () {
      expect(
        planNavigation(PermissionEvaluator(ownerPerms)).bottom.first.id,
        'today',
      );
    });

    test('no permissions → empty plan', () {
      expect(planNavigation(PermissionEvaluator.none).bottom, isEmpty);
    });
  });

  group('computeRedirect', () {
    test('bootstrapping always shows the splash', () {
      expect(
        computeRedirect(const SessionState.bootstrapping(), '/tasks'),
        Routes.splash,
      );
      expect(
        computeRedirect(const SessionState.bootstrapping(), Routes.splash),
        isNull,
      );
    });

    test('signed-out users can only reach login and forgot-password', () {
      const s = SessionState.unauthenticated();
      expect(computeRedirect(s, '/tasks'), Routes.login);
      expect(computeRedirect(s, '/more'), Routes.login);
      expect(computeRedirect(s, Routes.login), isNull);
      expect(computeRedirect(s, Routes.forgotPassword), isNull);
    });

    test(
      'an expired session is sent to login, not left on a protected screen',
      () {
        expect(
          computeRedirect(const SessionState.expired(), '/clock'),
          Routes.login,
        );
      },
    );

    test('subscription-blocked users are confined to the blocked screen', () {
      final s = SessionState.subscriptionBlocked(
        const AppException(
          AppErrorKind.subscription,
          'x',
          code: 'TRIAL_EXPIRED',
        ),
      );
      expect(computeRedirect(s, '/tasks'), Routes.subscriptionBlocked);
      expect(computeRedirect(s, Routes.subscriptionBlocked), isNull);
    });

    test('startup failure is confined to its screen', () {
      final s = SessionState.startupFailed(
        const AppException(AppErrorKind.offline, 'x'),
      );
      expect(computeRedirect(s, '/clock'), Routes.startupFailed);
    });

    test('signed-in user leaves auth screens for their home tab', () {
      final s = signedIn(workerPerms);
      expect(computeRedirect(s, Routes.login), '/clock');
      expect(computeRedirect(s, Routes.splash), '/clock');
      expect(computeRedirect(s, '/'), '/clock');
    });

    test('signed-in user with no tabs goes to More', () {
      expect(
        computeRedirect(signedIn(['reports.view']), Routes.login),
        '/more',
      );
    });

    test('an accountant lands on Finance', () {
      expect(
        computeRedirect(signedIn(accountantPerms), Routes.login),
        '/finance',
      );
    });

    test('permitted routes pass through, including nested paths', () {
      final s = signedIn(workerPerms);
      expect(computeRedirect(s, '/tasks'), isNull);
      expect(computeRedirect(s, '/tasks/abc123'), isNull);
      expect(computeRedirect(s, '/materials/log'), isNull);
      expect(computeRedirect(s, '/more'), isNull);
    });

    test('deep links to forbidden areas are blocked (fail closed)', () {
      final s = signedIn(['tasks.view']);
      expect(computeRedirect(s, '/materials'), Routes.denied);
      expect(computeRedirect(s, '/materials/log'), Routes.denied);
      expect(computeRedirect(s, '/clock'), Routes.denied);
      expect(computeRedirect(s, '/messages/xyz'), Routes.denied);
    });

    test('losing a permission while on a screen redirects away', () {
      expect(computeRedirect(signedIn(workerPerms), '/tasks'), isNull);
      expect(
        computeRedirect(signedIn(['materials.log']), '/tasks'),
        Routes.denied,
      );
    });

    test(
      'a path that merely starts with a destination name is not treated as it',
      () {
        // '/tasksX' is unknown, not '/tasks/…' — falls through to normal handling.
        expect(requiredPermissionsFor('/tasksX'), isNull);
        expect(requiredPermissionsFor('/tasks/1'), isNotNull);
      },
    );
  });

  group(
    'detail routes follow the permissions of their tab (deep links too)',
    () {
      const noFieldAccess = ['invoices.view'];

      test('a signed-in user without tasks permissions cannot open a task', () {
        expect(
          computeRedirect(signedIn(noFieldAccess), '/tasks/abc'),
          Routes.denied,
        );
      });

      test('...nor a conversation, nor the material log form', () {
        expect(
          computeRedirect(signedIn(noFieldAccess), '/messages/abc'),
          Routes.denied,
        );
        expect(
          computeRedirect(signedIn(noFieldAccess), '/materials/log'),
          Routes.denied,
        );
      });

      test('a worker may open them', () {
        expect(computeRedirect(signedIn(workerPerms), '/tasks/abc'), isNull);
        expect(computeRedirect(signedIn(workerPerms), '/messages/abc'), isNull);
        expect(
          computeRedirect(signedIn(workerPerms), '/materials/log'),
          isNull,
        );
      });

      test('Notifications are open to any signed-in user', () {
        expect(
          computeRedirect(signedIn(noFieldAccess), Routes.notifications),
          isNull,
        );
      });

      test('a user with only messaging cannot reach time or tasks detail', () {
        final onlyChat = signedIn(['messaging.view']);
        expect(computeRedirect(onlyChat, '/tasks/abc'), Routes.denied);
        expect(computeRedirect(onlyChat, '/clock'), Routes.denied);
        expect(computeRedirect(onlyChat, '/messages/abc'), isNull);
      });
    },
  );

  group('overview routes (deep links)', () {
    const paths = ['/today', '/projects', '/projects/p1', '/approvals'];

    test(
      'a worker is denied Today, Projects, project detail and Approvals',
      () {
        for (final path in paths) {
          expect(
            computeRedirect(signedIn(workerPerms), path),
            Routes.denied,
            reason: path,
          );
        }
      },
    );

    test('a supervisor may open them', () {
      for (final path in paths) {
        expect(
          computeRedirect(signedIn(supervisorPerms), path),
          isNull,
          reason: path,
        );
      }
    });

    test('an owner may open them', () {
      for (final path in paths) {
        expect(
          computeRedirect(signedIn(ownerPerms), path),
          isNull,
          reason: path,
        );
      }
    });

    test('an accountant may open finance screens but not these', () {
      for (final path in [
        '/finance',
        '/invoices',
        '/invoices/i1',
        '/quotes',
        '/quotes/q1',
        '/requests',
      ]) {
        expect(
          computeRedirect(signedIn(accountantPerms), path),
          isNull,
          reason: path,
        );
      }
      for (final path in paths) {
        expect(
          computeRedirect(signedIn(accountantPerms), path),
          Routes.denied,
          reason: path,
        );
      }
    });

    test('a supervisor lands on Today after signing in', () {
      expect(
        computeRedirect(signedIn(supervisorPerms), Routes.login),
        '/today',
      );
    });
  });

  group('PermissionEvaluator.satisfies (AND of ORs)', () {
    final p = PermissionEvaluator(['projects.view', 'tasks.*']);

    test('every group needs one satisfied key', () {
      expect(
        p.satisfies([
          ['projects.*', 'projects.view'],
          ['tasks.*'],
        ]),
        isTrue,
      );
      expect(
        p.satisfies([
          ['projects.*', 'projects.view'],
          ['timesheets.*'],
        ]),
        isFalse,
      );
    });

    test('fails closed on no groups or an empty group', () {
      expect(p.satisfies([]), isFalse);
      expect(p.satisfies([[]]), isFalse);
      expect(
        p.satisfies([
          ['tasks.*'],
          [],
        ]),
        isFalse,
      );
    });

    test('a held wildcard satisfies specific keys in each group', () {
      expect(
        PermissionEvaluator(['timesheets.*']).satisfies([
          ['timesheets.approve'],
          ['timesheets.view_all'],
        ]),
        isTrue,
      );
    });
  });
}

import 'package:builder_pro_mobile/core/permissions/feature_permissions.dart';
import 'package:builder_pro_mobile/core/permissions/permission_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionEvaluator mirrors the backend PermissionsGuard', () {
    test('exact key matches', () {
      final p = PermissionEvaluator(['tasks.view']);
      expect(p.has('tasks.view'), isTrue);
      expect(p.has('tasks.complete'), isFalse);
    });

    test('held wildcard satisfies any key in the same module', () {
      final p = PermissionEvaluator(['projects.*']);
      expect(p.has('projects.view'), isTrue);
      expect(p.has('projects.create'), isTrue);
      expect(p.has('projects.*'), isTrue);
      expect(p.has('tasks.view'), isFalse);
    });

    test('wildcard does not leak across modules sharing a prefix', () {
      final p = PermissionEvaluator(['task.*']);
      expect(p.has('tasks.view'), isFalse);
    });

    test('a REQUIRED wildcard is not satisfied by a specific held key', () {
      // Backend routes that list only `tasks.*` reject a `tasks.view` holder.
      final p = PermissionEvaluator(['tasks.view', 'tasks.complete']);
      expect(p.has('tasks.*'), isFalse);
      expect(p.hasAny(Feature.tasksCollaborate), isFalse);
    });

    test('hasAny uses OR logic, hasAll uses AND logic', () {
      final p = PermissionEvaluator(['tasks.view', 'timesheets.view_own']);
      expect(p.hasAny(['tasks.*', 'tasks.view']), isTrue);
      expect(p.hasAll(['tasks.view', 'timesheets.view_own']), isTrue);
      expect(p.hasAll(['tasks.view', 'invoices.view']), isFalse);
    });

    test('empty inputs fail closed', () {
      final p = PermissionEvaluator(['projects.*']);
      expect(p.has(''), isFalse);
      expect(p.hasAny(const []), isFalse);
      expect(p.hasAll(const []), isFalse);
      expect(PermissionEvaluator.none.has('projects.view'), isFalse);
    });

    test('default Worker role: field features yes, office features no', () {
      final worker = PermissionEvaluator([
        'projects.view',
        'tasks.view',
        'tasks.complete',
        'timesheets.view_own',
        'materials.log',
        'messaging.*',
      ]);
      expect(worker.hasAny(Feature.tasks), isTrue);
      expect(worker.hasAny(Feature.tasksComplete), isTrue);
      expect(worker.hasAny(Feature.timesheetsOwn), isTrue);
      expect(worker.hasAny(Feature.materialsLog), isTrue);
      expect(worker.hasAny(Feature.messaging), isTrue);
      expect(worker.hasAny(Feature.messagingSend), isTrue);

      expect(worker.hasAny(Feature.financials), isFalse);
      expect(worker.hasAny(Feature.invoices), isFalse);
      expect(worker.hasAny(Feature.timesheetsApprove), isFalse);
      expect(worker.hasAny(Feature.materialsManage), isFalse);
      expect(worker.hasAny(Feature.settings), isFalse);
    });

    test('owner wildcards unlock everything including required wildcards', () {
      final owner = PermissionEvaluator([
        'projects.*',
        'tasks.*',
        'timesheets.*',
        'settings.*',
        'financials.*',
      ]);
      expect(owner.hasAny(Feature.tasksCollaborate), isTrue);
      expect(owner.hasAny(Feature.timesheetsApprove), isTrue);
      expect(owner.hasAny(Feature.settings), isTrue);
      expect(owner.hasAny(Feature.financials), isTrue);
    });
  });
}

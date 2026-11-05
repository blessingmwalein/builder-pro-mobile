import 'package:builder_pro_mobile/core/auth/auth_models.dart';
import 'package:builder_pro_mobile/core/auth/session_controller.dart';
import 'package:builder_pro_mobile/core/auth/session_state.dart';

/// Default Worker role permissions from builder-pro-back SYSTEM_ROLES.
const workerPerms = [
  'projects.view',
  'tasks.view',
  'tasks.complete',
  'timesheets.view_own',
  'materials.log',
  'messaging.*',
];

const supervisorPerms = [
  'projects.view',
  'tasks.*',
  'timesheets.*',
  'materials.*',
  'messaging.*',
  'documents.*',
];

const accountantPerms = [
  'invoices.*',
  'financials.*',
  'quotes.view',
  'reports.*',
];

const ownerPerms = [
  'projects.*',
  'tasks.*',
  'timesheets.*',
  'materials.*',
  'quotes.*',
  'invoices.*',
  'financials.*',
  'employees.*',
  'settings.*',
  'crm.*',
  'reports.*',
  'messaging.*',
  'documents.*',
];

Me testMe({
  List<String> permissions = workerPerms,
  String role = 'Worker',
  String first = 'Tendai',
  String last = 'Moyo',
}) {
  return Me(
    user: UserProfile(
      id: 'u1',
      email: 'tendai@acme.test',
      firstName: first,
      lastName: last,
      roles: [RoleRef(id: 'r1', name: role)],
    ),
    tenant: const Tenant(
      id: 'c1',
      name: 'Acme Builders',
      slug: 'acme',
      defaultCurrency: 'USD',
    ),
    permissions: permissions,
  );
}

Map<String, dynamic> meJson({List<String> permissions = workerPerms}) =>
    testMe(permissions: permissions).toJson();

/// Session controller that starts in a fixed state and never touches storage/network.
class FakeSession extends SessionController {
  FakeSession(this.initial);
  final SessionState initial;

  @override
  SessionState build() => initial;

  void setState(SessionState s) => state = s;
}

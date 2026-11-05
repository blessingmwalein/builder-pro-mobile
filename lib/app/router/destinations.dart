import 'package:flutter/material.dart';

import '../../core/permissions/feature_permissions.dart';
import '../../core/permissions/permission_evaluator.dart';

/// Whose bar this is. Only an ordering hint derived from permissions; it never
/// grants access.
enum Persona {
  /// Supervisors and managers (hold a [Feature.supervise] key).
  manager,

  /// Accountants and other finance users (hold a [Feature.finance] key but no
  /// supervisory one).
  finance,

  /// Everyone else: field workers and custom roles.
  field,
}

Persona personaFor(PermissionEvaluator perms) {
  if (perms.hasAny(Feature.supervise)) return Persona.manager;
  if (perms.hasAny(Feature.finance)) return Persona.finance;
  return Persona.field;
}

/// A top-level place in the app. Visibility comes ONLY from permissions, never
/// from a role name, so custom roles work without new code.
class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    required this.branchIndex,
    required this.requires,
    required this.fieldRank,
    required this.managerRank,
    required this.financeRank,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  /// Index of this destination's branch in the shell route.
  final int branchIndex;

  /// Every group must have at least one satisfied key (AND of ORs).
  final List<List<String>> requires;

  /// Position in the bottom bar for each [Persona] (lower = nearer the thumb).
  final int fieldRank;
  final int managerRank;
  final int financeRank;

  int rankFor(Persona p) => switch (p) {
    Persona.field => fieldRank,
    Persona.manager => managerRank,
    Persona.finance => financeRank,
  };

  bool allowedFor(PermissionEvaluator perms) => perms.satisfies(requires);
}

const AppDestination clockDestination = AppDestination(
  id: 'clock',
  label: 'Clock',
  icon: Icons.timer_outlined,
  selectedIcon: Icons.timer_rounded,
  path: '/clock',
  branchIndex: 0,
  requires: [Feature.timesheetsOwn],
  fieldRank: 0,
  managerRank: 5,
  financeRank: 5,
);

const AppDestination tasksDestination = AppDestination(
  id: 'tasks',
  label: 'My Tasks',
  icon: Icons.checklist_rounded,
  selectedIcon: Icons.checklist_rounded,
  path: '/tasks',
  branchIndex: 1,
  requires: [Feature.tasks],
  fieldRank: 1,
  managerRank: 4,
  financeRank: 4,
);

const AppDestination materialsDestination = AppDestination(
  id: 'materials',
  label: 'Materials',
  icon: Icons.inventory_2_outlined,
  selectedIcon: Icons.inventory_2_rounded,
  path: '/materials',
  branchIndex: 2,
  requires: [Feature.materials],
  fieldRank: 2,
  managerRank: 6,
  financeRank: 6,
);

const AppDestination messagesDestination = AppDestination(
  id: 'messages',
  label: 'Messages',
  icon: Icons.chat_bubble_outline_rounded,
  selectedIcon: Icons.chat_bubble_rounded,
  path: '/messages',
  branchIndex: 3,
  requires: [Feature.messaging],
  fieldRank: 3,
  managerRank: 3,
  financeRank: 3,
);

const AppDestination todayDestination = AppDestination(
  id: 'today',
  label: 'Today',
  icon: Icons.dashboard_outlined,
  selectedIcon: Icons.dashboard_rounded,
  path: '/today',
  branchIndex: 4,
  requires: [Feature.supervise],
  fieldRank: 20,
  managerRank: 0,
  financeRank: 20,
);

const AppDestination projectsDestination = AppDestination(
  id: 'projects',
  label: 'Projects',
  icon: Icons.apartment_outlined,
  selectedIcon: Icons.apartment_rounded,
  path: '/projects',
  branchIndex: 5,
  requires: Feature.projectsOverview,
  fieldRank: 21,
  managerRank: 1,
  financeRank: 21,
);

const AppDestination approvalsDestination = AppDestination(
  id: 'approvals',
  label: 'Approvals',
  icon: Icons.fact_check_outlined,
  selectedIcon: Icons.fact_check_rounded,
  path: '/approvals',
  branchIndex: 6,
  requires: Feature.approvals,
  fieldRank: 22,
  managerRank: 2,
  financeRank: 22,
);

const AppDestination financeDestination = AppDestination(
  id: 'finance',
  label: 'Finance',
  icon: Icons.account_balance_wallet_outlined,
  selectedIcon: Icons.account_balance_wallet_rounded,
  path: '/finance',
  branchIndex: 7,
  // The overview shows the sections the user is allowed to see.
  requires: [
    ['financials.*', 'financials.view', 'invoices.*', 'invoices.view'],
  ],
  fieldRank: 23,
  managerRank: 10,
  financeRank: 0,
);

const AppDestination invoicesDestination = AppDestination(
  id: 'invoices',
  label: 'Invoices',
  icon: Icons.receipt_long_outlined,
  selectedIcon: Icons.receipt_long_rounded,
  path: '/invoices',
  branchIndex: 8,
  requires: [Feature.invoices],
  fieldRank: 24,
  managerRank: 11,
  financeRank: 1,
);

const AppDestination quotesDestination = AppDestination(
  id: 'quotes',
  label: 'Quotes',
  icon: Icons.request_quote_outlined,
  selectedIcon: Icons.request_quote_rounded,
  path: '/quotes',
  branchIndex: 9,
  requires: [Feature.quotes],
  fieldRank: 25,
  managerRank: 12,
  financeRank: 2,
);

const AppDestination requestsDestination = AppDestination(
  id: 'requests',
  label: 'Requests',
  icon: Icons.approval_outlined,
  selectedIcon: Icons.approval_rounded,
  path: '/requests',
  branchIndex: 10,
  requires: [Feature.requests],
  fieldRank: 26,
  managerRank: 9,
  financeRank: 7,
);

const AppDestination purchasingDestination = AppDestination(
  id: 'purchasing',
  label: 'Purchasing',
  icon: Icons.shopping_cart_outlined,
  selectedIcon: Icons.shopping_cart_rounded,
  path: '/purchasing',
  branchIndex: 11,
  requires: [Feature.purchasingView],
  fieldRank: 27,
  managerRank: 7,
  financeRank: 8,
);

const AppDestination equipmentDestination = AppDestination(
  id: 'equipment',
  label: 'Equipment',
  icon: Icons.construction_outlined,
  selectedIcon: Icons.construction_rounded,
  path: '/equipment',
  branchIndex: 12,
  requires: [Feature.equipmentView],
  fieldRank: 28,
  managerRank: 8,
  financeRank: 9,
);

const AppDestination clientsDestination = AppDestination(
  id: 'clients',
  label: 'Clients',
  icon: Icons.groups_2_outlined,
  selectedIcon: Icons.groups_2_rounded,
  path: '/clients',
  branchIndex: 13,
  requires: [Feature.crm],
  fieldRank: 29,
  managerRank: 13,
  financeRank: 10,
);

const AppDestination reportsDestination = AppDestination(
  id: 'reports',
  label: 'Reports',
  icon: Icons.insights_outlined,
  selectedIcon: Icons.insights_rounded,
  path: '/reports',
  branchIndex: 14,
  requires: [Feature.reports],
  fieldRank: 30,
  managerRank: 14,
  financeRank: 11,
);

const AppDestination teamDestination = AppDestination(
  id: 'team',
  label: 'Team',
  icon: Icons.contacts_outlined,
  selectedIcon: Icons.contacts_rounded,
  path: '/team',
  branchIndex: 15,
  requires: [Feature.team],
  fieldRank: 31,
  managerRank: 15,
  financeRank: 12,
);

const int moreBranchIndex = 16;
const String morePath = '/more';

/// Every destination the app knows. Order here does not matter; ranks decide.
const List<AppDestination> allDestinations = [
  clockDestination,
  tasksDestination,
  materialsDestination,
  messagesDestination,
  todayDestination,
  projectsDestination,
  approvalsDestination,
  financeDestination,
  invoicesDestination,
  quotesDestination,
  requestsDestination,
  purchasingDestination,
  equipmentDestination,
  clientsDestination,
  reportsDestination,
  teamDestination,
];

class NavPlan {
  const NavPlan({required this.bottom, required this.overflow});

  /// Shown in the bottom bar (the More tab is always appended by the shell).
  final List<AppDestination> bottom;

  /// Permitted but not room for in the bar; listed under More.
  final List<AppDestination> overflow;

  /// Where a user lands after sign-in.
  String get homePath => bottom.isEmpty ? morePath : bottom.first.path;
}

/// Builds the navigation for the signed-in user's effective permissions.
/// Supervisors and managers get their overview screens first, finance users get
/// the finance screens first, everyone else gets the field tabs first.
NavPlan planNavigation(PermissionEvaluator perms, {int maxBottom = 4}) {
  final persona = personaFor(perms);
  final allowed = allDestinations.where((d) => d.allowedFor(perms)).toList()
    ..sort((a, b) => a.rankFor(persona).compareTo(b.rankFor(persona)));
  return NavPlan(
    bottom: allowed.take(maxBottom).toList(),
    overflow: allowed.skip(maxBottom).toList(),
  );
}

/// Required permission groups for a location, or null when any signed-in user
/// may open it. Applies to deep links and direct navigation as well as taps.
List<List<String>>? requiredPermissionsFor(String location) {
  for (final d in allDestinations) {
    if (location == d.path || location.startsWith('${d.path}/')) {
      return d.requires;
    }
  }
  return null;
}

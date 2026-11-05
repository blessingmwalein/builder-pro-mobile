import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Project statuses the backend uses.
abstract final class ProjectStatus {
  static const draft = 'DRAFT';
  static const active = 'ACTIVE';
  static const onHold = 'ON_HOLD';
  static const completed = 'COMPLETED';
  static const archived = 'ARCHIVED';

  /// The order shown when choosing one.
  static const all = [draft, active, onHold, completed, archived];

  static String label(String status) => switch (status) {
    draft => 'Draft',
    active => 'Active',
    onHold => 'On hold',
    completed => 'Completed',
    archived => 'Archived',
    _ => status,
  };
}

/// Project types the backend accepts.
abstract final class ProjectKind {
  static const all = [
    'RESIDENTIAL',
    'COMMERCIAL',
    'RENOVATION',
    'INFRASTRUCTURE',
    'INDUSTRIAL',
    'OTHER',
  ];

  /// `RESIDENTIAL` → `Residential`.
  static String label(String type) => type.isEmpty
      ? type
      : '${type[0]}${type.substring(1).toLowerCase().replaceAll('_', ' ')}';
}

/// A person on a project team. Also the candidate list when assigning tasks.
@immutable
class PersonRef {
  const PersonRef({
    required this.id,
    required this.name,
    this.email,
    this.role,
  });

  final String id;
  final String name;
  final String? email;

  /// Role on this project (free text), not a permission.
  final String? role;

  static PersonRef? tryParse(Map<String, dynamic> member) {
    final user = J.map(member['user']);
    final id = J.str(user['id']) ?? J.str(member['userId']);
    if (id == null) return null;
    final name = '${J.strOr(user['firstName'])} ${J.strOr(user['lastName'])}'
        .trim();
    return PersonRef(
      id: id,
      name: name.isEmpty ? J.strOr(user['email'], 'Team member') : name,
      email: J.str(user['email']),
      role: J.str(member['role']),
    );
  }

  @override
  bool operator ==(Object other) => other is PersonRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A project as shown in lists and on the detail screen.
///
/// Money is deliberately NOT read here: the API returns the budget and actual
/// cost to anyone with `projects.view`, and the mobile app shows financials
/// only in the finance screens (a later phase) behind `financials.view`.
@immutable
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.status,
    this.code,
    this.projectType,
    this.siteAddress,
    this.clientName,
    this.completionPercent = 0,
    this.startDate,
    this.endDate,
    this.taskCount = 0,
    this.memberCount = 0,
    this.description,
    this.clientContact,
    this.clientPhone,
    this.clientEmail,
    this.clientId,
    this.projectManagerId,
    this.members = const [],
  });

  final String id;
  final String name;
  final String status;
  final String? code;
  final String? projectType;
  final String? siteAddress;
  final String? clientName;
  final int completionPercent;
  final DateTime? startDate;
  final DateTime? endDate;
  final int taskCount;
  final int memberCount;

  // Detail only.
  final String? description;
  final String? clientContact;
  final String? clientPhone;
  final String? clientEmail;
  final String? clientId;

  /// The user in charge of the project, when one has been assigned.
  final String? projectManagerId;
  final List<PersonRef> members;

  String get label => code == null ? name : '$code · $name';

  static ProjectSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final client = J.map(m['client']);
    final count = J.map(m['_count']);
    final members = J
        .maps(m['members'])
        .map(PersonRef.tryParse)
        .whereType<PersonRef>()
        .toList();
    return ProjectSummary(
      id: id,
      name: J.strOr(m['name'], 'Project'),
      status: J.strOr(m['status'], ProjectStatus.draft),
      code: J.str(m['code']),
      projectType: J.str(m['projectType']),
      siteAddress: J.str(m['siteAddress']),
      clientName: J.str(client['name']),
      completionPercent: (J.integer(m['completionPercent']) ?? 0).clamp(0, 100),
      startDate: J.date(m['startDate']),
      endDate: J.date(m['endDate']),
      taskCount: J.integer(count['tasks']) ?? 0,
      memberCount: J.integer(count['members']) ?? members.length,
      description: J.str(m['description']),
      clientContact: J.str(client['contactPerson']),
      clientPhone: J.str(client['phone']),
      clientEmail: J.str(client['email']),
      clientId: J.str(m['clientId']) ?? J.str(client['id']),
      projectManagerId: J.str(m['projectManagerId']),
      members: members,
    );
  }
}

@immutable
class ProjectPage {
  const ProjectPage(this.items, {required this.page, required this.hasMore});
  final List<ProjectSummary> items;
  final int page;
  final bool hasMore;
}

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// A colleague in the company directory: who they are and how to reach them.
/// Pay, ID numbers and employment records are never read (they live on the
/// employee record, not here).
@immutable
class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.roles,
    this.email,
    this.phone,
    this.lastLoginAt,
  });

  final String id;
  final String name;
  final List<String> roles;
  final String? email;
  final String? phone;
  final DateTime? lastLoginAt;

  /// `Site Supervisor, Worker`.
  String get roleLabel => roles.join(', ');

  static TeamMember? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final first = J.strOr(m['firstName']);
    final last = J.strOr(m['lastName']);
    final name = '$first $last'.trim();
    final email = J.str(m['email']);
    return TeamMember(
      id: id,
      name: name.isEmpty ? (email ?? 'Unnamed') : name,
      email: email,
      phone: J.str(m['phone']),
      lastLoginAt: J.date(m['lastLoginAt']),
      roles: J
          .maps(m['roles'])
          .map((r) => J.str(r['name']))
          .whereType<String>()
          .toList(),
    );
  }
}

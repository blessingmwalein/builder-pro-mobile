import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// `COMMERCIAL` → `Commercial`.
String clientTypeLabel(String type) {
  final t = type.trim().toLowerCase().replaceAll('_', ' ');
  return t.isEmpty ? 'Client' : t[0].toUpperCase() + t.substring(1);
}

/// A client in the list: who they are and how to reach them.
@immutable
class ClientSummary {
  const ClientSummary({
    required this.id,
    required this.name,
    required this.type,
    this.contactPerson,
    this.email,
    this.phone,
    this.projectCount = 0,
    this.quoteCount = 0,
    this.invoiceCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String type;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final int projectCount;
  final int quoteCount;
  final int invoiceCount;
  final DateTime? createdAt;

  static ClientSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    final count = J.map(m['_count']);
    return ClientSummary(
      id: id,
      name: name,
      type: J.strOr(m['clientType'], 'OTHER'),
      contactPerson: J.str(m['contactPerson']),
      email: J.str(m['email']),
      phone: J.str(m['phone']),
      projectCount:
          J.integer(count['projects']) ?? J.list(m['projects']).length,
      quoteCount: J.integer(count['quotes']) ?? J.list(m['quotes']).length,
      invoiceCount:
          J.integer(count['invoices']) ?? J.list(m['invoices']).length,
      createdAt: J.date(m['createdAt']),
    );
  }
}

/// The client types the backend uses.
abstract final class ClientType {
  static const residential = 'RESIDENTIAL';
  static const commercial = 'COMMERCIAL';
  static const government = 'GOVERNMENT';
  static const other = 'OTHER';
  static const all = [residential, commercial, government, other];
}

/// A project of a client.
@immutable
class ClientProject {
  const ClientProject({
    required this.id,
    required this.name,
    required this.status,
    this.code,
  });
  final String id;
  final String name;
  final String status;
  final String? code;

  static ClientProject? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return ClientProject(
      id: id,
      name: name,
      status: J.strOr(m['status'], 'ACTIVE'),
      code: J.str(m['code']),
    );
  }
}

/// A quote or invoice of a client. The amounts come with the client record even
/// for someone who may not read quotes or invoices (backend-gaps G42), so the
/// screens show them only to people who may.
@immutable
class ClientDocument {
  const ClientDocument({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    this.balance,
  });
  final String id;
  final String number;
  final String status;
  final double total;

  /// Invoices only.
  final double? balance;

  static ClientDocument? tryParse(
    Map<String, dynamic> m, {
    required String numberKey,
  }) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return ClientDocument(
      id: id,
      number: J.strOr(m[numberKey], 'Document'),
      status: J.strOr(m['status'], 'DRAFT'),
      total: J.number(m['totalAmount']) ?? 0,
      balance: J.number(m['balanceAmount']),
    );
  }
}

/// A client with their contact details, projects and recent quotes / invoices.
/// The financial summary the API adds up (it includes draft and void invoices,
/// G42) is not read.
@immutable
class ClientDetail {
  const ClientDetail({
    required this.summary,
    required this.projects,
    required this.quotes,
    required this.invoices,
    this.address,
    this.notes,
  });

  final ClientSummary summary;
  final String? address;
  final String? notes;
  final List<ClientProject> projects;
  final List<ClientDocument> quotes;
  final List<ClientDocument> invoices;

  static ClientDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = ClientSummary.tryParse(m);
    if (summary == null) return null;
    return ClientDetail(
      summary: summary,
      address: J.str(m['address']),
      notes: J.str(m['notes']),
      projects: J
          .maps(m['projects'])
          .map(ClientProject.tryParse)
          .whereType<ClientProject>()
          .toList(),
      quotes: J
          .maps(m['quotes'])
          .map((q) => ClientDocument.tryParse(q, numberKey: 'quoteNumber'))
          .whereType<ClientDocument>()
          .toList(),
      invoices: J
          .maps(m['invoices'])
          .map((i) => ClientDocument.tryParse(i, numberKey: 'invoiceNumber'))
          .whereType<ClientDocument>()
          .toList(),
    );
  }
}

/// Someone who has a login to the client portal for a client. They are people
/// with their own accounts, so they can be messaged in the app's chat.
@immutable
class ClientPortalUser {
  const ClientPortalUser({
    required this.userId,
    required this.name,
    required this.isActive,
    this.email,
  });

  final String userId;
  final String name;
  final bool isActive;
  final String? email;

  static ClientPortalUser? tryParse(Map<String, dynamic> m) {
    final user = J.map(m['user']);
    final id = J.str(user['id']) ?? J.str(m['userId']);
    if (id == null) return null;
    final name = '${J.strOr(user['firstName'])} ${J.strOr(user['lastName'])}'
        .trim();
    final email = J.str(user['email']);
    return ClientPortalUser(
      userId: id,
      name: name.isEmpty ? (email ?? 'Client contact') : name,
      isActive: J.boolean(m['isActive'], fallback: true),
      email: email,
    );
  }
}

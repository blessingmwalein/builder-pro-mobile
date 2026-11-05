import 'package:flutter/foundation.dart';

import '../utils/json.dart';

@immutable
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  /// Returns null when the body is not a valid token pair.
  static AuthTokens? tryParse(Object? body) {
    final m = J.map(body);
    final a = J.str(m['accessToken']);
    final r = J.str(m['refreshToken']);
    if (a == null || r == null) return null;
    return AuthTokens(accessToken: a, refreshToken: r);
  }
}

@immutable
class RoleRef {
  const RoleRef({required this.id, required this.name});
  final String id;
  final String name;

  factory RoleRef.fromJson(Map<String, dynamic> j) =>
      RoleRef(id: J.strOr(j['id']), name: J.strOr(j['name']));
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.avatarUrl,
    this.roles = const [],
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? avatarUrl;
  final List<RoleRef> roles;

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? email : n;
  }

  String get initials {
    final a = firstName.isNotEmpty ? firstName[0] : '';
    final b = lastName.isNotEmpty ? lastName[0] : '';
    final s = (a + b).toUpperCase();
    return s.isEmpty ? (email.isEmpty ? '?' : email[0].toUpperCase()) : s;
  }

  /// Display label only. Authorisation never depends on role names.
  String get roleLabel =>
      roles.isEmpty ? '' : roles.map((r) => r.name).join(', ');

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: J.strOr(j['id']),
    email: J.strOr(j['email']),
    firstName: J.strOr(j['firstName']),
    lastName: J.strOr(j['lastName']),
    phone: J.str(j['phone']),
    avatarUrl: J.str(j['avatarUrl']),
    roles: J.maps(j['roles']).map(RoleRef.fromJson).toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    'phone': phone,
    'avatarUrl': avatarUrl,
    'roles': roles.map((r) => r.toJson()).toList(),
  };
}

@immutable
class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    this.defaultCurrency = 'USD',
    this.timezone = 'Africa/Harare',
    this.countryCode = 'ZW',
    this.isActive = true,
  });

  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final String defaultCurrency;
  final String timezone;
  final String countryCode;
  final bool isActive;

  factory Tenant.fromJson(Map<String, dynamic> j) => Tenant(
    id: J.strOr(j['id']),
    name: J.strOr(j['name']),
    slug: J.strOr(j['slug']),
    logoUrl: J.str(j['logoUrl']),
    defaultCurrency: J.strOr(j['defaultCurrency'], 'USD'),
    timezone: J.strOr(j['timezone'], 'Africa/Harare'),
    countryCode: J.strOr(j['countryCode'], 'ZW'),
    isActive: J.boolean(j['isActive'], fallback: true),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'logoUrl': logoUrl,
    'defaultCurrency': defaultCurrency,
    'timezone': timezone,
    'countryCode': countryCode,
    'isActive': isActive,
  };
}

/// `GET /auth/me`: the signed-in user, their company and effective permissions.
@immutable
class Me {
  const Me({
    required this.user,
    required this.tenant,
    required this.permissions,
  });

  final UserProfile user;
  final Tenant tenant;
  final List<String> permissions;

  /// Returns null if the payload lacks a user id (treated as malformed).
  static Me? tryParse(Object? body) {
    final m = J.map(body);
    final user = UserProfile.fromJson(J.map(m['user']));
    if (user.id.isEmpty) return null;
    return Me(
      user: user,
      tenant: Tenant.fromJson(J.map(m['tenant'])),
      permissions: J.list(m['permissions']).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'tenant': tenant.toJson(),
    'permissions': permissions,
  };
}

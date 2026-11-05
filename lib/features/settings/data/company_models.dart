import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

String? _text(Object? v) {
  final s = J.str(v)?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// Business settings as `GET /companies/me` returns them; anything missing takes
/// the server's own default, as the web app does.
@immutable
class CompanySettings {
  const CompanySettings({
    required this.currency,
    required this.taxRate,
    required this.taxName,
    required this.invoicePrefix,
    required this.invoiceNextNumber,
    required this.quotePrefix,
    required this.quoteNextNumber,
    required this.purchaseOrderPrefix,
    required this.purchaseOrderNext,
    required this.approvalRequired,
    required this.notificationsEnabled,
  });

  static const defaults = CompanySettings(
    currency: 'USD',
    taxRate: 15,
    taxName: 'VAT',
    invoicePrefix: 'INV',
    invoiceNextNumber: 1,
    quotePrefix: 'QUO',
    quoteNextNumber: 1,
    purchaseOrderPrefix: 'PO',
    purchaseOrderNext: 1,
    approvalRequired: false,
    notificationsEnabled: true,
  );

  /// Currencies the web app offers.
  static const currencies = ['USD', 'ZWG', 'ZAR', 'EUR', 'GBP'];

  final String currency;
  final double taxRate;
  final String taxName;
  final String invoicePrefix;
  final int invoiceNextNumber;
  final String quotePrefix;
  final int quoteNextNumber;
  final String purchaseOrderPrefix;
  final int purchaseOrderNext;
  final bool approvalRequired;
  final bool notificationsEnabled;

  static String numberFormat(String prefix, int next) =>
      '$prefix-${next.toString().padLeft(4, '0')}';

  String get invoiceFormat => numberFormat(invoicePrefix, invoiceNextNumber);
  String get quoteFormat => numberFormat(quotePrefix, quoteNextNumber);
  String get purchaseOrderFormat =>
      numberFormat(purchaseOrderPrefix, purchaseOrderNext);

  static CompanySettings parse(Object? raw) {
    final m = J.map(raw);
    const d = defaults;
    return CompanySettings(
      currency: _text(m['currency']) ?? d.currency,
      taxRate: J.number(m['taxRate']) ?? d.taxRate,
      taxName: _text(m['taxName']) ?? d.taxName,
      invoicePrefix: _text(m['invoicePrefix']) ?? d.invoicePrefix,
      invoiceNextNumber:
          J.integer(m['invoiceNextNumber']) ?? d.invoiceNextNumber,
      quotePrefix: _text(m['quotePrefix']) ?? d.quotePrefix,
      quoteNextNumber: J.integer(m['quoteNextNumber']) ?? d.quoteNextNumber,
      purchaseOrderPrefix:
          _text(m['purchaseOrderPrefix']) ?? d.purchaseOrderPrefix,
      purchaseOrderNext:
          J.integer(m['purchaseOrderNext']) ?? d.purchaseOrderNext,
      approvalRequired: J.boolean(
        m['approvalRequired'],
        fallback: d.approvalRequired,
      ),
      notificationsEnabled: J.boolean(
        m['notificationsEnabled'],
        fallback: d.notificationsEnabled,
      ),
    );
  }
}

/// A sector or project type the company works in.
@immutable
class CompanyTag {
  const CompanyTag({required this.id, required this.name});
  final String id;
  final String name;

  static CompanyTag? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = _text(m['name']);
    return id == null || name == null ? null : CompanyTag(id: id, name: name);
  }
}

/// Someone the company deals with (a stakeholder), and the team role they hold.
@immutable
class CompanyStakeholder {
  const CompanyStakeholder({
    required this.id,
    required this.name,
    this.type,
    this.roleName,
  });
  final String id;
  final String name;
  final String? type;
  final String? roleName;

  static CompanyStakeholder? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = _text(m['name']);
    if (id == null || name == null) return null;
    return CompanyStakeholder(
      id: id,
      name: name,
      type: _text(m['type']),
      roleName: _text(J.map(m['role'])['name']),
    );
  }
}

@immutable
class CompanyWorkflow {
  const CompanyWorkflow({
    required this.id,
    required this.name,
    required this.isEnabled,
    this.stages,
  });
  final String id;
  final String name;
  final bool isEnabled;

  /// How many stages it has, when the server says.
  final int? stages;

  static CompanyWorkflow? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = _text(m['name']);
    if (id == null || name == null) return null;
    final stages = m['stages'];
    return CompanyWorkflow(
      id: id,
      name: name,
      isEnabled: J.boolean(m['isEnabled'], fallback: true),
      stages: stages is List ? stages.length : null,
    );
  }
}

/// The extra profile a sole trader (an INDIVIDUAL account) has instead of a
/// company's own fields.
@immutable
class IndividualBusiness {
  const IndividualBusiness({
    this.businessName,
    this.description,
    this.primarySector,
    this.businessSize,
    this.phone,
    this.businessEmail,
    this.registrationNumber,
    this.taxNumber,
    this.city,
    this.yearsOperating,
  });

  final String? businessName;
  final String? description;
  final String? primarySector;
  final String? businessSize;
  final String? phone;
  final String? businessEmail;
  final String? registrationNumber;
  final String? taxNumber;
  final String? city;
  final int? yearsOperating;

  /// Sizes the web app offers a sole trader.
  static const sizes = ['1-3', '4-10', '10-20'];

  static IndividualBusiness? parse(Object? raw) {
    final m = J.map(raw);
    if (m.isEmpty) return null;
    return IndividualBusiness(
      businessName: _text(m['businessName']),
      description: _text(m['description']),
      primarySector: _text(m['primarySector']),
      businessSize: _text(m['businessSize']),
      phone: _text(m['phone']),
      businessEmail: _text(m['businessEmail']),
      registrationNumber: _text(m['registrationNumber']),
      taxNumber: _text(m['taxNumber']),
      city: _text(m['city']),
      yearsOperating: J.integer(m['yearsOperating']),
    );
  }
}

/// The whole company profile, from `GET /companies/me` (needs `settings.*`).
/// Where a sole trader has not filled in the company's own field, the same
/// detail from their business profile is shown, as on the web.
@immutable
class CompanyProfile {
  const CompanyProfile({
    required this.id,
    required this.name,
    required this.slug,
    required this.accountType,
    required this.settings,
    required this.sectors,
    required this.projectTypes,
    required this.stakeholders,
    required this.workflows,
    this.logoUrl,
    this.description,
    this.website,
    this.businessPhone,
    this.businessEmail,
    this.city,
    this.legalName,
    this.registrationNumber,
    this.taxNumber,
    this.companySize,
    this.yearsOperating,
    this.individual,
  });

  final String id;
  final String name;
  final String slug;

  /// `COMPANY` or `INDIVIDUAL`.
  final String accountType;
  final String? logoUrl;
  final String? description;
  final String? website;
  final String? businessPhone;
  final String? businessEmail;
  final String? city;
  final String? legalName;
  final String? registrationNumber;
  final String? taxNumber;
  final String? companySize;
  final int? yearsOperating;
  final CompanySettings settings;
  final IndividualBusiness? individual;
  final List<CompanyTag> sectors;
  final List<CompanyTag> projectTypes;
  final List<CompanyStakeholder> stakeholders;
  final List<CompanyWorkflow> workflows;

  bool get isIndividual => accountType == 'INDIVIDUAL';

  /// The name people know the business by.
  String get displayName =>
      isIndividual ? (individual?.businessName ?? name) : name;

  String? get shownDescription => description ?? individual?.description;
  String? get shownPhone => businessPhone ?? individual?.phone;
  String? get shownEmail => businessEmail ?? individual?.businessEmail;
  String? get shownCity => city ?? individual?.city;
  String? get shownRegistration =>
      registrationNumber ?? individual?.registrationNumber;
  String? get shownTax => taxNumber ?? individual?.taxNumber;
  int? get shownYears => yearsOperating ?? individual?.yearsOperating;

  /// The size's own words: `SMALL` is shown as `Small`.
  String? get companySizeLabel => labelForSize(companySize);

  static String? labelForSize(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  /// Sizes the web app offers a company.
  static const companySizes = ['MICRO', 'SMALL', 'MEDIUM', 'LARGE'];

  static CompanyProfile? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = _text(m['name']);
    if (id == null || name == null) return null;
    return CompanyProfile(
      id: id,
      name: name,
      slug: J.strOr(m['slug']),
      accountType: J.strOr(m['accountType'], 'COMPANY'),
      logoUrl: _text(m['logoUrl']),
      description: _text(m['description']),
      website: _text(m['website']),
      businessPhone: _text(m['businessPhone']),
      businessEmail: _text(m['businessEmail']),
      city: _text(m['city']),
      legalName: _text(m['legalName']),
      registrationNumber: _text(m['registrationNumber']),
      taxNumber: _text(m['taxNumber']),
      companySize: _text(m['companySize']),
      yearsOperating: J.integer(m['yearsOperating']),
      settings: CompanySettings.parse(m['settings']),
      individual: IndividualBusiness.parse(m['individualProfile']),
      sectors: J
          .maps(m['sectors'])
          .map(CompanyTag.tryParse)
          .whereType<CompanyTag>()
          .toList(),
      projectTypes: J
          .maps(m['projectTypes'])
          .map(CompanyTag.tryParse)
          .whereType<CompanyTag>()
          .toList(),
      stakeholders: J
          .maps(m['stakeholders'])
          .map(CompanyStakeholder.tryParse)
          .whereType<CompanyStakeholder>()
          .toList(),
      workflows: J
          .maps(m['workflows'])
          .map(CompanyWorkflow.tryParse)
          .whereType<CompanyWorkflow>()
          .toList(),
    );
  }
}

/// A change to the company: only the fields that were changed are sent, so
/// nothing else is overwritten. A text field is cleared by sending it empty; the
/// years operating can be changed to another number but not emptied (the server
/// takes a missing number as "no change").
@immutable
class CompanyChange {
  const CompanyChange({
    this.name,
    this.description,
    this.website,
    this.businessPhone,
    this.businessEmail,
    this.city,
    this.legalName,
    this.registrationNumber,
    this.taxNumber,
    this.companySize,
    this.yearsOperating,
    this.settings,
    this.individual,
  });

  final String? name;
  final String? description;
  final String? website;
  final String? businessPhone;
  final String? businessEmail;
  final String? city;
  final String? legalName;
  final String? registrationNumber;
  final String? taxNumber;
  final String? companySize;
  final int? yearsOperating;

  /// Business settings fields that changed (already named as the server names
  /// them).
  final Map<String, Object?>? settings;

  /// Sole-trader profile fields that changed.
  final Map<String, Object?>? individual;

  bool get isEmpty => toBody().isEmpty;

  Map<String, Object?> toBody() => {
    'name': ?name,
    'description': ?description,
    'website': ?website,
    'businessPhone': ?businessPhone,
    'businessEmail': ?businessEmail,
    'city': ?city,
    'legalName': ?legalName,
    'registrationNumber': ?registrationNumber,
    'taxNumber': ?taxNumber,
    'companySize': ?companySize,
    'yearsOperating': ?yearsOperating,
    if (settings != null && settings!.isNotEmpty) 'settings': settings,
    if (individual != null && individual!.isNotEmpty)
      'individualProfile': individual,
  };
}

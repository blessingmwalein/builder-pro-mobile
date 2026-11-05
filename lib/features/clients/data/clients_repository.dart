import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'client_models.dart';

/// What the add / edit client form collects.
class ClientInput {
  const ClientInput({
    required this.name,
    required this.type,
    this.contactPerson,
    this.email,
    this.phone,
    this.address,
    this.notes,
  });

  final String name;
  final String type;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;

  /// A create sends only what was filled in; an update sends every field, with
  /// null for a blank one, so clearing a field works.
  Map<String, dynamic> toBody({required bool forCreate}) {
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final fields = <String, dynamic>{
      'contactPerson': clean(contactPerson),
      'email': clean(email),
      'phone': clean(phone),
      'address': clean(address),
      'notes': clean(notes),
    };
    if (forCreate) fields.removeWhere((_, v) => v == null);
    return {'name': name.trim(), 'clientType': type, ...fields};
  }
}

/// `/crm/clients`.
class ClientsRepository {
  ClientsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// Newest first. [search] matches the name or the email.
  Future<PageResult<ClientSummary>> list({String? search, int page = 1}) async {
    final body = await _api.get(
      'crm/clients',
      query: {'page': page, 'limit': pageSize, 'search': search?.trim()},
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(ClientSummary.tryParse)
          .whereType<ClientSummary>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// Adds a client. NOT repeatable: a repeat adds another.
  Future<ClientSummary> create(ClientInput input) async {
    final body = await _api.post(
      'crm/clients',
      body: input.toBody(forCreate: true),
    );
    final created = ClientSummary.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The client may have been added.',
      );
    }
    return created;
  }

  /// Sets every field of a client (a blank clears it). It only sets fields, so
  /// it may be sent once more after an uncertain failure.
  Future<void> update(String id, ClientInput input) async {
    await _api.put('crm/clients/$id', body: input.toBody(forCreate: false));
  }

  Future<ClientDetail> get(String id) async {
    final d = ClientDetail.tryParse(await _api.get('crm/clients/$id'));
    if (d == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected client response.',
      );
    }
    return d;
  }

  /// The people with a portal login for [clientId]:
  /// `GET /crm/clients/:id/portal-users` (needs the full `crm.*` key).
  Future<List<ClientPortalUser>> portalUsers(String clientId) async {
    final body = await _api.get('crm/clients/$clientId/portal-users');
    return J
        .maps(body is List ? body : J.list(J.map(body)['items']))
        .map(ClientPortalUser.tryParse)
        .whereType<ClientPortalUser>()
        .toList();
  }
}

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'material_models.dart';
import 'material_purchase_models.dart';
import 'material_reference_models.dart';

/// `/materials/*` for logging material use on site.
class MaterialsRepository {
  MaterialsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /materials`. `page` and `limit` are always sent: the backend answers
  /// 500 for some list endpoints when they are missing.
  Future<MaterialPage> list({String? search, int page = 1}) async {
    final body = await _api.get(
      'materials',
      query: {'page': page, 'limit': pageSize, 'search': search?.trim()},
    );
    final paged = J.paged(body);
    return MaterialPage(
      paged.items.map(MaterialItem.tryParse).whereType<MaterialItem>().toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// `GET /materials/categories/list`: the company's categories, the same ones
  /// the web app uses (the server adds the standard ones on first read).
  Future<List<MaterialCategoryRef>> categories() async {
    final body = await _api.get('materials/categories/list');
    return J
        .list(body)
        .map(MaterialCategoryRef.tryParse)
        .whereType<MaterialCategoryRef>()
        .toList();
  }

  /// `POST /materials/categories` (needs `materials.manage_inventory`). A code
  /// that already exists is refused by the server.
  Future<MaterialCategoryRef> createCategory(String name) async {
    final body = await _api.post(
      'materials/categories',
      body: {'name': name.trim(), 'code': categoryCodeFor(name)},
    );
    final created = MaterialCategoryRef.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The category may have been added.',
      );
    }
    return created;
  }

  /// `GET /materials/suppliers/list`, read page by page up to [maxPages] (a
  /// company's suppliers are few). The server adds a few standard suppliers the
  /// first time it is read.
  Future<List<Supplier>> suppliers({int maxPages = 5}) async {
    final all = <Supplier>[];
    for (var page = 1; page <= maxPages; page++) {
      final body = await _api.get(
        'materials/suppliers/list',
        query: {'page': page, 'limit': 50},
      );
      final paged = J.paged(body);
      final known = all.map((s) => s.id).toSet();
      all.addAll(
        paged.items
            .map(Supplier.tryParse)
            .whereType<Supplier>()
            .where((s) => !known.contains(s.id)),
      );
      if (!paged.hasMore) break;
    }
    return all;
  }

  /// `POST /materials/suppliers` (needs `materials.manage_inventory`). Names are
  /// unique per company, so a repeat is refused by the server.
  Future<Supplier> createSupplier(SupplierInput input) async {
    final created = Supplier.tryParse(
      await _api.post('materials/suppliers', body: input.toBody()),
    );
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The supplier may have been added.',
      );
    }
    return created;
  }

  /// `POST /materials` (needs `materials.manage_inventory`). NOT repeatable.
  Future<MaterialItem> createMaterial(MaterialInput input) async {
    final created = MaterialItem.tryParse(
      J.map(await _api.post('materials', body: input.toCreateBody())),
    );
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The material may have been added.',
      );
    }
    return created;
  }

  /// `PUT /materials/:id` (needs `materials.manage_inventory`). Sets the given
  /// fields, so it is safe to repeat. A changed price needs a reason.
  Future<void> updateMaterial(String id, MaterialInput input) async {
    await _api.put('materials/$id', body: input.toUpdateBody());
  }

  /// `GET /materials/:id`: one material as it is now.
  Future<MaterialItem> material(String id) async {
    final m = MaterialItem.tryParse(J.map(await _api.get('materials/$id')));
    if (m == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected material response.',
      );
    }
    return m;
  }

  /// Sets the stock on hand to a counted quantity (`PUT /materials/:id`, needs
  /// `materials.manage_inventory`). It sets, not adds, so the server records the
  /// difference with [reason] as a stock correction in its audit trail. The
  /// `stock-adjust` endpoint is not used: it adds a quantity with no reason, so
  /// a repeat would count twice.
  Future<void> setStock(String id, double counted, String reason) async {
    await _api.put(
      'materials/$id',
      body: {'stockOnHand': counted, 'reason': reason.trim()},
    );
  }

  /// `POST /materials/purchases` (needs `materials.manage_inventory`). Adds each
  /// quantity to stock, sets each material's price to what was paid, and (with a
  /// project) records the cost in its Materials budget. NOT repeatable.
  Future<MaterialPurchase> createPurchase(NewPurchaseInput input) async {
    final number = input.purchaseNumber?.trim();
    final notes = input.notes?.trim();
    final body = await _api.post(
      'materials/purchases',
      body: {
        'supplierId': input.supplierId,
        'projectId': ?input.projectId,
        if (number != null && number.isNotEmpty) 'purchaseNumber': number,
        'purchasedAt': input.purchasedAt.toUtc().toIso8601String(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'items': [
          for (final i in input.items)
            {
              'materialId': i.materialId,
              'quantity': i.quantity,
              'unitCost': i.unitCost,
            },
        ],
      },
    );
    final created = MaterialPurchase.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The purchase may have been recorded.',
      );
    }
    return created;
  }

  /// `GET /materials/purchases/list`, newest first.
  Future<PageResult<MaterialPurchase>> purchases({
    int page = 1,
    int limit = pageSize,
    String? supplierId,
    String? projectId,
  }) async {
    final body = await _api.get(
      'materials/purchases/list',
      query: {
        'page': page,
        'limit': limit,
        'supplierId': supplierId,
        'projectId': projectId,
      },
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(MaterialPurchase.tryParse)
          .whereType<MaterialPurchase>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// `POST /materials/usage`. Reduces stock and adds project cost, and has no
  /// idempotency key: callers confirm with the user and never repeat it blindly.
  ///
  /// [usedAt] is for usage saved on a phone with no signal: the exact moment it
  /// was used, to the millisecond. The server stores it, which is how an
  /// earlier attempt that got no answer can be found again before the usage is
  /// sent a second time, and a current server recognises the repeat itself.
  Future<MaterialLogEntry> logUsage({
    required MaterialItem material,
    required String projectId,
    required String projectName,
    required double quantity,
    String? notes,
    DateTime? usedAt,
  }) async {
    final body = await _api.post(
      'materials/usage',
      body: {
        'projectId': projectId,
        'materialId': material.id,
        'quantity': quantity,
        // Required by the API; taken from the catalog, not typed by the worker.
        'unitCost': material.unitCost,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'usedAt': ?usedAt?.toUtc().toIso8601String(),
      },
    );
    final log = MaterialLogEntry.tryParse(
      J.map(body),
      fallbackMaterialName: material.name,
      fallbackUnit: material.unit,
      fallbackProjectName: projectName,
    );
    if (log == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The usage may have been recorded.',
      );
    }
    return log;
  }

  /// Latest usage logs for one project + material, used to check whether an
  /// attempt that timed out was actually recorded.
  Future<List<MaterialLogEntry>> recentLogs({
    required String projectId,
    required String materialId,
    int limit = 5,
  }) async {
    final body = await _api.get(
      'materials/logs',
      query: {
        'page': 1,
        'limit': limit,
        'projectId': projectId,
        'materialId': materialId,
      },
    );
    return J
        .paged(body)
        .items
        .map((m) => MaterialLogEntry.tryParse(m))
        .whereType<MaterialLogEntry>()
        .toList();
  }
}

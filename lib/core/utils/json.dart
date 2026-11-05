/// Tolerant JSON accessors. The BuilderPro API serialises Prisma decimals as
/// strings, omits bodies on some 200 responses and returns plain arrays on some
/// list endpoints, so models never cast raw values directly.
abstract final class J {
  static Map<String, dynamic> map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return const {};
  }

  static List<dynamic> list(Object? v) => v is List ? v : const [];

  static List<Map<String, dynamic>> maps(Object? v) =>
      list(v).whereType<Object>().map(map).where((m) => m.isNotEmpty).toList();

  static String? str(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static String strOr(Object? v, [String fallback = '']) => str(v) ?? fallback;

  static int? integer(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
    return null;
  }

  static double? number(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool boolean(Object? v, {bool fallback = false}) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  static DateTime? date(Object? v) {
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  /// Parses `{ items: [...], meta: {page, limit, total} }`, also tolerating a
  /// bare array and string numbers inside `meta`.
  static PagedJson paged(Object? body) {
    if (body is List) {
      return PagedJson(maps(body), 1, body.length, body.length);
    }
    final m = map(body);
    final meta = map(m['meta']);
    final items = maps(m['items']);
    return PagedJson(
      items,
      integer(meta['page']) ?? integer(m['page']) ?? 1,
      integer(meta['limit']) ?? integer(m['limit']) ?? items.length,
      integer(meta['total']) ?? integer(m['total']) ?? items.length,
    );
  }
}

class PagedJson {
  const PagedJson(this.items, this.page, this.limit, this.total);
  final List<Map<String, dynamic>> items;
  final int page;
  final int limit;
  final int total;

  bool get hasMore => page * limit < total;
}

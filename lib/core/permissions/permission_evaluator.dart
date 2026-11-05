/// Central permission check. Mirrors `PermissionsGuard` in builder-pro-back
/// (`src/common/guards/permissions.guard.ts`) exactly:
///
/// * A held key matches a required key when they are equal.
/// * A held wildcard `module.*` additionally satisfies any required `module.xxx`.
/// * A *required* wildcard (e.g. `tasks.*`) is satisfied only by holding `tasks.*`;
///   holding `tasks.view` is not enough.
/// * A list of required keys uses OR logic.
///
/// Anything unknown fails closed. This only decides what the UI offers; the
/// backend independently authorises every request.
class PermissionEvaluator {
  PermissionEvaluator(Iterable<String> held) : held = Set.unmodifiable(held);

  const PermissionEvaluator._empty() : held = const {};

  static const PermissionEvaluator none = PermissionEvaluator._empty();

  final Set<String> held;

  bool get isEmpty => held.isEmpty;

  bool has(String required) {
    if (required.isEmpty) return false;
    for (final h in held) {
      if (h == required) return true;
      if (h.endsWith('.*')) {
        final prefix = h.substring(0, h.length - 1); // "projects."
        if (required.startsWith(prefix)) return true;
      }
    }
    return false;
  }

  /// True when ANY of [required] is satisfied. An empty list fails closed; use
  /// an explicit "authenticated only" flag for screens with no requirement.
  bool hasAny(Iterable<String> required) => required.any(has);

  bool hasAll(Iterable<String> required) {
    final list = required.toList();
    return list.isNotEmpty && list.every(has);
  }

  /// True when EVERY group has at least one satisfied key (AND of ORs), e.g.
  /// "can view projects AND supervises work". No groups, or an empty group,
  /// fails closed.
  bool satisfies(List<List<String>> groups) =>
      groups.isNotEmpty && groups.every((g) => g.isNotEmpty && hasAny(g));
}

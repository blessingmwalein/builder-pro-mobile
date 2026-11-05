import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/materials_providers.dart';
import '../data/material_models.dart';
import '../data/material_reference_models.dart';
import '../data/material_units.dart';
import '../../../shared/components/name_dialog.dart';

/// Chooses a unit from the construction units (grouped), keeping whatever unit
/// is already in use available. Null when dismissed.
Future<String?> chooseUnit(BuildContext context, {String? current}) async {
  final picked = await pickOne<String>(
    context,
    title: 'Unit',
    selected: current,
    options: [
      for (final u in unitChoices(current: current))
        PickerOption(value: u, title: u, subtitle: unitGroup(u)),
    ],
  );
  return picked?.value;
}

/// One thing the sheet can offer above the list: make a new item. Returns the
/// new item, or null when nothing was made.
class PickAction<T> {
  const PickAction({
    required this.label,
    required this.icon,
    required this.run,
  });
  final String label;
  final IconData icon;
  final Future<T?> Function(BuildContext context) run;
}

/// A short list to choose from, with a search box and optional "add" rows.
/// Returns null when dismissed; a result with a null value means "none".
Future<({T? value})?> pickFromList<T>(
  BuildContext context, {
  required String title,
  required Future<List<T>> Function() load,
  required String Function(T) titleOf,
  required bool Function(T, String query) matches,
  required bool Function(T) isSelected,
  String? Function(T)? subtitleOf,
  String? noneLabel,
  List<PickAction<T>> actions = const [],
  String emptyMessage = 'Nothing to choose from yet.',
}) {
  return showModalBottomSheet<({T? value})>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ListSheet<T>(
      title: title,
      load: load,
      titleOf: titleOf,
      subtitleOf: subtitleOf,
      matches: matches,
      isSelected: isSelected,
      noneLabel: noneLabel,
      actions: actions,
      emptyMessage: emptyMessage,
    ),
  );
}

class _ListSheet<T> extends StatefulWidget {
  const _ListSheet({
    required this.title,
    required this.load,
    required this.titleOf,
    required this.matches,
    required this.isSelected,
    required this.actions,
    required this.emptyMessage,
    this.subtitleOf,
    this.noneLabel,
  });

  final String title;
  final Future<List<T>> Function() load;
  final String Function(T) titleOf;
  final String? Function(T)? subtitleOf;
  final bool Function(T, String) matches;
  final bool Function(T) isSelected;
  final String? noneLabel;
  final List<PickAction<T>> actions;
  final String emptyMessage;

  @override
  State<_ListSheet<T>> createState() => _ListSheetState<T>();
}

class _ListSheetState<T> extends State<_ListSheet<T>> {
  final _search = TextEditingController();
  List<T>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = await widget.load();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    final query = _search.text.trim();
    final shown = items == null
        ? const <dynamic>[]
        : [
            for (final i in items)
              if (widget.matches(i, query)) i,
          ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xxl,
                Space.sm,
                Space.xxl,
                Space.md,
              ),
              child: Text(
                widget.title,
                style: AppType.sectionTitle.copyWith(color: c.text),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
              child: AppTextField(
                label: 'Search',
                controller: _search,
                prefixIcon: Icons.search_rounded,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Space.sm),
            Flexible(
              child: _error != null
                  ? ErrorPanel(error: _error!, compact: true, onRetry: _load)
                  : items == null
                  ? const Padding(
                      padding: EdgeInsets.all(Space.xxl),
                      child: SkeletonList(rows: 3, rowHeight: 56),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final a in widget.actions)
                          _Row(
                            icon: a.icon,
                            title: a.label,
                            accent: true,
                            onTap: () async {
                              final made = await a.run(context);
                              if (made != null && context.mounted) {
                                Navigator.of(context).pop((value: made));
                              }
                            },
                          ),
                        if (widget.noneLabel != null)
                          _Row(
                            icon: Icons.block_rounded,
                            title: widget.noneLabel!,
                            onTap: () =>
                                Navigator.of(context).pop((value: null)),
                          ),
                        if (shown.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Space.xxl),
                            child: Text(
                              query.isEmpty
                                  ? widget.emptyMessage
                                  : 'Nothing matches "$query".',
                              style: AppType.body.copyWith(color: c.textMuted),
                            ),
                          ),
                        for (final item in shown)
                          _Row(
                            title: widget.titleOf(item as T),
                            subtitle: widget.subtitleOf?.call(item),
                            selected: widget.isSelected(item),
                            onTap: () =>
                                Navigator.of(context).pop((value: item)),
                          ),
                        const SizedBox(height: Space.lg),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.accent = false,
    this.selected = false,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.touchTarget + 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.xxl,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: accent ? c.primary : c.textMuted),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.bodyStrong.copyWith(
                        color: accent ? c.primary : c.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_rounded, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chooses a supplier, optionally adding a new one (or none at all).
Future<({Supplier? value})?> chooseSupplier(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  bool allowAdd = false,
  bool allowNone = false,
  String title = 'Supplier',
}) {
  return pickFromList<Supplier>(
    context,
    title: title,
    load: () => ref.read(suppliersProvider.future),
    titleOf: (s) => s.name,
    subtitleOf: (s) => [
      if (s.phone != null) s.phone!,
      if (s.email != null) s.email!,
    ].join(' · '),
    matches: (s, q) =>
        q.isEmpty || s.name.toLowerCase().contains(q.toLowerCase()),
    isSelected: (s) => s.id == selectedId,
    noneLabel: allowNone ? 'No supplier' : null,
    emptyMessage: 'No suppliers yet.',
    actions: [
      if (allowAdd)
        PickAction<Supplier>(
          label: 'Add a supplier',
          icon: Icons.add_business_outlined,
          run: (ctx) => ctx.push<Supplier>('/materials/suppliers/new'),
        ),
    ],
  );
}

/// Chooses a material category, optionally adding a new one.
Future<({MaterialCategoryRef? value})?> chooseCategory(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  bool allowAdd = false,
}) {
  return pickFromList<MaterialCategoryRef>(
    context,
    title: 'Category',
    load: () => ref.read(materialCategoriesProvider.future),
    titleOf: (c) => c.name,
    matches: (c, q) =>
        q.isEmpty || c.name.toLowerCase().contains(q.toLowerCase()),
    isSelected: (c) => c.id == selectedId,
    noneLabel: 'No category',
    emptyMessage: 'No categories yet.',
    actions: [
      if (allowAdd)
        PickAction<MaterialCategoryRef>(
          label: 'Add a category',
          icon: Icons.add_rounded,
          run: (ctx) => _askNewCategory(ctx, ref),
        ),
    ],
  );
}

Future<MaterialCategoryRef?> _askNewCategory(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = await askForName(
    context,
    title: 'New category',
    label: 'Category name',
    hint: 'e.g. Plumbing',
  );
  if (name == null || !context.mounted) return null;
  try {
    final saved = await ref
        .read(materialManagementProvider)
        .createCategory(name);
    return saved.value;
  } on AppException catch (e) {
    if (context.mounted) Snack.error(context, e);
    return null;
  }
}

/// Chooses one of the company's materials (searching the whole catalog), or
/// makes a new one. Returns null when dismissed.
Future<MaterialItem?> chooseMaterial(
  BuildContext context, {
  bool allowCreate = false,
}) {
  return showModalBottomSheet<MaterialItem>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _MaterialSheet(allowCreate: allowCreate),
  );
}

class _MaterialSheet extends ConsumerStatefulWidget {
  const _MaterialSheet({required this.allowCreate});
  final bool allowCreate;

  @override
  ConsumerState<_MaterialSheet> createState() => _MaterialSheetState();
}

class _MaterialSheetState extends ConsumerState<_MaterialSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  var _items = <MaterialItem>[];
  var _page = 0;
  var _hasMore = false;
  var _loading = true;
  var _loadingMore = false;
  AppException? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(materialsRepositoryProvider)
          .list(search: query.trim().isEmpty ? null : query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = page.items;
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(materialsRepositoryProvider)
          .list(
            search: _search.text.trim().isEmpty ? null : _search.text,
            page: _page + 1,
          );
      if (!mounted || gen != _generation) return;
      final known = _items.map((m) => m.id).toSet();
      setState(() {
        _items = [..._items, ...page.items.where((m) => !known.contains(m.id))];
        _page = page.page;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on AppException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loadingMore = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xxl,
                Space.sm,
                Space.xxl,
                Space.md,
              ),
              child: Text(
                'Choose a material',
                style: AppType.sectionTitle.copyWith(color: c.text),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
              child: AppTextField(
                label: 'Search materials',
                controller: _search,
                hint: 'Name or code',
                prefixIcon: Icons.search_rounded,
                onChanged: (t) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 350),
                    () => _load(t),
                  );
                },
              ),
            ),
            const SizedBox(height: Space.sm),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(Space.xxl),
                      child: SkeletonList(rows: 3, rowHeight: 56),
                    )
                  : _error != null && _items.isEmpty
                  ? ErrorPanel(
                      error: _error!,
                      compact: true,
                      onRetry: () => _load(_search.text),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (widget.allowCreate)
                          _Row(
                            icon: Icons.add_box_outlined,
                            title: 'Create a new material',
                            accent: true,
                            onTap: () async {
                              final made = await context.push<MaterialItem>(
                                '/materials/new',
                              );
                              if (made != null && context.mounted) {
                                Navigator.of(context).pop(made);
                              }
                            },
                          ),
                        if (_items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Space.xxl),
                            child: Text(
                              _search.text.trim().isEmpty
                                  ? 'No materials yet.'
                                  : 'Nothing matches that.',
                              style: AppType.body.copyWith(color: c.textMuted),
                            ),
                          ),
                        for (final m in _items)
                          _Row(
                            title: m.name,
                            subtitle: [
                              if (m.sku != null) m.sku!,
                              if (m.category != null) m.category!,
                              m.unit,
                            ].where((s) => s.isNotEmpty).join(' · '),
                            onTap: () => Navigator.of(context).pop(m),
                          ),
                        if (_hasMore)
                          Padding(
                            padding: const EdgeInsets.all(Space.lg),
                            child: AppButton(
                              label: 'Show more',
                              variant: AppButtonVariant.secondary,
                              loading: _loadingMore,
                              onPressed: _more,
                            ),
                          ),
                        const SizedBox(height: Space.lg),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/states.dart';
import '../application/clients_providers.dart';
import '../data/client_models.dart';

/// Lets the person choose one of the company's clients, searching by name or
/// email (the list can be long). Returns null when dismissed.
Future<ClientSummary?> chooseClient(
  BuildContext context, {
  required String title,
}) {
  return showModalBottomSheet<ClientSummary>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ClientSheet(title: title),
  );
}

class _ClientSheet extends ConsumerStatefulWidget {
  const _ClientSheet({required this.title});
  final String title;

  @override
  ConsumerState<_ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends ConsumerState<_ClientSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  var _items = <ClientSummary>[];
  var _page = 0;
  var _hasMore = false;
  var _loading = true;
  var _loadingMore = false;
  AppException? _error;

  /// A newer search wins over a slower older one.
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
      final result = await ref
          .read(clientsRepositoryProvider)
          .list(search: query.trim().isEmpty ? null : query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = result.items;
        _page = result.page;
        _hasMore = result.hasMore;
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
      final result = await ref
          .read(clientsRepositoryProvider)
          .list(
            search: _search.text.trim().isEmpty ? null : _search.text,
            page: _page + 1,
          );
      if (!mounted || gen != _generation) return;
      final known = _items.map((c) => c.id).toSet();
      setState(() {
        _items = [
          ..._items,
          ...result.items.where((c) => !known.contains(c.id)),
        ];
        _page = result.page;
        _hasMore = result.hasMore;
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
                widget.title,
                style: AppType.sectionTitle.copyWith(color: c.text),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
              child: AppTextField(
                label: 'Search clients',
                controller: _search,
                hint: 'Name or email',
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
            const SizedBox(height: Space.md),
            Flexible(child: _body(c)),
          ],
        ),
      ),
    );
  }

  Widget _body(AppColors c) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: SkeletonList(rows: 3, rowHeight: 56),
      );
    }
    if (_error != null && _items.isEmpty) {
      return ErrorPanel(
        error: _error!,
        compact: true,
        onRetry: () => _load(_search.text),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: EmptyState(
          icon: Icons.groups_2_outlined,
          title: 'No clients found',
          message: 'Try a different name. Clients are added from the Clients screen.',
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final client in _items)
          InkWell(
            onTap: () => Navigator.of(context).pop(client),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: Sizes.touchTarget + 4,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.xxl,
                  vertical: Space.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    if (client.email != null)
                      Text(
                        client.email!,
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
            ),
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
    );
  }
}

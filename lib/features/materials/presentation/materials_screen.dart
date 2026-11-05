import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/states.dart';
import '../../sync/data/queued_write_models.dart';
import '../../sync/presentation/queued_writes_panel.dart';
import '../application/materials_providers.dart';
import '../data/material_models.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';

/// Material catalog: find an item and log how much was used on a project.
class MaterialsScreen extends ConsumerStatefulWidget {
  const MaterialsScreen({super.key});

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(materialCatalogProvider.notifier).search(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final catalog = ref.watch(materialCatalogProvider);
    final logged = ref.watch(loggedThisSessionProvider);

    return PageBody(
      onRefresh: () => ref.read(materialCatalogProvider.notifier).refresh(),
      children: [
        const PageTitle(
          'Materials',
          subtitle: 'Find an item to log what you used.',
        ),
        Row(
          children: [
            if (ref
                .watch(permissionsProvider)
                .hasAny(Feature.materialsInventory))
              Expanded(
                child: AppButton(
                  label: 'Add material',
                  icon: Icons.add_rounded,
                  onPressed: () => context.push('/materials/new'),
                ),
              ),
            if (ref
                    .watch(permissionsProvider)
                    .hasAny(Feature.materialsInventory) &&
                ref
                    .watch(permissionsProvider)
                    .hasAny(Feature.materialsReference))
              const SizedBox(width: Space.sm),
            if (ref
                .watch(permissionsProvider)
                .hasAny(Feature.materialsReference))
              Expanded(
                child: AppButton(
                  label: 'Suppliers',
                  icon: Icons.local_shipping_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push('/materials/suppliers'),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            if (ref
                .watch(permissionsProvider)
                .hasAny(Feature.materialsInventory))
              Expanded(
                child: AppButton(
                  label: 'Record purchase',
                  icon: Icons.add_shopping_cart_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push('/materials/purchases/new'),
                ),
              ),
            if (ref
                    .watch(permissionsProvider)
                    .hasAny(Feature.materialsInventory) &&
                ref
                    .watch(permissionsProvider)
                    .hasAny(Feature.materialsReference))
              const SizedBox(width: Space.sm),
            if (ref
                .watch(permissionsProvider)
                .hasAny(Feature.materialsReference))
              Expanded(
                child: AppButton(
                  label: 'Purchases',
                  icon: Icons.receipt_long_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push('/materials/purchases'),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        AppTextField(
          label: 'Search materials',
          controller: _search,
          hint: 'Name or code',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: _onSearch,
          onSubmitted: (t) =>
              ref.read(materialCatalogProvider.notifier).search(t),
        ),
        if (logged.isNotEmpty) ...[
          const SectionHeader('LOGGED ON THIS PHONE'),
          AppCard(
            child: Column(
              children: [
                for (final l in logged.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: Sizes.iconSm,
                          color: c.success,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${Fmt.quantity(l.quantity)} ${l.unit} ${l.materialName}',
                                style: AppType.bodyStrong.copyWith(
                                  color: c.text,
                                ),
                              ),
                              Text(
                                '${l.projectName} · ${Fmt.time(l.usedAt)}',
                                style: AppType.helper.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const QueuedWritesPanel(kinds: [WriteKind.materialUsage]),
        const SectionHeader('CATALOG'),
        if (catalog.fromSavedCopy)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'No connection. These are the materials saved on this phone from your earlier visits, so stock and cost may be out of date. What you log is saved and sent when there is a connection.',
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
        ..._catalog(catalog),
      ],
    );
  }

  List<Widget> _catalog(CatalogState catalog) {
    if (catalog.loading) return const [SkeletonList(rows: 5, rowHeight: 68)];
    if (catalog.error != null) {
      return [
        ErrorPanel(
          error: catalog.error!,
          compact: true,
          onRetry: () => ref.read(materialCatalogProvider.notifier).refresh(),
        ),
      ];
    }
    if (catalog.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: Space.x3),
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
            title: catalog.query.isEmpty
                ? 'No materials yet'
                : 'No materials match "${catalog.query}"',
            message: catalog.query.isEmpty
                ? 'Your company has not added materials to the catalog.'
                : 'Check the spelling or try a shorter word.',
          ),
        ),
      ];
    }
    return [
      for (final m in catalog.items)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: _MaterialRow(
            item: m,
            onTap: () => context.push('/materials/log', extra: m),
          ),
        ),
      if (catalog.loadMoreError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: ErrorPanel(
            error: catalog.loadMoreError!,
            compact: true,
            onRetry: () =>
                ref.read(materialCatalogProvider.notifier).loadMore(),
          ),
        ),
      if (catalog.hasMore && catalog.loadMoreError == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: AppButton(
            label: 'Show more',
            variant: AppButtonVariant.secondary,
            loading: catalog.loadingMore,
            onPressed: () =>
                ref.read(materialCatalogProvider.notifier).loadMore(),
          ),
        ),
      const SizedBox(height: Space.sm),
    ];
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.item, required this.onTap});
  final MaterialItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final detail = [
      if (item.sku != null) item.sku!,
      if (item.category != null) item.category!,
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Log usage of ${item.name}',
      child: Row(
        children: [
          const IconTile(Icons.inventory_2_outlined),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                Text(
                  '${Fmt.quantity(item.stockOnHand)} ${item.unit} in stock',
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}

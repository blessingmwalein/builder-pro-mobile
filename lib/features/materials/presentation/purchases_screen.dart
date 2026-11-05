import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/states.dart';
import '../../finance/application/finance_providers.dart' show currencyProvider;
import '../application/materials_providers.dart';
import '../data/material_purchase_models.dart';

/// Material bought and put into stock, newest first: what, from whom, for how
/// much, and for which project. Needs `materials.log` to read; recording one
/// needs `materials.manage_inventory`.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Purchases')),
      body: SafeArea(
        child: !perms.hasAny(Feature.materialsReference)
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot see purchases.',
              )
            : _List(canRecord: perms.hasAny(Feature.materialsInventory)),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.canRecord});
  final bool canRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(materialPurchasesProvider);
    final notifier = ref.read(materialPurchasesProvider.notifier);
    final currency = ref.watch(currencyProvider);
    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        if (canRecord) ...[
          AppButton(
            label: 'Record a purchase',
            icon: Icons.add_shopping_cart_rounded,
            onPressed: () => context.push('/materials/purchases/new'),
          ),
          const SizedBox(height: Space.lg),
        ],
        ...pagedRows<MaterialPurchase>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.shopping_bag_outlined,
          emptyTitle: 'No purchases yet',
          emptyMessage:
              'Material bought straight from a supplier is listed here.',
          rowBuilder: (p) => _PurchaseCard(purchase: p, currency: currency),
        ),
      ],
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({required this.purchase, required this.currency});
  final MaterialPurchase purchase;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = purchase;
    final facts = [
      Fmt.day(p.purchasedAt),
      if (p.number != null) p.number!,
      if (p.projectName != null) p.projectName!,
    ].join(' · ');
    return AppCard(
      semanticLabel:
          '${p.supplierName ?? 'Purchase'}, ${Fmt.money(p.total, currency)}, $facts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.supplierName ?? 'No supplier',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                Text(facts, style: AppType.helper.copyWith(color: c.textMuted)),
              ],
            ),
            end: Text(
              Fmt.money(p.total, currency),
              style: AppType.amount.copyWith(color: c.text),
            ),
          ),
          if (p.lines.isNotEmpty) ...[
            Divider(height: Space.xl, color: c.border),
            for (final l in p.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${Fmt.quantity(l.quantity)} ${l.unit} ${l.materialName} × ${Fmt.money(l.unitCost, currency)}',
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
          ],
          if (p.notes != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                p.notes!,
                style: AppType.body.copyWith(color: c.text),
              ),
            ),
        ],
      ),
    );
  }
}

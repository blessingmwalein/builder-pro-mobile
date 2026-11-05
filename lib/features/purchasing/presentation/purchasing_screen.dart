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
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';

/// Purchase requests and orders for supervisors and managers. Receiving
/// deliveries and sending orders to suppliers stay on the web app.
class PurchasingScreen extends ConsumerStatefulWidget {
  const PurchasingScreen({super.key});

  @override
  ConsumerState<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends ConsumerState<PurchasingScreen> {
  bool _orders = false;

  static const _requestFilters = <(String?, String)>[
    (null, 'All'),
    (PrStatus.submitted, 'Waiting'),
    (PrStatus.draft, 'Draft'),
    (PrStatus.approved, 'Approved'),
    (PrStatus.ordered, 'Ordered'),
    (PrStatus.rejected, 'Rejected'),
  ];

  static const _orderFilters = <(String?, String)>[
    (null, 'All'),
    ('SENT', 'Sent'),
    ('PARTIAL', 'Part received'),
    ('RECEIVED', 'Received'),
    ('DRAFT', 'Draft'),
    ('CANCELLED', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    final canCreate = perms.hasAny(Feature.purchasingManage);
    final currency = ref.watch(currencyProvider);

    final requests = ref.watch(purchaseRequestsProvider);
    final requestsNotifier = ref.read(purchaseRequestsProvider.notifier);
    final orders = ref.watch(purchaseOrdersProvider);
    final ordersNotifier = ref.read(purchaseOrdersProvider.notifier);

    return PageBody(
      onRefresh: _orders ? ordersNotifier.refresh : requestsNotifier.refresh,
      children: [
        const PageTitle('Purchasing'),
        Wrap(
          spacing: Space.sm,
          children: [
            ChoiceChip(
              label: const Text('Requests'),
              selected: !_orders,
              onSelected: (_) => setState(() => _orders = false),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
            ChoiceChip(
              label: const Text('Orders'),
              selected: _orders,
              onSelected: (_) => setState(() => _orders = true),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        if (!_orders) ...[
          if (canCreate) ...[
            AppButton(
              label: 'New purchase request',
              icon: Icons.add_rounded,
              onPressed: () => context.push('/purchasing/new'),
            ),
            const SizedBox(height: Space.md),
          ],
          StatusFilterRow(
            options: _requestFilters,
            selected: requests.filter,
            onSelected: requestsNotifier.setFilter,
          ),
          const SizedBox(height: Space.md),
          ...pagedRows<PurchaseRequestSummary>(
            context,
            state: requests,
            onRefresh: requestsNotifier.refresh,
            onLoadMore: requestsNotifier.loadMore,
            emptyIcon: Icons.shopping_cart_outlined,
            emptyTitle: requests.filter == null
                ? 'No purchase requests yet'
                : 'No requests with that status',
            emptyMessage: requests.filter == null && canCreate
                ? 'Ask for materials with "New purchase request".'
                : null,
            rowBuilder: (r) => _RequestCard(
              request: r,
              onTap: () => context.push('/purchasing/requests/${r.id}'),
            ),
          ),
        ] else ...[
          StatusFilterRow(
            options: _orderFilters,
            selected: orders.filter,
            onSelected: ordersNotifier.setFilter,
          ),
          const SizedBox(height: Space.md),
          ...pagedRows<PurchaseOrderSummary>(
            context,
            state: orders,
            onRefresh: ordersNotifier.refresh,
            onLoadMore: ordersNotifier.loadMore,
            emptyIcon: Icons.local_shipping_outlined,
            emptyTitle: orders.filter == null
                ? 'No purchase orders yet'
                : 'No orders with that status',
            emptyMessage: orders.filter == null
                ? 'Orders are made from approved requests on the web app.'
                : null,
            rowBuilder: (o) => _OrderCard(
              order: o,
              currency: currency,
              onTap: () => context.push('/purchasing/orders/${o.id}'),
            ),
          ),
        ],
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});
  final PurchaseRequestSummary request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${r.number}, ${statusInfo(r.status).label}, requested by ${r.requestedBy}, ${r.itemCount} items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              r.number,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(r.status),
          ),
          if (r.projectName != null)
            Text(
              r.projectName!,
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          const SizedBox(height: Space.sm),
          Text(
            '${r.requestedBy} · ${Fmt.ago(r.createdAt)} · ${r.itemCount} ${r.itemCount == 1 ? 'item' : 'items'}',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
          if (r.notes != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                r.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodySmall.copyWith(color: c.text),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currency,
    required this.onTap,
  });
  final PurchaseOrderSummary order;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = order;
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${o.number}, ${o.supplierName}, ${statusInfo(o.status).label}, ${Fmt.money(o.total, currency)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              o.supplierName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(o.status),
          ),
          Text(o.number, style: AppType.bodySmall.copyWith(color: c.textMuted)),
          const SizedBox(height: Space.md),
          AdaptiveRow(
            start: Text(
              o.expectedDelivery == null
                  ? '${o.itemCount} ${o.itemCount == 1 ? 'item' : 'items'}'
                  : 'Expected ${Fmt.day(o.expectedDelivery!)}',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
            end: Text(
              Fmt.money(o.total, currency),
              style: AppType.amount.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

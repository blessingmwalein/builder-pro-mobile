import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../../finance/presentation/finance_widgets.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';

/// One purchase order, its deliveries, and (with `materials.manage`) recording
/// a delivery. Sending the order to the supplier is done on the web app.
class PurchaseOrderDetailScreen extends ConsumerWidget {
  const PurchaseOrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseOrderDetailProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.number ?? 'Order')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 120),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(purchaseOrderDetailProvider(orderId)),
          ),
          data: (d) => _Body(
            detail: d,
            onRefresh: () async {
              ref.invalidate(purchaseOrderDetailProvider(orderId));
              try {
                await ref.read(purchaseOrderDetailProvider(orderId).future);
              } catch (_) {
                // The error state is shown by the screen itself.
              }
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail, required this.onRefresh});
  final PurchaseOrderDetail detail;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final perms = ref.watch(permissionsProvider);
    final me = ref.watch(currentUserIdProvider);
    final d = detail;
    final o = d.summary;
    final canManage = perms.hasAny(Feature.purchasingManage);
    return PageBody(
      onRefresh: onRefresh,
      children: [
        Text(o.supplierName, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(o.status),
            Text(o.number, style: AppType.label.copyWith(color: c.textMuted)),
          ],
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact('Raised', Fmt.day(o.createdAt)),
              if (o.expectedDelivery != null)
                _Fact('Expected', Fmt.day(o.expectedDelivery!)),
              if (d.deliveredAt != null)
                _Fact('Delivered', Fmt.day(d.deliveredAt!)),
              _Fact(
                'Deliveries',
                d.deliveryCount == 0
                    ? 'None recorded'
                    : '${d.deliveryCount} recorded',
              ),
              if (d.requestNumber != null)
                _Fact('From request', d.requestNumber!),
            ],
          ),
        ),
        if (d.requestId != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: AppCard(
              onTap: () => context.push('/purchasing/requests/${d.requestId}'),
              child: Row(
                children: [
                  const IconTile(Icons.shopping_cart_outlined),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Text(
                      'Open request ${d.requestNumber ?? ''}'.trim(),
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textMuted),
                ],
              ),
            ),
          ),
        SectionHeader('ITEMS ${d.items.length}'),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < d.items.length; i++) ...[
                if (i > 0) Divider(height: Space.xl, color: c.border),
                AdaptiveRow(
                  start: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.items[i].description,
                        style: AppType.bodyStrong.copyWith(color: c.text),
                      ),
                      Text(
                        '${Fmt.quantity(d.items[i].quantity)} × ${Fmt.money(d.items[i].unitCost, currency)}',
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                  end: Text(
                    Fmt.money(d.items[i].totalCost, currency),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
              ],
              Divider(height: Space.xl, color: c.border),
              AmountRow(
                'Order total',
                o.total,
                currency: currency,
                strong: true,
              ),
            ],
          ),
        ),
        if (d.deliveries.isNotEmpty) ...[
          SectionHeader('DELIVERIES ${d.deliveries.length}'),
          for (final n in d.deliveries)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                child: _DeliveryFacts(note: n, mine: n.receivedById == me),
              ),
            ),
        ],
        if (d.notes != null) ...[
          const SectionHeader('NOTES'),
          Text(d.notes!, style: AppType.body.copyWith(color: c.text)),
        ],
        const SizedBox(height: Space.xl),
        if (canManage && o.status == PoStatus.draft) _MarkSentButton(order: d),
        if (canManage && d.canEdit) ...[
          AppButton(
            label: 'Edit order',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => context.push('/purchasing/orders/${o.id}/edit'),
          ),
          const SizedBox(height: Space.sm),
        ],
        if (canManage && d.isReceivable && d.hasOutstanding)
          AppButton(
            label: 'Record a delivery',
            icon: Icons.local_shipping_outlined,
            onPressed: () => context.push('/purchasing/orders/${o.id}/receive'),
          ),
        if (canManage && d.isReceivable && !d.hasOutstanding)
          Text(
            'Everything ordered is recorded as received, but the order does not show as complete. Check it on the web app.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        if (!canManage && d.isReceivable)
          Text(
            'Recording a delivery needs permission to manage purchasing.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        if (canManage && d.canCancel) ...[
          const SizedBox(height: Space.sm),
          _CancelOrderButton(order: d),
        ],
        if (canManage &&
            (o.status == PoStatus.partial || o.status == PoStatus.sent) &&
            !d.canCancel)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              'An order with a delivery recorded cannot be cancelled.',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ),
        const SizedBox(height: Space.md),
        Text(
          'Sending an order to the supplier is done on the web app.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

/// "Mark as sent" on a draft order. It only records that the order was sent: the
/// server contacts nobody, and the screen says so.
class _MarkSentButton extends ConsumerStatefulWidget {
  const _MarkSentButton({required this.order});
  final PurchaseOrderDetail order;

  @override
  ConsumerState<_MarkSentButton> createState() => _MarkSentButtonState();
}

class _MarkSentButtonState extends ConsumerState<_MarkSentButton> {
  bool _busy = false;

  Future<void> _send() async {
    if (_busy) return;
    final o = widget.order.summary;
    setState(() => _busy = true);
    try {
      final ok = await confirmAction(
        context,
        title: 'Mark ${o.number} as sent?',
        message:
            'This records that the order went to ${o.supplierName}. Nothing is emailed or sent from this app.',
        confirmLabel: 'Mark as sent',
      );
      if (!ok || !mounted) return;
      final note = await ref.read(purchasingActionsProvider).sendOrder(o.id);
      if (mounted) Snack.show(context, note ?? 'Marked as sent.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Mark as sent',
          icon: Icons.outbox_rounded,
          loading: _busy,
          onPressed: _busy ? null : _send,
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Marks the order as sent. Nothing is emailed to the supplier from this app.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

/// "Cancel this order" on an order with nothing delivered against it. It only
/// records the cancellation: the server contacts nobody, so the sheet says to
/// tell the supplier when the order had been sent.
class _CancelOrderButton extends ConsumerStatefulWidget {
  const _CancelOrderButton({required this.order});
  final PurchaseOrderDetail order;

  @override
  ConsumerState<_CancelOrderButton> createState() => _CancelOrderButtonState();
}

class _CancelOrderButtonState extends ConsumerState<_CancelOrderButton> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    final d = widget.order;
    final o = d.summary;
    setState(() => _busy = true);
    try {
      final freed = d.requestNumber == null
          ? ''
          : ' ${d.requestNumber} goes back to Approved so it can be ordered again.';
      final told = o.status == PoStatus.sent
          ? ' It was marked as sent, and nothing is emailed from this app, so tell ${o.supplierName} yourself.'
          : ' Nothing was sent to the supplier.';
      final ok = await confirmAction(
        context,
        title: 'Cancel ${o.number}?',
        message:
            'The order is marked Cancelled and cannot be used again.$freed$told',
        confirmLabel: 'Cancel order',
        cancelLabel: 'Keep the order',
        destructive: true,
      );
      if (!ok || !mounted) return;
      final note = await ref.read(purchasingActionsProvider).cancelOrder(o.id);
      if (mounted) Snack.show(context, note ?? 'Order cancelled.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Cancel this order',
      icon: Icons.block_rounded,
      variant: AppButtonVariant.secondary,
      loading: _busy,
      onPressed: _busy ? null : _cancel,
    );
  }
}

class _DeliveryFacts extends StatelessWidget {
  const _DeliveryFacts({required this.note, required this.mine});
  final DeliveryNote note;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final day = note.deliveryDate == null
        ? 'Delivery'
        : Fmt.calendarDay(note.deliveryDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$day · received by ${mine ? 'you' : 'a colleague'}',
          style: AppType.bodyStrong.copyWith(color: c.text),
        ),
        const SizedBox(height: Space.xs),
        for (final l in note.lines.where((l) => l.received > 0))
          Text(
            '${l.description}: ${Fmt.quantity(l.received)} received',
            style: AppType.bodySmall.copyWith(color: c.textMuted),
          ),
        if (note.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              note.notes!,
              style: AppType.body.copyWith(color: c.text),
            ),
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

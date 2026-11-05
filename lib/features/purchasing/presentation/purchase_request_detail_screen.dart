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
import '../../../shared/components/layout.dart';
import '../../finance/presentation/finance_widgets.dart';
import '../../../shared/components/reason_sheet.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';

/// One purchase request: what is being asked for, who asked, and the actions the
/// user's permissions allow for its current status.
class PurchaseRequestDetailScreen extends ConsumerStatefulWidget {
  const PurchaseRequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<PurchaseRequestDetailScreen> createState() =>
      _PurchaseRequestDetailScreenState();
}

class _PurchaseRequestDetailScreenState
    extends ConsumerState<PurchaseRequestDetailScreen> {
  bool _busy = false;

  PurchasingActions get _actions => ref.read(purchasingActionsProvider);

  Future<void> _run(
    Future<String?> Function() action,
    String successMessage,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final note = await action();
      if (mounted) Snack.show(context, note ?? successMessage);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(PurchaseRequestDetail d) =>
      _run(() => _actions.submit(d.summary.id), 'Submitted for approval.');

  Future<void> _approve(PurchaseRequestDetail d, String currency) async {
    final mine = d.summary.requestedById == ref.read(currentUserIdProvider);
    final estimate = d.estimatedTotal > 0
        ? ', about ${Fmt.money(d.estimatedTotal, currency)} estimated'
        : '';
    final ok = await confirmAction(
      context,
      title: 'Approve ${d.summary.number}?',
      message:
          '${d.items.length} ${d.items.length == 1 ? 'item' : 'items'}$estimate. Once approved it can be turned into a purchase order.${mine ? ' You raised this request yourself.' : ''}',
      confirmLabel: 'Approve',
    );
    if (!ok || !mounted) return;
    await _run(() => _actions.approve(d.summary.id), 'Approved.');
  }

  Future<void> _reject(PurchaseRequestDetail d) async {
    final reason = await showReasonSheet(
      context,
      title: 'Reject ${d.summary.number}?',
      subtitle:
          'Requested by ${d.summary.requestedBy}. Your reason replaces the notes they wrote on this request.',
      confirmLabel: 'Reject',
      hint: 'Tell them why',
    );
    if (reason == null || !mounted) return;
    await _run(() => _actions.reject(d.summary.id, notes: reason), 'Rejected.');
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(purchaseRequestDetailProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.number ?? 'Request')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 120),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () =>
                ref.invalidate(purchaseRequestDetailProvider(widget.requestId)),
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(PurchaseRequestDetail d) {
    final c = context.colors;
    final perms = ref.watch(permissionsProvider);
    final currency = ref.watch(currencyProvider);
    final s = d.summary;
    final canSubmit = s.isDraft && perms.hasAny(Feature.purchasingManage);
    final canDecide = s.isSubmitted && perms.hasAny(Feature.purchasingApprove);

    return PageBody(
      onRefresh: () async {
        ref.invalidate(purchaseRequestDetailProvider(widget.requestId));
        try {
          await ref.read(
            purchaseRequestDetailProvider(widget.requestId).future,
          );
        } catch (_) {
          // The error state is shown by the screen itself.
        }
      },
      children: [
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(s.status),
            Text(s.number, style: AppType.label.copyWith(color: c.textMuted)),
          ],
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.projectName != null) _Fact('Project', s.projectName!),
              _Fact('Requested by', s.requestedBy),
              _Fact('Raised', Fmt.dayTime(s.createdAt)),
              if (s.approvedBy != null && d.approvedAt != null)
                _Fact(
                  'Approved by',
                  '${s.approvedBy} · ${Fmt.day(d.approvedAt!)}',
                ),
              if (s.approvedBy != null && d.rejectedAt != null)
                _Fact(
                  'Rejected by',
                  '${s.approvedBy} · ${Fmt.day(d.rejectedAt!)}',
                ),
            ],
          ),
        ),
        if (s.notes != null) ...[
          const SectionHeader('NOTES'),
          Text(s.notes!, style: AppType.body.copyWith(color: c.text)),
        ],
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
                        '${Fmt.quantity(d.items[i].quantity)} ${d.items[i].unit}${d.items[i].estimatedUnitCost == null ? '' : ' × ${Fmt.money(d.items[i].estimatedUnitCost!, currency)}'}',
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                  end: Text(
                    d.items[i].estimatedTotal == null
                        ? 'No estimate'
                        : Fmt.money(d.items[i].estimatedTotal!, currency),
                    style: AppType.amount.copyWith(
                      color: d.items[i].estimatedTotal == null
                          ? c.textMuted
                          : c.text,
                    ),
                  ),
                ),
              ],
              if (d.estimatedTotal > 0) ...[
                Divider(height: Space.xl, color: c.border),
                AmountRow(
                  d.estimateComplete
                      ? 'Estimated total'
                      : 'Estimated total (at least)',
                  d.estimatedTotal,
                  currency: currency,
                  strong: true,
                ),
              ],
            ],
          ),
        ),
        if (d.orders.isNotEmpty) ...[
          const SectionHeader('ORDERS FROM THIS REQUEST'),
          for (final o in d.orders)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                onTap: () => context.push('/purchasing/orders/${o.id}'),
                child: AdaptiveRow(
                  start: Text(
                    o.number,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        Fmt.money(o.total, currency),
                        style: AppType.amount.copyWith(color: c.text),
                      ),
                      StatusBadge.status(o.status, dense: true),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (canSubmit) ...[
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Submit for approval',
            icon: Icons.send_rounded,
            loading: _busy,
            onPressed: () => _submit(d),
          ),
        ],
        if (canDecide) ...[
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Approve',
            icon: Icons.check_rounded,
            loading: _busy,
            onPressed: _busy ? null : () => _approve(d, currency),
          ),
          const SizedBox(height: Space.sm),
          AppButton(
            label: 'Reject',
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => _reject(d),
          ),
        ],
        if (s.status == PrStatus.approved &&
            perms.hasAny(Feature.purchasingManage)) ...[
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Create purchase order',
            icon: Icons.local_shipping_outlined,
            onPressed: () => context.push('/purchasing/requests/${s.id}/order'),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Choose the supplier and prices. The order starts as a draft: nothing is sent to the supplier until you mark it sent.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
        if (s.isSubmitted && !canDecide) ...[
          const SizedBox(height: Space.xl),
          Text(
            'Waiting for someone with approval rights to decide.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
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

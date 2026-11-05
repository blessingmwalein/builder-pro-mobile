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
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/finance_providers.dart';
import '../application/send_actions.dart';
import '../data/finance_models.dart';
import 'finance_widgets.dart';
import 'send_to_client_button.dart';

/// Invoices, newest first, filtered by status. Read-only.
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('OVERDUE', 'Overdue'),
    ('SENT', 'Sent'),
    ('PARTIALLY_PAID', 'Part paid'),
    ('PAID', 'Paid'),
    ('DRAFT', 'Draft'),
    ('VOID', 'Void'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(invoicesCatalogProvider);
    final notifier = ref.read(invoicesCatalogProvider.notifier);
    final currency = ref.watch(currencyProvider);
    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        const PageTitle('Invoices'),
        if (ref.watch(permissionsProvider).hasAny(Feature.invoicesCreate)) ...[
          AppButton(
            label: 'New invoice',
            icon: Icons.add_rounded,
            onPressed: () => context.push('/invoices/new'),
          ),
          const SizedBox(height: Space.md),
        ],
        StatusFilterRow(
          options: _filters,
          selected: state.filter,
          onSelected: notifier.setFilter,
        ),
        const SizedBox(height: Space.md),
        ...pagedRows<InvoiceSummary>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.receipt_long_outlined,
          emptyTitle: state.filter == null
              ? 'No invoices yet'
              : 'No invoices with that status',
          emptyMessage: state.filter == null
              ? 'Invoices you create will appear here.'
              : null,
          rowBuilder: (i) => _InvoiceCard(
            invoice: i,
            currency: currency,
            onTap: () => context.push('/invoices/${i.id}'),
          ),
        ),
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.currency,
    required this.onTap,
  });

  final InvoiceSummary invoice;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = invoice;
    final owing = i.balance > 0 && i.status != 'VOID' && i.status != 'DRAFT';
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${i.number}, ${i.clientName}, ${statusInfo(i.status).label}, total ${Fmt.money(i.total, currency)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              i.clientName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(i.status),
          ),
          Text(
            [i.number, if (i.projectName != null) i.projectName!].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.md),
          AdaptiveRow(
            start: Text(
              i.dueDate == null ? '' : 'Due ${Fmt.day(i.dueDate!)}',
              style: AppType.helper.copyWith(
                color: i.status == 'OVERDUE' ? c.danger : c.textMuted,
              ),
            ),
            end: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.money(i.total, currency),
                  style: AppType.amount.copyWith(color: c.text),
                ),
                if (owing)
                  Text(
                    '${Fmt.money(i.balance, currency)} owing',
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One invoice: totals, lines and payments. Sending an invoice or recording a
/// payment is done on the web app.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(invoiceDetailProvider(invoiceId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.number ?? 'Invoice')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 120),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
          ),
          data: (d) => _Body(
            detail: d,
            onRefresh: () async {
              ref.invalidate(invoiceDetailProvider(invoiceId));
              try {
                await ref.read(invoiceDetailProvider(invoiceId).future);
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
  final InvoiceDetail detail;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final d = detail;
    final i = d.summary;
    return PageBody(
      onRefresh: onRefresh,
      children: [
        Text(i.clientName, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(i.status),
            Text(i.number, style: AppType.label.copyWith(color: c.textMuted)),
          ],
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i.projectName != null) _Fact('Project', i.projectName!),
              if (i.issueDate != null) _Fact('Issued', Fmt.day(i.issueDate!)),
              if (i.dueDate != null) _Fact('Due', Fmt.day(i.dueDate!)),
              if (d.quoteNumber != null) _Fact('From quote', d.quoteNumber!),
              if (d.clientContact != null) _Fact('Contact', d.clientContact!),
              if (d.paymentTerms != null) _Fact('Terms', d.paymentTerms!),
            ],
          ),
        ),
        const SectionHeader('LINES'),
        LineItemsCard(lines: d.lines, currency: currency),
        const SectionHeader('TOTALS'),
        AppCard(
          child: Column(
            children: [
              AmountRow('Subtotal', d.subtotal, currency: currency),
              if (d.tax != 0) AmountRow('Tax', d.tax, currency: currency),
              AmountRow('Total', i.total, currency: currency, strong: true),
              AmountRow('Paid', i.paid, currency: currency),
              Divider(color: c.border),
              AmountRow(
                'Balance due',
                i.balance,
                currency: currency,
                strong: true,
                tone: i.balance > 0 && i.status != 'VOID' ? c.danger : null,
              ),
              if (d.retentionPercent > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Retention ${Fmt.percent(d.retentionPercent)} applies.',
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                ),
            ],
          ),
        ),
        const SectionHeader('PAYMENTS'),
        if (d.payments.isEmpty)
          AppCard(
            child: Text(
              'No payments recorded.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          )
        else
          for (final p in d.payments)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                child: AdaptiveRow(
                  start: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.paidAt == null ? 'Payment' : Fmt.day(p.paidAt!),
                        style: AppType.bodyStrong.copyWith(color: c.text),
                      ),
                      Text(
                        [
                          _method(p.method),
                          if (p.reference != null) p.reference!,
                        ].join(' · '),
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                  end: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Fmt.money(p.amount, currency),
                        style: AppType.amount.copyWith(color: c.text),
                      ),
                      StatusBadge.status(p.status, dense: true),
                    ],
                  ),
                ),
              ),
            ),
        if (d.notes != null) ...[
          const SectionHeader('NOTES'),
          Text(d.notes!, style: AppType.body.copyWith(color: c.text)),
        ],
        const SizedBox(height: Space.xl),
        if (i.status == InvoiceStatus.draft &&
            ref.watch(permissionsProvider).hasAny(Feature.invoicesSend))
          SendToClientButton(
            kind: 'invoice',
            number: i.number,
            clientName: i.clientName,
            clientEmail: d.clientEmail,
            onSend: (email) =>
                ref.read(sendActionsProvider).sendInvoice(i.id, email: email),
          ),
        if (ref
                .watch(permissionsProvider)
                .hasAny(Feature.invoicesRecordPayment) &&
            i.isOpenForPayment)
          AppButton(
            label: 'Record a payment',
            icon: Icons.payments_outlined,
            onPressed: () => context.push('/invoices/${i.id}/pay'),
          ),
        const SizedBox(height: Space.md),
        Text(
          'Payments by PayNow or EcoCash, and voiding an invoice, are done on the web app.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
      ],
    );
  }

  String _method(String raw) {
    final words = raw
        .toLowerCase()
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');
    return words.join(' ');
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
            width: 84,
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

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
import '../../../shared/components/reason_sheet.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/finance_providers.dart';
import '../application/quote_actions.dart';
import '../application/send_actions.dart';
import '../data/finance_models.dart';
import 'finance_widgets.dart';
import 'send_to_client_button.dart';

/// Quotes, newest first, filtered by status. Read-only.
class QuotesScreen extends ConsumerWidget {
  const QuotesScreen({super.key});

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('SENT', 'Sent'),
    ('APPROVED', 'Approved'),
    ('DRAFT', 'Draft'),
    ('REJECTED', 'Rejected'),
    ('EXPIRED', 'Expired'),
    ('CONVERTED', 'Converted'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quotesCatalogProvider);
    final notifier = ref.read(quotesCatalogProvider.notifier);
    final currency = ref.watch(currencyProvider);
    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        const PageTitle('Quotes'),
        if (ref.watch(permissionsProvider).hasAny(Feature.quotesCreate)) ...[
          AppButton(
            label: 'New quote',
            icon: Icons.add_rounded,
            onPressed: () => context.push('/quotes/new'),
          ),
          const SizedBox(height: Space.md),
        ],
        StatusFilterRow(
          options: _filters,
          selected: state.filter,
          onSelected: notifier.setFilter,
        ),
        const SizedBox(height: Space.md),
        ...pagedRows<QuoteSummary>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.request_quote_outlined,
          emptyTitle: state.filter == null
              ? 'No quotes yet'
              : 'No quotes with that status',
          emptyMessage: state.filter == null
              ? 'Quotes you create will appear here.'
              : null,
          rowBuilder: (q) => _QuoteCard(
            quote: q,
            currency: currency,
            onTap: () => context.push('/quotes/${q.id}'),
          ),
        ),
      ],
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.currency,
    required this.onTap,
  });

  final QuoteSummary quote;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = quote;
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${q.number}, ${q.title}, ${q.clientName}, ${statusInfo(q.status).label}, ${Fmt.money(q.total, currency)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              q.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(q.status),
          ),
          Text(
            '${q.number} · ${q.clientName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.md),
          AdaptiveRow(
            start: Text(
              q.expiryDate == null
                  ? ''
                  : 'Valid until ${Fmt.day(q.expiryDate!)}',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
            end: Text(
              Fmt.money(q.total, currency),
              style: AppType.amount.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// One quote: lines and totals. Sending, approving and converting a quote are
/// done on the web app.
class QuoteDetailScreen extends ConsumerWidget {
  const QuoteDetailScreen({super.key, required this.quoteId});
  final String quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(quoteDetailProvider(quoteId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.number ?? 'Quote')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 120),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(quoteDetailProvider(quoteId)),
          ),
          data: (d) => _QuoteBody(
            detail: d,
            onRefresh: () async {
              ref.invalidate(quoteDetailProvider(quoteId));
              try {
                await ref.read(quoteDetailProvider(quoteId).future);
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

class _QuoteBody extends ConsumerWidget {
  const _QuoteBody({required this.detail, required this.onRefresh});
  final QuoteDetail detail;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final d = detail;
    final q = d.summary;
    return PageBody(
      onRefresh: onRefresh,
      children: [
        Text(q.title, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(q.status),
            Text(
              '${q.number} · ${q.clientName}',
              style: AppType.label.copyWith(color: c.textMuted),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (q.issueDate != null) _Fact('Issued', Fmt.day(q.issueDate!)),
              if (q.expiryDate != null)
                _Fact('Valid until', Fmt.day(q.expiryDate!)),
              if (d.paymentTerms != null) _Fact('Terms', d.paymentTerms!),
            ],
          ),
        ),
        if (d.rejectionNotes != null) ...[
          const SectionHeader('WHY IT WAS REJECTED'),
          Text(d.rejectionNotes!, style: AppType.body.copyWith(color: c.text)),
        ],
        const SectionHeader('LINES'),
        LineItemsCard(lines: d.lines, currency: currency),
        const SectionHeader('TOTALS'),
        AppCard(
          child: Column(
            children: [
              AmountRow('Subtotal', d.subtotal, currency: currency),
              if (d.discount != 0)
                AmountRow('Discount', -d.discount, currency: currency),
              if (d.tax != 0)
                AmountRow(
                  d.taxRate > 0 ? 'Tax (${Fmt.percent(d.taxRate)})' : 'Tax',
                  d.tax,
                  currency: currency,
                ),
              Divider(color: c.border),
              AmountRow('Total', q.total, currency: currency, strong: true),
            ],
          ),
        ),
        if (d.notes != null) ...[
          const SectionHeader('NOTES'),
          Text(d.notes!, style: AppType.body.copyWith(color: c.text)),
        ],
        const SizedBox(height: Space.xl),
        if (q.status == 'DRAFT' &&
            ref.watch(permissionsProvider).hasAny(Feature.quotesSend))
          SendToClientButton(
            kind: 'quote',
            number: q.number,
            clientName: q.clientName,
            clientEmail: d.clientEmail,
            onSend: (email) =>
                ref.read(sendActionsProvider).sendQuote(q.id, email: email),
          ),
        if (q.status == QuoteStatus.sent &&
            ref.watch(permissionsProvider).hasAny(Feature.quotesApprove))
          _DecideButtons(quote: d),
        if (q.status == QuoteStatus.approved &&
            ref.watch(permissionsProvider).hasAny(Feature.invoicesCreate)) ...[
          const SizedBox(height: Space.sm),
          AppButton(
            label: 'Create invoice from this quote',
            icon: Icons.receipt_long_outlined,
            onPressed: () => context.push('/invoices/new?quoteId=${q.id}'),
          ),
          const SizedBox(height: Space.sm),
          Text(
            "Makes a draft invoice from the quote's lines. Nothing is sent to the client.",
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
        if (q.status == QuoteStatus.converted) ...[
          const SizedBox(height: Space.md),
          Text(
            'An invoice has been made from this quote.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
      ],
    );
  }
}

/// "Mark approved" / "Mark rejected" on a sent quote: the client's answer,
/// recorded. Each is a status change that answers 400 when repeated.
class _DecideButtons extends ConsumerStatefulWidget {
  const _DecideButtons({required this.quote});
  final QuoteDetail quote;

  @override
  ConsumerState<_DecideButtons> createState() => _DecideButtonsState();
}

class _DecideButtonsState extends ConsumerState<_DecideButtons> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      final note = await action();
      if (mounted) Snack.show(context, note ?? done);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    if (_busy) return;
    final q = widget.quote.summary;
    final currency = ref.read(currencyProvider);
    setState(() => _busy = true);
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Mark ${q.number} as approved?',
        message:
            '${q.clientName} accepted ${Fmt.money(q.total, currency)}. If the quote belongs to a project, its material lines are also recorded as used on that project, which adds to its cost. This cannot be undone from this app.',
        confirmLabel: 'Mark approved',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!ok || !mounted || _busy) return;
    await _run(
      () => ref.read(quoteActionsProvider).approve(q.id),
      'Quote marked as approved.',
    );
  }

  Future<void> _reject() async {
    if (_busy) return;
    final q = widget.quote.summary;
    setState(() => _busy = true);
    final String? reason;
    try {
      reason = await showReasonSheet(
        context,
        title: 'Mark ${q.number} as rejected?',
        subtitle:
            '${q.clientName} turned this quote down. The reason is kept with the quote.',
        confirmLabel: 'Mark rejected',
        hint: 'Why was it turned down?',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (reason == null || !mounted || _busy) return;
    await _run(
      () => ref.read(quoteActionsProvider).reject(q.id, notes: reason),
      'Quote marked as rejected.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Mark approved',
          icon: Icons.check_rounded,
          loading: _busy,
          onPressed: _busy ? null : _approve,
        ),
        const SizedBox(height: Space.sm),
        AppButton(
          label: 'Mark rejected',
          variant: AppButtonVariant.secondary,
          onPressed: _busy ? null : _reject,
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
            width: 88,
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

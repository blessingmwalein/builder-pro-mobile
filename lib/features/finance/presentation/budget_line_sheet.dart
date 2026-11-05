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
import '../../projects/presentation/projects_screen.dart' show ProgressLine;
import '../application/finance_providers.dart';
import '../data/finance_models.dart';
import '../data/money_models.dart';
import 'budget_flag.dart';

/// Opens everything behind one budget line: each cost recorded against it, the
/// material used and (for Labour) the time worked, with the totals fixed at the
/// bottom so they stay in view while the items scroll.
Future<void> showBudgetLineSheet(
  BuildContext context, {
  required String projectId,
  required BudgetLine line,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _BudgetLineSheet(projectId: projectId, line: line),
  );
}

class _BudgetLineSheet extends ConsumerWidget {
  const _BudgetLineSheet({required this.projectId, required this.line});
  final String projectId;
  final BudgetLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    final header = _Header(line: line, currency: currency);

    if (line.categoryId.isEmpty) {
      return _Frame(
        maxHeight: maxHeight,
        header: header,
        body: const Padding(
          padding: EdgeInsets.all(Space.xxl),
          child: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No details for this line',
            message: 'The server did not say which category this line is.',
          ),
        ),
      );
    }

    final key = (projectId: projectId, categoryId: line.categoryId);
    final ledger = ref.watch(budgetLedgerProvider(key));
    return ledger.when(
      loading: () => _Frame(
        maxHeight: maxHeight,
        header: header,
        body: const Padding(
          padding: EdgeInsets.fromLTRB(
            Space.xxl,
            Space.lg,
            Space.xxl,
            Space.xxl,
          ),
          child: SkeletonList(rows: 3, rowHeight: 56),
        ),
      ),
      error: (e, _) => _Frame(
        maxHeight: maxHeight,
        header: header,
        body: ErrorPanel(
          error: e,
          compact: true,
          onRetry: () => ref.invalidate(budgetLedgerProvider(key)),
        ),
      ),
      data: (l) => _Frame(
        maxHeight: maxHeight,
        header: header,
        body: _Items(ledger: l, currency: currency),
        footer: _Totals(
          ledger: l,
          line: line,
          currency: currency,
          projectId: projectId,
        ),
      ),
    );
  }
}

/// The header and the totals stay in place; only the items scroll.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.maxHeight,
    required this.header,
    required this.body,
    this.footer,
  });
  final double maxHeight;
  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Flexible(child: body),
          ?footer,
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.line, required this.currency});
  final BudgetLine line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flag = BudgetFlagChip.forLine(line);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            line.categoryName,
            style: AppType.sectionTitle.copyWith(color: c.text),
          ),
          if (flag != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Align(alignment: Alignment.centerLeft, child: flag),
            ),
          const SizedBox(height: Space.md),
          ProgressLine(percent: line.percentUsed.clamp(0, 100)),
          const SizedBox(height: Space.xs),
          Text(
            line.isOver
                ? '${Fmt.money(line.actual, currency)} of ${Fmt.money(line.planned, currency)} · over by ${Fmt.money(-line.remaining, currency)}'
                : '${Fmt.money(line.actual, currency)} of ${Fmt.money(line.planned, currency)} · alert at ${line.thresholdPct ?? defaultAlertPercent}%',
            style: AppType.helper.copyWith(
              color: budgetTone(c, over: line.isOver, warning: line.isWarning),
            ),
          ),
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.ledger, required this.currency});
  final BudgetLedger ledger;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = ledger;
    if (l.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Nothing charged yet',
          message: 'Costs recorded against this line, and material used on the project, appear here.',
        ),
      );
    }
    final mismatch = (l.itemisedTotal - l.actual).abs() >= 0.01;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.lg),
      children: [
        if (l.recorded.isNotEmpty)
          _Section(
            title: 'COSTS RECORDED',
            count: l.recorded.length,
            total: Fmt.money(l.recordedTotal, currency),
            rows: [
              for (final e in l.recorded)
                _Row(
                  title: e.description,
                  detail: [
                    Fmt.day(e.occurredAt),
                    if (e.vendor != null) e.vendor!,
                    if (e.reference != null) e.reference!,
                  ].join(' · '),
                  amount: Fmt.money(e.amount, currency),
                ),
            ],
          ),
        if (l.usage.isNotEmpty)
          _Section(
            title: 'MATERIAL USED',
            count: l.usage.length,
            total: Fmt.money(l.usageTotal, currency),
            rows: [
              for (final u in l.usage)
                _Row(
                  title: u.name,
                  detail:
                      '${Fmt.quantity(u.quantity)}${u.unit == null ? '' : ' ${u.unit}'} × ${Fmt.money(u.unitCost, currency)} · ${Fmt.day(u.date)}',
                  amount: Fmt.money(u.amount, currency),
                ),
            ],
          ),
        if (l.labour.isNotEmpty)
          _Section(
            title: 'LABOUR FROM TIME SHEETS',
            count: l.labour.length,
            total: Fmt.money(l.labourTotal, currency),
            note: 'Time worked on this project, added up by day. The server does not add it to this line\'s spent amount.',
            rows: [
              for (final d in l.labour)
                _Row(
                  title: Fmt.day(d.day),
                  detail:
                      '${d.entries} ${d.entries == 1 ? 'time entry' : 'time entries'} · ${Fmt.hours(d.hours)}',
                  amount: Fmt.money(d.amount, currency),
                ),
            ],
          ),
        if (l.purchases.isNotEmpty)
          _Section(
            title: 'BOUGHT FOR THIS PROJECT',
            count: l.purchases.length,
            total: Fmt.money(l.purchasesTotal, currency),
            note: 'Counted when the material is used, so these are not part of the amount spent.',
            rows: [
              for (final e in l.purchases)
                _Row(
                  title: e.description,
                  detail: [
                    Fmt.day(e.occurredAt),
                    if (e.vendor != null) e.vendor!,
                    if (e.reference != null) e.reference!,
                  ].join(' · '),
                  amount: Fmt.money(e.amount, currency),
                ),
            ],
          ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: AppCard(
              child: Text(
                'The items above add up to ${Fmt.money(l.itemisedTotal, currency)}, but this line counts ${Fmt.money(l.actual, currency)}. Costs recorded before the line was set are not counted by it.',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.total,
    required this.rows,
    this.note,
  });
  final String title;
  final int count;
  final String total;
  final String? note;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xs),
          child: AdaptiveRow(
            start: Text(
              '$title $count',
              style: AppType.overline.copyWith(color: c.textMuted),
            ),
            end: Text(total, style: AppType.amount.copyWith(color: c.text)),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(
              note!,
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.borderSoft),
          rows[i],
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.detail, required this.amount});
  final String title;
  final String detail;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: AdaptiveRow(
        start: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppType.bodyStrong.copyWith(color: c.text)),
            if (detail.isNotEmpty)
              Text(detail, style: AppType.helper.copyWith(color: c.textMuted)),
          ],
        ),
        end: Text(amount, style: AppType.amount.copyWith(color: c.text)),
      ),
    );
  }
}

/// Fixed under the items: what the line counts, what was planned and what is left.
class _Totals extends ConsumerWidget {
  const _Totals({
    required this.ledger,
    required this.line,
    required this.currency,
    required this.projectId,
  });
  final BudgetLedger ledger;
  final BudgetLine line;
  final String currency;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final canRecord = ref
        .watch(permissionsProvider)
        .hasAny(Feature.financialsManage);
    final left = ledger.planned - ledger.actual;
    final over = ledger.actual > ledger.planned;
    Widget row(
      String label,
      String value, {
      bool strong = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AdaptiveRow(
        start: Text(
          label,
          style: (strong ? AppType.bodyStrong : AppType.body).copyWith(
            color: strong ? c.text : c.textMuted,
          ),
        ),
        end: Text(
          value,
          style: AppType.amount.copyWith(color: color ?? c.text),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xxl,
          Space.md,
          Space.xxl,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              'Counted in this budget',
              Fmt.money(ledger.actual, currency),
              strong: true,
            ),
            row('Planned', Fmt.money(ledger.planned, currency)),
            row(
              over ? 'Over by' : 'Left',
              Fmt.money(over ? -left : left, currency),
              color: over ? c.danger : c.text,
            ),
            if (canRecord) ...[
              const SizedBox(height: Space.sm),
              AppButton(
                label: 'Record a cost here',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(
                    '/projects/$projectId/costs/new?category=${line.categoryId}',
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

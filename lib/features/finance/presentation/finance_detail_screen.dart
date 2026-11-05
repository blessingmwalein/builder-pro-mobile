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
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/states.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../../shared/components/snack.dart';
import '../../projects/application/projects_providers.dart';
import '../../projects/presentation/project_budget_section.dart';
import '../../projects/presentation/project_picker.dart';
import '../application/finance_providers.dart';
import '../data/money_models.dart';
import 'budget_flag.dart';
import 'money_filters.dart';

/// The four money figures on the Finance page, each opened up.
enum MoneyTab {
  collected('collected'),
  costs('costs'),
  profit('profit'),
  budget('budget');

  const MoneyTab(this.path);
  final String path;

  static MoneyTab parse(String? s) =>
      MoneyTab.values.where((t) => t.path == s).firstOrNull ?? MoneyTab.costs;
}

/// What makes up the money collected, the costs, the profit and the budget left,
/// for a day, a month, a range of dates or all time, and for all projects or one.
/// For people who may read financials. The four figures at the top double as the
/// tabs. Budgets are not dated, so the dates do not change them.
class FinanceDetailScreen extends ConsumerStatefulWidget {
  const FinanceDetailScreen({super.key, required this.tab, this.projectId});
  final MoneyTab tab;
  final String? projectId;

  @override
  ConsumerState<FinanceDetailScreen> createState() =>
      _FinanceDetailScreenState();
}

class _FinanceDetailScreenState extends ConsumerState<FinanceDetailScreen> {
  late MoneyTab _tab = widget.tab;
  MoneyPeriod _period = MoneyPeriod.all;
  late String? _projectId = widget.projectId;
  String? _projectName;
  CostSource _source = CostSource.materials;
  bool _picking = false;

  MoneyQuery get _query => MoneyQuery(_period, _projectId);

  Future<void> _pickProject() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final id = _projectId;
      final picked = await chooseProject(
        context,
        ref,
        title: 'Show one project',
        selected: id == null ? null : ref.read(projectDetailProvider(id)).value,
        clearLabel: 'All projects',
      );
      if (picked == null || !mounted) return;
      _setProject(picked.value?.id, picked.value?.name);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _setProject(String? id, String? name) => setState(() {
    _projectId = id;
    _projectName = name;
  });

  Future<void> _refresh() async {
    final q = _query;
    ref.invalidate(moneyOverviewProvider(q));
    switch (_tab) {
      case MoneyTab.collected:
        ref.invalidate(collectionsLedgerProvider(q));
      case MoneyTab.costs:
        ref.invalidate(costsLedgerProvider(CostsKey(q, _source)));
      case MoneyTab.budget:
        if (q.projectId != null) {
          ref.invalidate(projectBudgetProvider(q.projectId!));
        }
      case MoneyTab.profit:
        break;
    }
    try {
      await ref.read(moneyOverviewProvider(q).future);
    } on AppException {
      // The panel below shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref.watch(permissionsProvider).hasAny(Feature.financials);
    final q = _query;
    final overview = ref.watch(moneyOverviewProvider(q));
    final id = _projectId;
    final name = id == null
        ? null
        : (_projectName ??
              ref.watch(projectDetailProvider(id)).value?.name ??
              'This project');
    return Scaffold(
      appBar: AppBar(title: const Text('Money in and out')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot see the company\'s money.',
              )
            : PageBody(
                onRefresh: _refresh,
                children: [
                  MoneyFilterBar(
                    period: _period,
                    onPeriod: (p) => setState(() => _period = p),
                    projectName: name,
                    onPickProject: _pickProject,
                    onClearProject: () => _setProject(null, null),
                  ),
                  const SizedBox(height: Space.md),
                  overview.when(
                    skipLoadingOnReload: true,
                    loading: () => const SkeletonList(rows: 3, rowHeight: 96),
                    error: (e, _) =>
                        e is AppException && e.kind == AppErrorKind.notFound
                        ? const _NeedsServerUpdate()
                        : ErrorPanel(
                            error: e,
                            onRetry: () =>
                                ref.invalidate(moneyOverviewProvider(q)),
                          ),
                    data: (o) => _Loaded(
                      overview: o,
                      query: q,
                      tab: _tab,
                      source: _source,
                      onTab: (t) => setState(() => _tab = t),
                      onSource: (s) => setState(() => _source = s),
                      onProject: _setProject,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Shown when the server answers "not found": it does not have these figures yet.
class _NeedsServerUpdate extends StatelessWidget {
  const _NeedsServerUpdate();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: Space.x3),
    child: EmptyState(
      icon: Icons.cloud_sync_outlined,
      title: 'Not available on your server yet',
      message: 'This page needs the latest server update, which has not been installed. The figures on the Finance page still work.',
    ),
  );
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.overview,
    required this.query,
    required this.tab,
    required this.source,
    required this.onTab,
    required this.onSource,
    required this.onProject,
  });
  final MoneyOverview overview;
  final MoneyQuery query;
  final MoneyTab tab;
  final CostSource source;
  final ValueChanged<MoneyTab> onTab;
  final ValueChanged<CostSource> onSource;
  final void Function(String? id, String? name) onProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final o = overview;
    Widget tile(MoneyTab t, String label, String value, String caption) =>
        Expanded(
          child: MetricTile(
            label: label,
            value: value,
            caption: caption,
            selected: tab == t,
            onTap: () => onTab(t),
          ),
        );
    final margin = o.marginPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                MoneyTab.collected,
                'COLLECTED',
                Fmt.money(o.collected, currency),
                'Paid by clients',
              ),
              const SizedBox(width: Space.md),
              tile(
                MoneyTab.costs,
                'COSTS',
                Fmt.money(o.costs.total, currency),
                'Used, recorded, labour',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                MoneyTab.profit,
                'PROFIT',
                Fmt.money(o.profit, currency),
                margin == null
                    ? 'Collected minus costs'
                    : '$margin% of collected',
              ),
              const SizedBox(width: Space.md),
              tile(
                MoneyTab.budget,
                'BUDGET LEFT',
                Fmt.money(o.budget.left, currency),
                o.budget.isOver
                    ? 'Over its budget'
                    : 'of ${Fmt.money(o.budget.planned, currency)}',
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        switch (tab) {
          MoneyTab.collected => _CollectedTab(
            query: query,
            overview: o,
            currency: currency,
            onProject: onProject,
          ),
          MoneyTab.costs => _CostsTab(
            query: query,
            overview: o,
            currency: currency,
            source: source,
            onSource: onSource,
          ),
          MoneyTab.profit => _ProfitTab(
            query: query,
            overview: o,
            currency: currency,
            onProject: onProject,
          ),
          MoneyTab.budget => _BudgetTab(
            query: query,
            overview: o,
            currency: currency,
            onProject: onProject,
          ),
        },
      ],
    );
  }
}

// ---- shared bits -------------------------------------------------------------

/// A project's row in a by-project list. Tapping it narrows the page to it.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.title,
    required this.subtitle,
    required this.value,
    this.valueColor,
    this.flag,
    this.onTap,
    this.footer,
  });
  final String title;
  final String subtitle;
  final String value;
  final Color? valueColor;
  final Widget? flag;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: AppCard(
        onTap: onTap,
        semanticLabel: '$title, $subtitle, $value',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              start: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  Text(
                    subtitle,
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              end: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: AppType.amount.copyWith(color: valueColor ?? c.text),
                  ),
                  if (flag != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: flag,
                    ),
                ],
              ),
            ),
            if (footer != null) ...[const SizedBox(height: Space.sm), footer!],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.sm),
    child: Text(
      text,
      style: AppType.helper.copyWith(color: context.colors.textMuted),
    ),
  );
}

// ---- collected ------------------------------------------------------------

class _CollectedTab extends ConsumerWidget {
  const _CollectedTab({
    required this.query,
    required this.overview,
    required this.currency,
    required this.onProject,
  });
  final MoneyQuery query;
  final MoneyOverview overview;
  final String currency;
  final void Function(String? id, String? name) onProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectionsLedgerProvider(query));
    final notifier = ref.read(collectionsLedgerProvider(query).notifier);
    final canOpenInvoice = ref
        .watch(permissionsProvider)
        .hasAny(Feature.invoices);
    final byProject = overview.projects.where((p) => p.collected != 0).toList()
      ..sort((a, b) => b.collected.compareTo(a.collected));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (query.projectId == null && byProject.length > 1) ...[
          const SectionHeader('BY PROJECT'),
          for (final p in byProject)
            _ProjectRow(
              title: p.name,
              subtitle: p.code ?? 'Money collected',
              value: Fmt.money(p.collected, currency),
              onTap: p.projectId == null
                  ? null
                  : () => onProject(p.projectId, p.name),
            ),
        ],
        const SectionHeader('PAYMENTS RECEIVED'),
        ...pagedRows<CollectionEntry>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.payments_outlined,
          emptyTitle: 'No payments in this period',
          emptyMessage: 'Money received from clients appears here.',
          rowBuilder: (e) => _PaymentRow(
            entry: e,
            currency: currency,
            canOpenInvoice: canOpenInvoice,
          ),
        ),
        const _Note(
          'These are the payments recorded against invoices. Each one is counted on the day it was received.',
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.entry,
    required this.currency,
    required this.canOpenInvoice,
  });
  final CollectionEntry entry;
  final String currency;
  final bool canOpenInvoice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final facts = [
      e.invoiceNumber,
      e.methodLabel,
      if (e.paidAt != null) Fmt.dayTime(e.paidAt!),
    ].join(' · ');
    return AppCard(
      onTap: canOpenInvoice && e.invoiceId != null
          ? () => context.push('/invoices/${e.invoiceId}')
          : null,
      semanticLabel:
          '${e.clientName ?? 'Client'}, ${Fmt.money(e.amount, currency)}, $facts',
      child: AdaptiveRow(
        start: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.clientName ?? 'Client',
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            Text(facts, style: AppType.helper.copyWith(color: c.textMuted)),
            if (e.projectName != null)
              Text(
                e.projectName!,
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            if (e.shownReference != null)
              Text(
                e.shownReference!,
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
          ],
        ),
        end: Text(
          Fmt.money(e.amount, currency),
          style: AppType.amount.copyWith(color: c.text),
        ),
      ),
    );
  }
}

// ---- costs ----------------------------------------------------------------

class _CostsTab extends ConsumerWidget {
  const _CostsTab({
    required this.query,
    required this.overview,
    required this.currency,
    required this.source,
    required this.onSource,
  });
  final MoneyQuery query;
  final MoneyOverview overview;
  final String currency;
  final CostSource source;
  final ValueChanged<CostSource> onSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final k = overview.costs;
    final key = CostsKey(query, source);
    final state = ref.watch(costsLedgerProvider(key));
    final notifier = ref.read(costsLedgerProvider(key).notifier);

    Widget part(String label, double amount, {String? extra}) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              extra == null ? label : '$label · $extra',
              style: AppType.body.copyWith(color: c.text),
            ),
            end: Text(
              Fmt.money(amount, currency),
              style: AppType.amount.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: k.total > 0 ? (amount / k.total).clamp(0.0, 1.0) : 0,
              minHeight: 6,
              color: c.primary,
              backgroundColor: c.surfaceMuted,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('WHAT MAKES UP THE COSTS'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              part('Materials used', k.materialsUsed),
              part('Recorded costs', k.recorded),
              part(
                'Labour',
                k.labour,
                extra: k.labourHours > 0 ? Fmt.hours(k.labourHours) : null,
              ),
              Divider(height: 1, color: c.border),
              const SizedBox(height: Space.sm),
              AdaptiveRow(
                start: Text(
                  'Total costs',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                end: Text(
                  Fmt.money(k.total, currency),
                  style: AppType.amount.copyWith(color: c.text),
                ),
              ),
              if (k.purchases > 0)
                _Note(
                  'Material bought for projects: ${Fmt.money(k.purchases, currency)}. It is counted when it is used, so it is not added above.',
                ),
            ],
          ),
        ),
        if (k.byCategory.isNotEmpty) ...[
          const SectionHeader('BY BUDGET CATEGORY'),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < k.byCategory.length; i++) ...[
                  if (i > 0) Divider(height: Space.xl, color: c.borderSoft),
                  AdaptiveRow(
                    start: Text(
                      k.byCategory[i].name,
                      style: AppType.body.copyWith(color: c.text),
                    ),
                    end: Text(
                      '${Fmt.money(k.byCategory[i].amount, currency)}'
                      '${k.total > 0 ? ' · ${(k.byCategory[i].amount / k.total * 100).round()}%' : ''}',
                      style: AppType.amount.copyWith(color: c.text),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const _Note(
          'Labour is included here. The Costs figure on the Finance page is worked out by the server in its own way and leaves labour out, so the two can differ.',
        ),
        const SectionHeader('DETAILS'),
        StatusFilterRow(
          options: [for (final s in CostSource.values) (s.api, s.label)],
          selected: source.api,
          onSelected: (v) => onSource(
            CostSource.values.firstWhere(
              (s) => s.api == v,
              orElse: () => CostSource.materials,
            ),
          ),
        ),
        if (source == CostSource.labour)
          const _Note(
            'Added up by day and project. Who worked and what they are paid is never shown.',
          ),
        if (source == CostSource.purchases)
          const _Note(
            'Material bought for a project. It is counted when it is used, so these are not in the total.',
          ),
        const SizedBox(height: Space.sm),
        ...pagedRows<CostEntry>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.receipt_long_outlined,
          emptyTitle: 'Nothing in this period',
          emptyMessage:
              'There are no ${source.label.toLowerCase()} for these dates.',
          rowBuilder: (e) => _CostRow(entry: e, currency: currency),
        ),
      ],
    );
  }
}

class _CostRow extends ConsumerWidget {
  const _CostRow({required this.entry, required this.currency});
  final CostEntry entry;
  final String currency;

  Future<void> _openReceipt(BuildContext context, WidgetRef ref) async {
    final url = entry.receiptUrl;
    if (url == null) return;
    final ok = await ref.read(contactLauncherProvider).openLink(url);
    if (!ok && context.mounted) {
      Snack.show(context, 'Could not open the receipt. Try again later.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final e = entry;
    final when = e.date == null ? null : Fmt.day(e.date!);
    final String title;
    final String detail;
    switch (e.source) {
      case CostSource.labour:
        title = when ?? 'Labour';
        detail = [
          if (e.people != null)
            '${e.people} ${e.people == 1 ? 'person' : 'people'}',
          if (e.hours != null) Fmt.hours(e.hours!),
        ].join(' · ');
      case CostSource.materials:
        title = e.description;
        detail = [
          if (e.quantity != null)
            '${Fmt.quantity(e.quantity!)}${e.unit == null ? '' : ' ${e.unit}'}'
                '${e.unitCost == null ? '' : ' × ${Fmt.money(e.unitCost!, currency)}'}',
          ?when,
        ].join(' · ');
      case CostSource.recorded || CostSource.purchases:
        title = e.description;
        detail = [?when, ?e.categoryName, ?e.vendor, ?e.reference].join(' · ');
    }
    return AppCard(
      onTap: e.receiptUrl == null ? null : () => _openReceipt(context, ref),
      semanticLabel:
          '$title, ${Fmt.money(e.amount, currency)}, $detail'
          '${e.receiptUrl == null ? '' : ', tap to open the receipt'}',
      child: AdaptiveRow(
        start: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppType.bodyStrong.copyWith(color: c.text)),
            if (detail.isNotEmpty)
              Text(detail, style: AppType.helper.copyWith(color: c.textMuted)),
            if (e.projectName != null)
              Text(
                e.projectName!,
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            if (e.notes != null)
              Text(
                e.notes!,
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            if (e.receiptUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file_rounded, size: 16, color: c.primary),
                    const SizedBox(width: Space.xs),
                    Text(
                      'Receipt',
                      style: AppType.helper.copyWith(color: c.primary),
                    ),
                  ],
                ),
              ),
          ],
        ),
        end: Text(
          Fmt.money(e.amount, currency),
          style: AppType.amount.copyWith(color: c.text),
        ),
      ),
    );
  }
}

// ---- profit ---------------------------------------------------------------

class _ProfitTab extends StatelessWidget {
  const _ProfitTab({
    required this.query,
    required this.overview,
    required this.currency,
    required this.onProject,
  });
  final MoneyQuery query;
  final MoneyOverview overview;
  final String currency;
  final void Function(String? id, String? name) onProject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = overview;
    final rows = o.projects.where((p) => p.hasMoney).toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));
    Color tone(double v) => v < 0 ? c.danger : c.success;
    Widget line(String label, double v, {bool strong = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: AdaptiveRow(
            start: Text(
              label,
              style: (strong ? AppType.bodyStrong : AppType.body).copyWith(
                color: strong ? c.text : c.textMuted,
              ),
            ),
            end: Text(
              Fmt.money(v, currency),
              style: AppType.amount.copyWith(color: color ?? c.text),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('HOW THE PROFIT IS WORKED OUT'),
        AppCard(
          child: Column(
            children: [
              line('Collected from clients', o.collected),
              line('Costs', -o.costs.total),
              Divider(height: Space.xl, color: c.border),
              line('Profit', o.profit, strong: true, color: tone(o.profit)),
              if (o.marginPercent != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${o.marginPercent}% of what was collected',
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (query.projectId == null && rows.length > 1) ...[
          const SectionHeader('BY PROJECT'),
          for (final p in rows)
            _ProjectRow(
              title: p.name,
              subtitle:
                  'Collected ${Fmt.money(p.collected, currency)} · Costs ${Fmt.money(p.costs, currency)}',
              value: Fmt.money(p.profit, currency),
              valueColor: tone(p.profit),
              onTap: p.projectId == null
                  ? null
                  : () => onProject(p.projectId, p.name),
            ),
        ],
        const _Note(
          'Costs here are material used, recorded costs and labour for the dates chosen. Money that is not tied to a project is listed as "No project".',
        ),
      ],
    );
  }
}

// ---- budget left ----------------------------------------------------------

class _BudgetTab extends StatelessWidget {
  const _BudgetTab({
    required this.query,
    required this.overview,
    required this.currency,
    required this.onProject,
  });
  final MoneyQuery query;
  final MoneyOverview overview;
  final String currency;
  final void Function(String? id, String? name) onProject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = overview.budget;
    final rows = overview.projects.where((p) => p.hasBudget).toList()
      ..sort((a, b) => b.percentUsed.compareTo(a.percentUsed));
    final flags = <Widget>[
      if (b.overLines > 0)
        BudgetFlagChip(
          over: true,
          label: '${b.overLines} ${b.overLines == 1 ? 'line' : 'lines'} over',
        ),
      if (b.warningLines > 0)
        BudgetFlagChip(
          over: false,
          label:
              '${b.warningLines} ${b.warningLines == 1 ? 'line' : 'lines'} near the limit',
        ),
    ];
    final projectId = query.projectId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('BUDGET'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdaptiveRow(
                start: Text(
                  'Spent ${Fmt.money(b.spent, currency)}',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                end: Text(
                  'of ${Fmt.money(b.planned, currency)}',
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
              const SizedBox(height: Space.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (b.percentUsed.clamp(0, 100)) / 100,
                  minHeight: 8,
                  color: b.isOver ? c.danger : c.primary,
                  backgroundColor: c.surfaceMuted,
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                b.isOver
                    ? 'Over budget by ${Fmt.money(-b.left, currency)} (${b.percentUsed}% used)'
                    : '${Fmt.money(b.left, currency)} left (${b.percentUsed}% used)',
                style: AppType.bodySmall.copyWith(
                  color: b.isOver ? c.danger : c.textMuted,
                ),
              ),
              if (flags.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Wrap(spacing: Space.sm, runSpacing: Space.xs, children: flags),
              ],
            ],
          ),
        ),
        const _Note(
          'Budgets are not tied to dates, so the dates chosen above do not change this page. Spent is what the server has counted against each budget.',
        ),
        if (projectId != null) ...[
          const SizedBox(height: Space.md),
          ProjectBudgetSection(projectId: projectId),
        ] else ...[
          const SectionHeader('BY PROJECT'),
          if (rows.isEmpty)
            const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No budgets set',
              message: 'Set a budget on a project and it will be listed here.',
            ),
          for (final p in rows)
            _ProjectRow(
              title: p.name,
              subtitle: p.isOver
                  ? 'Over by ${Fmt.money(-p.left, currency)}'
                  : '${Fmt.money(p.left, currency)} left',
              value: '${p.percentUsed}%',
              valueColor: budgetTone(c, over: p.isOver, warning: p.isWarning),
              flag: BudgetFlagChip.forStatus(
                p.status,
                warningLabel: 'Near the limit',
              ),
              footer: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (p.percentUsed.clamp(0, 100)) / 100,
                  minHeight: 6,
                  color: p.isOver
                      ? c.danger
                      : (p.isWarning ? c.warning : c.primary),
                  backgroundColor: c.surfaceMuted,
                ),
              ),
              onTap: p.projectId == null
                  ? null
                  : () => onProject(p.projectId, p.name),
            ),
        ],
      ],
    );
  }
}

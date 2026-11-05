import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/services/contact_launcher.dart';
import '../application/finance_providers.dart';
import '../data/finance_models.dart';

/// Every cost recorded against one project, newest first, for people who may
/// read financials. Read only.
///
/// Only transactions are listed: material purchases and manual entries such as
/// equipment and overheads. Labour is counted in the budget totals but is never
/// itemised here, because the only source that itemises it lists each worker's
/// pay (backend-gaps G44).
class ProjectCostsScreen extends ConsumerWidget {
  const ProjectCostsScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(permissionsProvider).hasAny(Feature.financials);
    return Scaffold(
      appBar: AppBar(title: const Text('Project costs')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot see project costs.',
              )
            : _Ledger(projectId: projectId),
      ),
    );
  }
}

class _Ledger extends ConsumerWidget {
  const _Ledger({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(costLedgerProvider(projectId));
    final notifier = ref.read(costLedgerProvider(projectId).notifier);
    final currency = ref.watch(currencyProvider);
    final budget = ref.watch(projectBudgetProvider(projectId)).value;
    return PageBody(
      onRefresh: () async {
        ref.invalidate(projectBudgetProvider(projectId));
        await notifier.refresh();
      },
      children: [
        if (budget != null && !budget.isEmpty) ...[
          AppCard(
            child: AdaptiveRow(
              start: Text(
                'Spent so far',
                style: AppType.body.copyWith(color: c.textMuted),
              ),
              end: Text(
                Fmt.money(budget.totalActual, currency),
                style: AppType.amount.copyWith(color: c.text),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        Text(
          'Material purchases and manual entries. Labour is counted in the budget but is not itemised here, so nobody\'s pay is shown.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        ...pagedRows<SpendEntry>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.receipt_long_outlined,
          emptyTitle: 'No costs recorded',
          emptyMessage: 'Costs appear here as materials are bought.',
          rowBuilder: (e) => _CostRow(entry: e, currency: currency),
        ),
      ],
    );
  }
}

class _CostRow extends ConsumerWidget {
  const _CostRow({required this.entry, required this.currency});
  final SpendEntry entry;
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
    final facts = [
      Fmt.day(e.occurredAt),
      if (e.vendor != null) e.vendor!,
      if (e.categoryName != null) e.categoryName!,
      if (e.sourceLabel != null) e.sourceLabel!,
      if (e.reference != null) e.reference!,
    ].join(' · ');
    return AppCard(
      onTap: e.receiptUrl == null ? null : () => _openReceipt(context, ref),
      semanticLabel:
          '${e.description}, ${Fmt.money(e.amount, currency)}, $facts'
          '${e.receiptUrl == null ? '' : ', tap to open the receipt'}',
      child: AdaptiveRow(
        start: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.description,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            Text(facts, style: AppType.helper.copyWith(color: c.textMuted)),
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

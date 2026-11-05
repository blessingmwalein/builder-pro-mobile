import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/name_dialog.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../materials/data/material_reference_models.dart'
    show categoryCodeFor;
import '../application/finance_providers.dart';
import '../data/document_input.dart';
import '../data/finance_models.dart';
import 'line_items_editor.dart' show validateOptionalAmount;

/// Set a project's budget: one planned amount per category, the same categories
/// as the web app's "Edit Budget". Needs the full `financials.*` key. What has
/// been spent is not typed here: the server adds it up as material is used and
/// bought, and the figure beside each category shows it.
class BudgetEditScreen extends ConsumerStatefulWidget {
  const BudgetEditScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends ConsumerState<BudgetEditScreen> {
  final _form = GlobalKey<FormState>();
  final _amounts = <String, TextEditingController>{};
  final _extra = <BudgetCategory>[];
  bool _seeded = false;
  bool _saving = false;
  bool _adding = false;
  AppException? _error;

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String categoryId, [String text = '']) =>
      _amounts.putIfAbsent(categoryId, () => TextEditingController(text: text));

  void _seed(List<BudgetCategory> categories, ProjectBudget budget) {
    _seeded = true;
    for (final cat in categories) {
      final line = budget.lines
          .where((l) => l.categoryId == cat.id)
          .firstOrNull;
      _controllerFor(
        cat.id,
        line == null || line.planned == 0
            ? ''
            : line.planned.toStringAsFixed(2),
      );
    }
  }

  Future<void> _addCategory() async {
    if (_adding) return;
    final name = await askForName(
      context,
      title: 'New budget category',
      label: 'Category name',
      hint: 'e.g. Plumbing',
    );
    if (name == null || !mounted) return;
    setState(() => _adding = true);
    try {
      final created = await ref
          .read(budgetActionsProvider)
          .addCategory(name, categoryCodeFor(name));
      if (!mounted) return;
      setState(() {
        _extra.add(created);
        _controllerFor(created.id);
      });
      Snack.show(context, 'Category "${created.name}" added.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  double _total(List<BudgetCategory> all) =>
      all.fold(0.0, (s, c) => s + (parseAmountText(_amounts[c.id]?.text) ?? 0));

  Future<void> _save(List<BudgetCategory> all, ProjectBudget budget) async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    // A category with a planned amount, or one that had a line (blank = 0, so a
    // budget can be cleared). Blank categories with no line are left alone.
    final edits = <BudgetEdit>[];
    for (final cat in all) {
      final line = budget.lines
          .where((l) => l.categoryId == cat.id)
          .firstOrNull;
      final typed = parseAmountText(_amounts[cat.id]?.text);
      if (typed == null && line == null) continue;
      edits.add(
        BudgetEdit(
          categoryId: cat.id,
          plannedAmount: roundMoney(typed ?? 0),
          thresholdPct: line?.thresholdPct,
        ),
      );
    }
    if (edits.isEmpty) {
      Snack.show(context, 'Enter an amount for at least one category.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetActionsProvider).save(widget.projectId, edits);
      if (!mounted) return;
      Snack.show(context, 'Budget saved.');
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.financialsManage);
    final categories = ref.watch(budgetCategoriesProvider);
    final budget = ref.watch(projectBudgetProvider(widget.projectId));
    return Scaffold(
      appBar: AppBar(title: const Text('Project budget')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot change project budgets.',
              )
            : categories.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 4, rowHeight: 90),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(budgetCategoriesProvider),
                ),
                data: (cats) => budget.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(Space.gutter),
                    child: SkeletonList(rows: 4, rowHeight: 90),
                  ),
                  error: (e, _) => ErrorPanel(
                    error: e,
                    onRetry: () =>
                        ref.invalidate(projectBudgetProvider(widget.projectId)),
                  ),
                  data: (b) {
                    final all = [
                      ...cats,
                      ..._extra.where((x) => !cats.any((c) => c.id == x.id)),
                    ];
                    if (!_seeded) _seed(all, b);
                    for (final c in all) {
                      _controllerFor(c.id);
                    }
                    return _body(all, b);
                  },
                ),
              ),
      ),
    );
  }

  Widget _body(List<BudgetCategory> all, ProjectBudget budget) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    return PageBody(
      children: [
        Text(
          'Set how much is planned for each category. Spending is added up by itself as material is used and bought.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final cat in all)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _CategoryCard(
                    category: cat,
                    line: budget.lines
                        .where((l) => l.categoryId == cat.id)
                        .firstOrNull,
                    controller: _controllerFor(cat.id),
                    currency: currency,
                    enabled: !_saving,
                    onChanged: () => setState(() {}),
                  ),
                ),
              AppButton(
                label: 'Add a category',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.secondary,
                loading: _adding,
                onPressed: _saving ? null : _addCategory,
              ),
              const SizedBox(height: Space.lg),
              AppCard(
                child: AdaptiveRow(
                  start: Text(
                    'Total planned',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: Text(
                    Fmt.money(_total(all), currency),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Save budget',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(all, budget),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.line,
    required this.controller,
    required this.currency,
    required this.enabled,
    required this.onChanged,
  });
  final BudgetCategory category;
  final BudgetLine? line;
  final TextEditingController controller;
  final String currency;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = line;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveRow(
            start: Text(
              category.name,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: l == null
                ? const SizedBox.shrink()
                : StatusBadge.status(l.status, dense: true),
          ),
          if (l != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Spent so far ${Fmt.money(l.actual, currency)}',
                style: AppType.helper.copyWith(
                  color: l.isOver ? c.danger : c.textMuted,
                ),
              ),
            ),
          const SizedBox(height: Space.md),
          AppTextField(
            label: 'Planned ($currency)',
            controller: controller,
            enabled: enabled,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            validator: validateOptionalAmount,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

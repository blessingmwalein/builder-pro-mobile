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
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../projects/application/projects_providers.dart';
import '../application/finance_providers.dart';
import '../data/document_input.dart' show parseAmountText;
import '../data/finance_models.dart';
import '../data/money_models.dart';
import 'budget_flag.dart';

/// The amount of a cost: required, above zero, two decimals. Corrections are not
/// possible from the app (the server has no way to remove a cost), so a negative
/// amount is not accepted either.
String? validateCostAmount(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter the amount';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v <= 0) return 'Enter more than zero';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

String? validateCostDescription(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Say what the cost was for';
  if (t.length > 200) return 'Keep it under 200 characters';
  return null;
}

String? validateCostOptional(String? raw, {required int max}) =>
    (raw ?? '').trim().length > max ? 'Keep it under $max characters' : null;

/// What recording [amount] does to a budget line: how far along it will be, and
/// whether that crosses its alert level or goes over. Null when it only says what
/// the line will be at and nothing needs flagging.
class CostEffect {
  const CostEffect(this.text, {this.over = false, this.warning = false});
  final String text;
  final bool over;
  final bool warning;
}

CostEffect costEffect({
  required BudgetLine? line,
  required String categoryName,
  required double amount,
  required String currency,
}) {
  if (line == null) {
    return CostEffect(
      'This project has no budget for $categoryName, so the cost is recorded but not counted against any budget line.',
      warning: true,
    );
  }
  final after = line.actual + amount;
  final percent = line.planned > 0 ? ((after / line.planned) * 100).round() : 0;
  final alert = line.thresholdPct ?? defaultAlertPercent;
  if (after > line.planned) {
    return CostEffect(
      'This puts $categoryName over its budget by ${Fmt.money(after - line.planned, currency)} (${line.planned > 0 ? '$percent%' : 'nothing was planned'}).',
      over: true,
    );
  }
  if (percent >= alert && line.percentUsed < alert) {
    return CostEffect(
      'This takes $categoryName to $percent% of its budget, past its alert level of $alert%.',
      warning: true,
    );
  }
  if (percent >= alert) {
    return CostEffect(
      '$categoryName will be at $percent% of its budget (alert level $alert%).',
      warning: true,
    );
  }
  return CostEffect(
    '$categoryName will be at $percent% of its budget, ${Fmt.money(line.planned - after, currency)} left.',
  );
}

/// Records a cost against a project's budget: equipment, subcontractors,
/// overheads, or any category. It is added to that category's spent amount at
/// once. Needs `financials.*`. Never recorded twice: see [CostActions].
class RecordCostScreen extends ConsumerStatefulWidget {
  const RecordCostScreen({
    super.key,
    required this.projectId,
    this.initialCategoryId,
  });
  final String projectId;
  final String? initialCategoryId;

  @override
  ConsumerState<RecordCostScreen> createState() => _RecordCostScreenState();
}

class _RecordCostScreenState extends ConsumerState<RecordCostScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  BudgetCategory? _category;
  DateTime _date = _today();
  bool _seeded = false;
  String? _categoryError;
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _vendor.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _seed(List<BudgetCategory> categories) {
    _seeded = true;
    final id = widget.initialCategoryId;
    if (id != null) _category = categories.where((c) => c.id == id).firstOrNull;
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 366)),
      lastDate: today,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickCategory(
    List<BudgetCategory> categories,
    ProjectBudget? budget,
  ) async {
    final picked = await pickOne<BudgetCategory>(
      context,
      title: 'Which budget category?',
      selected: _category,
      options: [
        for (final c in categories)
          PickerOption(
            value: c,
            title: c.name,
            subtitle: _lineFor(budget, c) == null
                ? 'No budget on this project'
                : '${_lineFor(budget, c)!.percentUsed}% of the budget used',
          ),
      ],
    );
    if (picked?.value != null && mounted) {
      setState(() {
        _category = picked!.value;
        _categoryError = null;
      });
    }
  }

  BudgetLine? _lineFor(ProjectBudget? b, BudgetCategory c) =>
      b?.lines.where((l) => l.categoryId == c.id).firstOrNull;

  Future<void> _save(ProjectBudget? budget, String projectName) async {
    if (_saving || _confirming) return;
    setState(() {
      _error = null;
      _categoryError = _category == null ? 'Choose the budget category' : null;
    });
    if (!_form.currentState!.validate() || _category == null) return;

    final amount = roundMoney(parseAmountText(_amount.text)!);
    final now = DateTime.now();
    // The exact moment is what finds this cost again if the answer is lost.
    final input = NewCostInput(
      projectId: widget.projectId,
      categoryId: _category!.id,
      description: _description.text,
      amount: amount,
      occurredAt: DateTime(
        _date.year,
        _date.month,
        _date.day,
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
      ),
      vendor: _vendor.text,
      reference: _reference.text,
      notes: _notes.text,
    );
    final currency = ref.read(currencyProvider);
    final effect = costEffect(
      line: _lineFor(budget, _category!),
      categoryName: _category!.name,
      amount: amount,
      currency: currency,
    );

    // Set before the sheet opens: a second activation in the same frame would
    // otherwise open a second confirmation.
    _confirming = true;
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Record this cost?',
        message:
            '${Fmt.money(amount, currency)} for "${input.description.trim()}", charged to $projectName under ${_category!.name}. '
            '${effect.text} '
            'It cannot be removed from the app once it is recorded.',
        confirmLabel: 'Record cost',
      );
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;

    setState(() => _saving = true);
    try {
      final note = await ref.read(costActionsProvider).record(input);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Snack.show(context, note ?? 'Cost recorded.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Record a cost')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot record costs.',
              )
            : categories.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 4, rowHeight: 70),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(budgetCategoriesProvider),
                ),
                data: (cats) {
                  if (!_seeded) _seed(cats);
                  return _body(cats);
                },
              ),
      ),
    );
  }

  Widget _body(List<BudgetCategory> categories) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final budget = ref.watch(projectBudgetProvider(widget.projectId)).value;
    final projectName =
        ref.watch(projectDetailProvider(widget.projectId)).value?.name ??
        'this project';
    final typed = parseAmountText(_amount.text);
    final effect =
        _category == null ||
            typed == null ||
            validateCostAmount(_amount.text) != null
        ? null
        : costEffect(
            line: _lineFor(budget, _category!),
            categoryName: _category!.name,
            amount: roundMoney(typed),
            currency: currency,
          );
    return PageBody(
      children: [
        Text(
          'A cost that was paid for $projectName, such as equipment, a subcontractor or overheads. It is added to the budget\'s spent amount straight away. For material, use a purchase or log what was used.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickerField(
                label: 'Budget category',
                icon: Icons.category_outlined,
                value: _category?.name,
                placeholder: 'Choose the category',
                enabled: !_saving,
                onTap: () => _pickCategory(categories, budget),
              ),
              if (_categoryError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    _categoryError!,
                    style: AppType.helper.copyWith(color: c.danger),
                  ),
                ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'What was it for?',
                controller: _description,
                enabled: !_saving,
                validator: validateCostDescription,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Amount ($currency)',
                controller: _amount,
                enabled: !_saving,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: validateCostAmount,
                onChanged: (_) => setState(() {}),
              ),
              if (_category != null && effect == null && typed == null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    _budgetNow(budget, currency),
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                ),
              if (effect != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        effect.over
                            ? Icons.error_outline_rounded
                            : effect.warning
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline_rounded,
                        size: 18,
                        color: budgetTone(
                          c,
                          over: effect.over,
                          warning: effect.warning,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          effect.text,
                          style: AppType.helper.copyWith(
                            color: budgetTone(
                              c,
                              over: effect.over,
                              warning: effect.warning,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Date',
                icon: Icons.event_rounded,
                value: Fmt.day(_date),
                enabled: !_saving,
                onTap: _pickDate,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Supplier or payee (optional)',
                controller: _vendor,
                enabled: !_saving,
                validator: (v) => validateCostOptional(v, max: 100),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Receipt or invoice number (optional)',
                controller: _reference,
                enabled: !_saving,
                validator: (v) => validateCostOptional(v, max: 60),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Notes (optional)',
                controller: _notes,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                validator: (v) => validateCostOptional(v, max: 500),
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Record cost',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(budget, projectName),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'A receipt photo cannot be attached from the app yet.',
                textAlign: TextAlign.center,
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Where the chosen category stands before anything is typed.
  String _budgetNow(ProjectBudget? budget, String currency) {
    final line = _lineFor(budget, _category!);
    if (line == null) {
      return '${_category!.name} has no budget on this project.';
    }
    return '${_category!.name}: ${Fmt.money(line.actual, currency)} of ${Fmt.money(line.planned, currency)} spent (${line.percentUsed}%).';
  }
}

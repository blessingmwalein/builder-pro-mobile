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
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../application/change_requests_providers.dart';
import '../data/change_request_models.dart';
import 'new_change_request_screen.dart';

/// The most a money or days field accepts: far above any real change, below
/// what the server's columns can hold, so a slipped finger cannot inflate a
/// project's budget or push its end date years out.
const double maxCrAmount = 999999999.99;
const int maxCrDays = 3650;

/// Optional amount: not negative, at most two decimals, not absurdly large.
String? validateCrAmount(String? raw) {
  final problem = validateCrNumber(raw, decimals: 2);
  if (problem != null) return problem;
  final v = parseCrAmount(raw);
  if (v != null && v > maxCrAmount) return 'That is too large';
  return null;
}

/// Optional whole number of days, not negative, not absurdly large.
String? validateCrDays(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final v = int.tryParse(text);
  if (v == null) return 'Enter a whole number of days';
  if (v < 0) return 'Cannot be negative';
  if (v > maxCrDays) return 'That is too many days';
  return null;
}

/// The amount typed, or null when empty or not a number.
double? parseCrAmount(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return null;
  return (v * 100).round() / 100;
}

/// The days typed, or null when empty or not a whole number.
int? parseCrDays(String? raw) => int.tryParse((raw ?? '').trim());

/// The two steps that take a request forward from this screen.
enum CrDecision { review, approve }

/// "Start review" and "Approve" on a change request. Neither is ever sent
/// twice: see [ChangeRequestActions]. Approving can add to the project's budget
/// and push its end date, so it states that and asks first.
class ChangeRequestDecisionScreen extends ConsumerStatefulWidget {
  const ChangeRequestDecisionScreen({
    super.key,
    required this.projectId,
    required this.requestId,
    required this.decision,
  });
  final String projectId;
  final String requestId;
  final CrDecision decision;

  @override
  ConsumerState<ChangeRequestDecisionScreen> createState() =>
      _ChangeRequestDecisionScreenState();
}

class _ChangeRequestDecisionScreenState
    extends ConsumerState<ChangeRequestDecisionScreen> {
  final _form = GlobalKey<FormState>();
  final _cost = TextEditingController();
  final _days = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  bool get _approving => widget.decision == CrDecision.approve;

  @override
  void dispose() {
    _cost.dispose();
    _days.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(ChangeRequestDetail d) async {
    if (_saving || _confirming) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final cost = parseCrAmount(_cost.text);
    final days = parseCrDays(_days.text);
    final notes = _notes.text;

    if (_approving) {
      final currency = ref.read(currencyProvider);
      // Set before the sheet opens: a second activation in the same frame would
      // otherwise open a second confirmation.
      _confirming = true;
      final bool ok;
      try {
        ok = await confirmAction(
          context,
          title: 'Approve ${d.summary.number}?',
          message:
              '${changeApprovalEffect(cost: cost, days: days, money: (v) => Fmt.money(v, currency))} '
              'Approving cannot be undone from this app.',
          confirmLabel: 'Approve',
        );
      } finally {
        _confirming = false;
      }
      if (!ok || !mounted || _saving) return;
    }

    setState(() => _saving = true);
    try {
      final actions = ref.read(changeRequestActionsProvider);
      final note = _approving
          ? await actions.approve(
              widget.projectId,
              widget.requestId,
              approvedCost: cost,
              approvedDays: days,
              notes: notes,
            )
          : await actions.review(
              widget.projectId,
              widget.requestId,
              estimatedCost: cost,
              estimatedDays: days,
              notes: notes,
            );
      if (!mounted) return;
      Snack.show(
        context,
        note ?? (_approving ? 'Change request approved.' : 'Review started.'),
      );
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
        .hasAny(Feature.changeRequests);
    final key = (projectId: widget.projectId, id: widget.requestId);
    final detail = ref.watch(changeRequestDetailProvider(key));
    final step = _approving ? 'Approve' : 'Start review';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value == null
              ? step
              : '$step · ${detail.value!.summary.number}',
        ),
      ),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot review change requests.',
              )
            : detail.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 100),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(changeRequestDetailProvider(key)),
                ),
                data: (d) {
                  final expected = _approving
                      ? CrStatus.underReview
                      : CrStatus.submitted;
                  if (d.summary.status != expected && !_saving) {
                    return EmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'Not ready for this step',
                      message:
                          'This change request is ${statusInfo(d.summary.status).label.toLowerCase()}.',
                    );
                  }
                  return _body(d);
                },
              ),
      ),
    );
  }

  Widget _body(ChangeRequestDetail d) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final s = d.summary;
    String days(int n) => '$n ${n == 1 ? 'day' : 'days'}';
    final linesTotal = d.itemsTotal;

    return PageBody(
      children: [
        Text(s.title, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(s.status),
            Text(s.number, style: AppType.label.copyWith(color: c.textMuted)),
            Text(
              crTypeLabel(s.type),
              style: AppType.label.copyWith(color: c.textMuted),
            ),
          ],
        ),
        if (d.description.isNotEmpty) ...[
          const SectionHeader('WHAT IS ASKED FOR'),
          Text(d.description, style: AppType.body.copyWith(color: c.text)),
        ],
        const SectionHeader('SO FAR'),
        AppCard(
          child: Column(
            children: [
              AdaptiveRow(
                start: Text(
                  'Requested by',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
                end: Text(
                  s.requestedBy,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
              ),
              if (linesTotal != null)
                AdaptiveRow(
                  start: Text(
                    'Cost lines add up to',
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                  end: Text(
                    Fmt.money(linesTotal, currency),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
              if (s.estimatedCost != null)
                AdaptiveRow(
                  start: Text(
                    'Estimated cost',
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                  end: Text(
                    Fmt.money(s.estimatedCost!, currency),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
              if (s.estimatedDays != null)
                AdaptiveRow(
                  start: Text(
                    'Estimated time',
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                  end: Text(
                    days(s.estimatedDays!),
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                ),
              if (d.reviewNotes != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    d.reviewNotes!,
                    style: AppType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: _approving
                    ? 'Approved cost (optional)'
                    : 'Your estimate of the cost (optional)',
                controller: _cost,
                hint: '0.00',
                helper: _approving
                    ? "Added to the project's budget. Leave empty to keep the budget as it is."
                    : null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: validateCrAmount,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: Space.sm,
                  children: [
                    if (_approving && s.estimatedCost != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _cost.text = s.estimatedCost!
                                    .toStringAsFixed(2),
                              ),
                        child: const Text('Use the estimate'),
                      ),
                    if (!_approving && linesTotal != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () =>
                                    _cost.text = linesTotal.toStringAsFixed(2),
                              ),
                        child: const Text('Use the cost lines total'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              AppTextField(
                label: _approving
                    ? 'Approved time in days (optional)'
                    : 'Your estimate of the time in days (optional)',
                controller: _days,
                hint: '0',
                helper: _approving
                    ? "Added to the project's end date. Leave empty to keep the date as it is."
                    : null,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: validateCrDays,
              ),
              if (_approving && s.estimatedDays != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () =>
                              setState(() => _days.text = '${s.estimatedDays}'),
                    child: const Text('Use the estimate'),
                  ),
                ),
              const SizedBox(height: Space.md),
              AppTextField(
                label: _approving
                    ? 'Approval notes (optional)'
                    : 'Notes (optional)',
                controller: _notes,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_approving) ...[
                const SizedBox(height: Space.lg),
                ListenableBuilder(
                  listenable: Listenable.merge([_cost, _days]),
                  builder: (context, _) {
                    final cost = validateCrAmount(_cost.text) == null
                        ? parseCrAmount(_cost.text)
                        : null;
                    final dayCount = validateCrDays(_days.text) == null
                        ? parseCrDays(_days.text)
                        : null;
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WHAT APPROVING DOES',
                            style: AppType.label.copyWith(color: c.textMuted),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            changeApprovalEffect(
                              cost: cost,
                              days: dayCount,
                              money: (v) => Fmt.money(v, currency),
                            ),
                            style: AppType.body.copyWith(color: c.text),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xl),
              AppButton(
                label: _approving ? 'Approve' : 'Start review',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(d),
              ),
              const SizedBox(height: Space.md),
              Text(
                _approving ? 'Approving cannot be undone from this app.' : 'Your estimate is saved on the request. You can leave both numbers empty.',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

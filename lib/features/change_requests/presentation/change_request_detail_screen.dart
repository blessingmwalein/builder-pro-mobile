import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/reason_sheet.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../application/change_requests_providers.dart';
import '../data/change_request_models.dart';

/// One change request: what is asked for, its cost and time, and what the
/// reviewer and approver said, with the next step for its status: submit a
/// draft, start a review, approve or reject, mark as implemented.
class ChangeRequestDetailScreen extends ConsumerWidget {
  const ChangeRequestDetailScreen({
    super.key,
    required this.projectId,
    required this.requestId,
  });
  final String projectId;
  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (projectId: projectId, id: requestId);
    final detail = ref.watch(changeRequestDetailProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.summary.number ?? 'Change request'),
      ),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 110),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(changeRequestDetailProvider(key)),
          ),
          data: (d) => _Body(
            projectId: projectId,
            detail: d,
            onRefresh: () async {
              ref.invalidate(changeRequestDetailProvider(key));
              try {
                await ref.read(changeRequestDetailProvider(key).future);
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

/// "Submit for review" on a draft: a status change that answers 400 when
/// repeated, so it is read back after a timeout, never resent.
class _SubmitButton extends ConsumerStatefulWidget {
  const _SubmitButton({required this.projectId, required this.requestId});
  final String projectId;
  final String requestId;

  @override
  ConsumerState<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends ConsumerState<_SubmitButton> {
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final note = await ref
          .read(changeRequestActionsProvider)
          .submit(widget.projectId, widget.requestId);
      if (mounted) Snack.show(context, note ?? 'Submitted for review.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppButton(
    label: 'Submit for review',
    icon: Icons.send_rounded,
    loading: _busy,
    onPressed: _busy ? null : _submit,
  );
}

/// The next step for a submitted, under-review or approved request. Starting a
/// review and approving open their own forms; rejecting and marking as
/// implemented ask first. Each is a status change the server answers with 400
/// when repeated, so none is ever resent (see [ChangeRequestActions]).
class _DecisionButtons extends ConsumerStatefulWidget {
  const _DecisionButtons({required this.projectId, required this.summary});
  final String projectId;
  final ChangeRequestSummary summary;

  @override
  ConsumerState<_DecisionButtons> createState() => _DecisionButtonsState();
}

class _DecisionButtonsState extends ConsumerState<_DecisionButtons> {
  /// A sheet is open (set before it opens so a second tap in the same frame
  /// cannot open another).
  bool _opening = false;
  bool _busy = false;

  Future<void> _reject() async {
    if (_busy || _opening) return;
    _opening = true;
    final String? reason;
    try {
      reason = await showReasonSheet(
        context,
        title: 'Reject this change request?',
        subtitle: 'The requester will read why. Rejecting cannot be undone from this app.',
        confirmLabel: 'Reject',
        fieldLabel: 'Why is it rejected?',
        required: true,
      );
    } finally {
      _opening = false;
    }
    if (reason == null || !mounted || _busy) return;
    await _run(
      () => ref
          .read(changeRequestActionsProvider)
          .reject(widget.projectId, widget.summary.id, notes: reason!),
      'Change request rejected.',
    );
  }

  Future<void> _implement() async {
    if (_busy || _opening) return;
    _opening = true;
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Mark as implemented?',
        message: 'This records that the approved work has been carried out. It cannot be undone from this app.',
        confirmLabel: 'Mark as implemented',
      );
    } finally {
      _opening = false;
    }
    if (!ok || !mounted || _busy) return;
    await _run(
      () => ref
          .read(changeRequestActionsProvider)
          .implement(widget.projectId, widget.summary.id),
      'Marked as implemented.',
    );
  }

  Future<void> _run(Future<String?> Function() send, String done) async {
    setState(() => _busy = true);
    try {
      final note = await send();
      if (mounted) Snack.show(context, note ?? done);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.summary;
    final base = '/projects/${widget.projectId}/change-requests/${s.id}';
    switch (s.status) {
      case CrStatus.submitted:
        return AppButton(
          label: 'Start review',
          icon: Icons.rate_review_outlined,
          onPressed: () => context.push('$base/review'),
        );
      case CrStatus.underReview:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(
              label: 'Approve',
              icon: Icons.check_rounded,
              onPressed: _busy ? null : () => context.push('$base/approve'),
            ),
            const SizedBox(height: Space.sm),
            AppButton(
              label: 'Reject',
              variant: AppButtonVariant.danger,
              loading: _busy,
              onPressed: _busy ? null : _reject,
            ),
            const SizedBox(height: Space.md),
            Text(
              'Approving can add to the project budget and push its end date.',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ],
        );
      case CrStatus.approved:
        return AppButton(
          label: 'Mark as implemented',
          icon: Icons.done_all_rounded,
          loading: _busy,
          onPressed: _busy ? null : _implement,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.detail,
    required this.onRefresh,
    required this.projectId,
  });
  final ChangeRequestDetail detail;
  final Future<void> Function() onRefresh;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final d = detail;
    final s = d.summary;
    String days(int? n) => n == null ? '—' : '$n ${n == 1 ? 'day' : 'days'}';
    String cost(double? v) => v == null ? '—' : Fmt.money(v, currency);

    return PageBody(
      onRefresh: onRefresh,
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
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact(
                'Requested by',
                '${s.requestedBy} · ${Fmt.day(s.createdAt)}',
              ),
              if (d.reviewedBy != null)
                _Fact(
                  'Reviewed by',
                  d.reviewedAt == null
                      ? d.reviewedBy!
                      : '${d.reviewedBy} · ${Fmt.day(d.reviewedAt!)}',
                ),
              // The server stores the rejecter in the approver column, so a
              // rejected request must not read "Approved by".
              if (d.rejectedAt != null)
                _Fact(
                  'Rejected',
                  d.approvedBy == null
                      ? Fmt.day(d.rejectedAt!)
                      : '${d.approvedBy} · ${Fmt.day(d.rejectedAt!)}',
                )
              else if (d.approvedBy != null)
                _Fact(
                  'Approved by',
                  d.approvedAt == null
                      ? d.approvedBy!
                      : '${d.approvedBy} · ${Fmt.day(d.approvedAt!)}',
                ),
              if (d.implementedAt != null)
                _Fact('Implemented', Fmt.day(d.implementedAt!)),
            ],
          ),
        ),
        const SectionHeader('COST AND TIME'),
        AppCard(
          child: Column(
            children: [
              AdaptiveRow(
                start: Text(
                  'Estimated cost',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
                end: Text(
                  cost(s.estimatedCost),
                  style: AppType.amount.copyWith(color: c.text),
                ),
              ),
              AdaptiveRow(
                start: Text(
                  'Estimated time',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
                end: Text(
                  days(s.estimatedDays),
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
              ),
              if (s.approvedCost != null || s.approvedDays != null) ...[
                Divider(height: Space.xl, color: c.border),
                AdaptiveRow(
                  start: Text(
                    'Approved cost',
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                  end: Text(
                    cost(s.approvedCost),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
                AdaptiveRow(
                  start: Text(
                    'Approved time',
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                  end: Text(
                    days(s.approvedDays),
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (d.description.isNotEmpty) ...[
          const SectionHeader('WHAT IS ASKED FOR'),
          Text(d.description, style: AppType.body.copyWith(color: c.text)),
        ],
        if (d.items.isNotEmpty) ...[
          SectionHeader('COST LINES ${d.items.length}'),
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
                        if (d.items[i].category != null ||
                            d.items[i].quantity != null)
                          Text(
                            [
                              if (d.items[i].category != null)
                                d.items[i].category!,
                              if (d.items[i].quantity != null)
                                '${Fmt.quantity(d.items[i].quantity!)}${d.items[i].unitCost == null ? '' : ' × ${Fmt.money(d.items[i].unitCost!, currency)}'}',
                            ].join(' · '),
                            style: AppType.helper.copyWith(color: c.textMuted),
                          ),
                      ],
                    ),
                    end: Text(
                      cost(d.items[i].estimatedCost),
                      style: AppType.amount.copyWith(color: c.text),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (d.reviewNotes != null) ...[
          const SectionHeader('REVIEW NOTES'),
          Text(d.reviewNotes!, style: AppType.body.copyWith(color: c.text)),
        ],
        if (d.approvalNotes != null) ...[
          const SectionHeader('APPROVAL NOTES'),
          Text(d.approvalNotes!, style: AppType.body.copyWith(color: c.text)),
        ],
        if (d.rejectionNotes != null) ...[
          const SectionHeader('WHY IT WAS REJECTED'),
          Text(d.rejectionNotes!, style: AppType.body.copyWith(color: c.text)),
        ],
        const SizedBox(height: Space.xl),
        if (s.status == CrStatus.draft)
          _SubmitButton(projectId: projectId, requestId: s.id)
        else
          _DecisionButtons(projectId: projectId, summary: s),
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

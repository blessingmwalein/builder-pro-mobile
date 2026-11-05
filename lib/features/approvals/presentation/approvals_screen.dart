import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/components/tick_builder.dart';
import '../application/approvals_providers.dart';
import '../data/approval_models.dart';

/// Review and decide on workers' time. Decisions are never queued offline: the
/// supervisor must see current data, and a decision feeds payroll.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  /// Entries with a decision in flight (their buttons are locked).
  final _busy = <String>{};

  ApprovalsController get _controller => ref.read(approvalsProvider.notifier);

  Future<void> _approve(ApprovalEntry e) async {
    final ok = await confirmAction(
      context,
      title: 'Approve this time?',
      message:
          '${Fmt.hours(e.totalHours)} for ${e.workerName} on ${Fmt.day(e.clockInAt)} (${e.projectName}).',
      confirmLabel: 'Approve',
    );
    if (!ok || !mounted) return;
    await _decide(e, approve: true);
  }

  Future<void> _reject(ApprovalEntry e) async {
    final reason = await showRejectSheet(context, e);
    if (reason == null || !mounted) return;
    await _decide(e, approve: false, comment: reason);
  }

  Future<void> _decide(
    ApprovalEntry e, {
    required bool approve,
    String? comment,
  }) async {
    if (!_busy.add(e.id)) return;
    setState(() {});
    try {
      await _controller.decide(e, approve: approve, comment: comment);
      if (mounted) {
        Snack.show(
          context,
          approve
              ? 'Approved ${Fmt.hours(e.totalHours)} for ${e.workerName}.'
              : 'Rejected the time for ${e.workerName}.',
        );
      }
    } on AppException catch (err) {
      if (mounted) Snack.error(context, err);
    } finally {
      _busy.remove(e.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _approveAll(WorkerApprovals group) async {
    final ok = await confirmAction(
      context,
      title: 'Approve all for ${group.workerName}?',
      message:
          '${group.entries.length} shifts, ${Fmt.hours(group.totalHours)} in total. Manual entries are included, so check them first.',
      confirmLabel: 'Approve ${group.entries.length}',
    );
    if (!ok || !mounted) return;
    var done = 0;
    for (final e in List.of(group.entries)) {
      if (!mounted) return;
      if (!_busy.add(e.id)) continue;
      setState(() {});
      try {
        await _controller.decide(e, approve: true);
        done++;
      } on AppException catch (err) {
        if (mounted) {
          Snack.show(
            context,
            'Approved $done of ${group.entries.length}. ${err.message}',
          );
        }
        _busy.remove(e.id);
        if (mounted) setState(() {});
        return; // Stop at the first problem rather than push on.
      }
      _busy.remove(e.id);
    }
    if (mounted) {
      setState(() {});
      Snack.show(context, 'Approved $done shifts for ${group.workerName}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final approvals = ref.watch(approvalsProvider);
    return approvals.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.gutter),
        child: SkeletonList(rows: 4, rowHeight: 110),
      ),
      error: (e, _) =>
          ErrorPanel(error: e, onRetry: () => _controller.refresh()),
      data: _content,
    );
  }

  Widget _content(ApprovalsState state) {
    final groups = groupByWorker(state.ready);
    final working = state.working;
    final waiting = state.ready.length;
    return PageBody(
      onRefresh: () => _controller.refresh(),
      children: [
        PageTitle(
          'Approvals',
          subtitle: waiting == 0
              ? null
              : '$waiting ${waiting == 1 ? 'shift' : 'shifts'} to review',
        ),
        if (working.isNotEmpty) ...[
          const SectionHeader('WORKING NOW'),
          for (final e in working)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _WorkingRow(entry: e),
            ),
        ],
        if (groups.isEmpty && working.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: Space.x4),
            child: EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'All caught up',
              message:
                  'No time is waiting for your decision. Pull down to refresh.',
            ),
          ),
        for (final g in groups) ...[
          SectionHeader(
            g.workerName.toUpperCase(),
            trailing: g.entries.length > 1
                ? TextButton(
                    onPressed: g.entries.any((e) => _busy.contains(e.id))
                        ? null
                        : () => _approveAll(g),
                    child: Text('Approve all ${g.entries.length}'),
                  )
                : null,
          ),
          for (final e in g.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _EntryCard(
                entry: e,
                busy: _busy.contains(e.id),
                onApprove: () => _approve(e),
                onReject: () => _reject(e),
              ),
            ),
        ],
        if (state.loadMoreError != null)
          ErrorPanel(
            error: state.loadMoreError!,
            compact: true,
            onRetry: () => _controller.loadMore(),
          ),
        if (state.hasMore && state.loadMoreError == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: AppButton(
              label: 'Show older entries',
              variant: AppButtonVariant.secondary,
              loading: state.loadingMore,
              onPressed: () => _controller.loadMore(),
            ),
          ),
      ],
    );
  }
}

class _WorkingRow extends StatelessWidget {
  const _WorkingRow({required this.entry});
  final ApprovalEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(
        children: [
          const IconTile(Icons.timer_outlined, tone: StatusTone.success),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.workerName,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                Text(
                  '${entry.projectName} · since ${Fmt.time(entry.clockInAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
          TickBuilder(
            interval: const Duration(seconds: 30),
            builder: (context, now) => Text(
              Fmt.duration(entry.workedAt(now)),
              style: AppType.amount.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final ApprovalEntry entry;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final span =
        '${Fmt.time(e.clockInAt)} – ${e.clockOutAt == null ? 'now' : Fmt.time(e.clockOutAt!)}';
    return AppCard(
      semanticLabel:
          '${e.workerName}, ${Fmt.day(e.clockInAt)}, $span, ${Fmt.hours(e.totalHours)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.day(e.clockInAt),
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    Text(
                      e.projectLabel,
                      style: AppType.bodySmall.copyWith(color: c.textMuted),
                    ),
                    if (e.taskTitle != null)
                      Text(
                        e.taskTitle!,
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.hours(e.totalHours),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                  Text(
                    span,
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                  if (e.breakMinutes > 0)
                    Text(
                      '${e.breakMinutes} min break',
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ],
          ),
          if (e.isManual || (e.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (e.isManual)
                  StatusBadge(
                    label: 'Entered by hand',
                    tone: StatusTone.warning,
                  ),
                if ((e.notes ?? '').isNotEmpty)
                  Text(
                    e.notes!,
                    style: AppType.bodySmall.copyWith(color: c.text),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              AppButton(
                label: 'Reject',
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: busy ? null : onReject,
              ),
              AppButton(
                label: 'Approve',
                compact: true,
                expand: false,
                icon: Icons.check_rounded,
                loading: busy,
                onPressed: busy ? null : onApprove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks why the time is being rejected. Returns the reason (possibly empty), or
/// null when cancelled.
Future<String?> showRejectSheet(BuildContext context, ApprovalEntry entry) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _RejectSheet(entry: entry),
  );
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.entry});
  final ApprovalEntry entry;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = widget.entry;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.xxl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reject this time?',
            style: AppType.sectionTitle.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.sm),
          Text(
            '${e.workerName} · ${Fmt.day(e.clockInAt)} · ${Fmt.hours(e.totalHours)}',
            style: AppType.body.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Tell the worker what to fix',
            ),
          ),
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Reject',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          ),
          const SizedBox(height: Space.sm),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/stages_providers.dart';
import '../data/stage_models.dart';

/// The stages of a project, grouped by workflow. With `projects.update` a stage
/// can be started, completed or skipped (the same three moves the web app
/// offers); approving a stage that needs approval needs `projects.*`.
///
/// Shows nothing when the project has no stages.
class StagesSection extends ConsumerStatefulWidget {
  const StagesSection({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<StagesSection> createState() => _StagesSectionState();
}

class _StagesSectionState extends ConsumerState<StagesSection> {
  /// The stage being changed. One at a time, so a double tap sends once.
  String? _busy;

  Future<void> _run(
    ProjectStage stage,
    Future<String?> Function() action,
    String success,
  ) async {
    if (_busy != null) return;
    setState(() => _busy = stage.id);
    try {
      final note = await action();
      if (mounted) Snack.show(context, note ?? success);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setStatus(
    ProjectStage s,
    String status,
    String success, {
    String? confirmTitle,
    String? confirmMessage,
    String? confirmLabel,
  }) async {
    if (_busy != null) return;
    if (confirmTitle != null) {
      final ok = await confirmAction(
        context,
        title: confirmTitle,
        message: confirmMessage ?? '',
        confirmLabel: confirmLabel ?? 'Confirm',
      );
      if (!ok || !mounted) return;
    }
    await _run(s, () async {
      await ref
          .read(stageActionsProvider)
          .setStatus(widget.projectId, s.id, status);
      return null;
    }, success);
  }

  Future<void> _approve(ProjectStage s) async {
    if (_busy != null) return;
    final ok = await confirmAction(
      context,
      title: 'Approve “${s.name}”?',
      message: 'Approving completes this stage.',
      confirmLabel: 'Approve',
    );
    if (!ok || !mounted) return;
    await _run(
      s,
      () => ref.read(stageActionsProvider).approve(widget.projectId, s.id),
      'Stage approved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stages = ref.watch(projectStagesProvider(widget.projectId));
    return stages.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.xl),
        child: SkeletonList(rows: 2, rowHeight: 92),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: ErrorPanel(
          error: e,
          compact: true,
          onRetry: () =>
              ref.invalidate(projectStagesProvider(widget.projectId)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final c = context.colors;
        final perms = ref.watch(permissionsProvider);
        final canUpdate = perms.hasAny(Feature.stagesUpdate);
        final canApprove = perms.hasAny(Feature.stagesApprove);
        final done = list.where((s) => s.isFinished).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader('STAGES $done of ${list.length} done'),
            for (final g in groupStages(list)) ...[
              Padding(
                padding: const EdgeInsets.only(top: Space.sm, bottom: Space.sm),
                child: Text(
                  '${g.label.toUpperCase()} · ${g.finished} of ${g.stages.length}',
                  style: AppType.overline.copyWith(color: c.textMuted),
                ),
              ),
              for (final s in g.stages)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _StageCard(
                    stage: s,
                    busy: _busy == s.id,
                    locked: _busy != null,
                    canUpdate: canUpdate,
                    canApprove: canApprove,
                    onStart: () => _setStatus(
                      s,
                      StageStatus.inProgress,
                      'Started “${s.name}”.',
                    ),
                    onComplete: () => _setStatus(
                      s,
                      StageStatus.completed,
                      'Completed “${s.name}”.',
                      confirmTitle: 'Complete “${s.name}”?',
                      confirmMessage: 'It will be marked completed. This app cannot reopen a completed stage.',
                      confirmLabel: 'Complete',
                    ),
                    onSkip: () => _setStatus(
                      s,
                      StageStatus.skipped,
                      'Skipped “${s.name}”.',
                      confirmTitle: 'Skip “${s.name}”?',
                      confirmMessage: 'It will be marked skipped. This app cannot bring a skipped stage back.',
                      confirmLabel: 'Skip',
                    ),
                    onApprove: () => _approve(s),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.busy,
    required this.locked,
    required this.canUpdate,
    required this.canApprove,
    required this.onStart,
    required this.onComplete,
    required this.onSkip,
    required this.onApprove,
  });

  final ProjectStage stage;
  final bool busy;

  /// Another stage is being changed.
  final bool locked;
  final bool canUpdate;
  final bool canApprove;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onApprove;

  String? _dates() {
    final s = stage;
    if (s.actualStart != null || s.actualEnd != null) {
      return [
        if (s.actualStart != null) 'Started ${Fmt.calendarDay(s.actualStart!)}',
        if (s.actualEnd != null) 'finished ${Fmt.calendarDay(s.actualEnd!)}',
      ].join(' · ');
    }
    if (s.plannedStart != null || s.plannedEnd != null) {
      final range = [
        if (s.plannedStart != null) Fmt.calendarDay(s.plannedStart!),
        if (s.plannedEnd != null) Fmt.calendarDay(s.plannedEnd!),
      ].join(' → ');
      return 'Planned $range';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stage;
    final dates = _dates();
    final actions = <Widget>[
      if (canUpdate && s.status == StageStatus.pending) ...[
        AppButton(
          label: 'Start',
          compact: true,
          expand: false,
          icon: Icons.play_arrow_rounded,
          loading: busy,
          onPressed: locked ? null : onStart,
        ),
        AppButton(
          label: 'Skip',
          compact: true,
          expand: false,
          variant: AppButtonVariant.secondary,
          onPressed: locked ? null : onSkip,
        ),
      ],
      if (canUpdate &&
          s.status == StageStatus.inProgress &&
          !s.requiresApproval)
        AppButton(
          label: 'Complete',
          compact: true,
          expand: false,
          icon: Icons.check_rounded,
          loading: busy,
          onPressed: locked ? null : onComplete,
        ),
      if (canApprove &&
          s.status == StageStatus.inProgress &&
          s.requiresApproval)
        AppButton(
          label: 'Approve stage',
          compact: true,
          expand: false,
          icon: Icons.verified_outlined,
          loading: busy,
          onPressed: locked ? null : onApprove,
        ),
    ];
    return AppCard(
      semanticLabel:
          '${s.name}, ${statusInfo(s.status).label}${s.awaitsApproval ? ', needs approval' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              s.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: StatusBadge.status(s.status),
          ),
          if (dates != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                dates,
                style: AppType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          if (s.awaitsApproval)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Needs approval to complete',
                style: AppType.helper.copyWith(color: c.warning),
              ),
            ),
          if (s.isCompleted && s.approvedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                s.approvedBy == null
                    ? 'Approved ${Fmt.day(s.approvedAt!)}'
                    : 'Approved by ${s.approvedBy} · ${Fmt.day(s.approvedAt!)}',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ),
          if (s.notes != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                s.notes!,
                style: AppType.body.copyWith(color: c.text),
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}

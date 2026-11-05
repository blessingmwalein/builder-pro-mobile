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
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/equipment_providers.dart';
import '../data/equipment_models.dart';

/// One piece of equipment: where it is, its recent history, and (with
/// `materials.manage`) assigning it to a project or taking it back.
class EquipmentDetailScreen extends ConsumerStatefulWidget {
  const EquipmentDetailScreen({super.key, required this.equipmentId});
  final String equipmentId;

  @override
  ConsumerState<EquipmentDetailScreen> createState() =>
      _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends ConsumerState<EquipmentDetailScreen> {
  bool _busy = false;

  Future<void> _return(EquipmentDetail d, EquipmentAssignment a) async {
    final ok = await confirmAction(
      context,
      title: 'Mark ${d.summary.name} as returned?',
      message:
          'It was assigned to ${a.projectName} from ${Fmt.calendarDay(a.startDate)}. Once returned it can be assigned to another project.',
      confirmLabel: 'Mark returned',
    );
    if (!ok || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final note = await ref
          .read(equipmentActionsProvider)
          .returnItem(d.summary.id, a.id);
      if (mounted) Snack.show(context, note ?? 'Marked as returned.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(equipmentDetailProvider(widget.equipmentId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.name ?? 'Equipment')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 120),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () =>
                ref.invalidate(equipmentDetailProvider(widget.equipmentId)),
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(EquipmentDetail d) {
    final c = context.colors;
    final perms = ref.watch(permissionsProvider);
    final canManage = perms.hasAny(Feature.equipmentManage);
    final s = d.summary;
    final open = d.openAssignments;
    final current = open.isEmpty ? null : open.first;
    final returnable = d.returnable;
    final canAssign = canManage && s.isAvailable;
    // Assigning needs a project to choose from.
    final canChooseProject = perms.hasAny(Feature.projects);

    return PageBody(
      onRefresh: () async {
        ref.invalidate(equipmentDetailProvider(widget.equipmentId));
        try {
          await ref.read(equipmentDetailProvider(widget.equipmentId).future);
        } catch (_) {
          // The error state is shown by the screen itself.
        }
      },
      children: [
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(s.status),
            if (s.categoryName != null)
              Text(
                s.categoryName!,
                style: AppType.label.copyWith(color: c.textMuted),
              ),
            if (s.serialNumber != null)
              Text(
                'Serial ${s.serialNumber}',
                style: AppType.label.copyWith(color: c.textMuted),
              ),
          ],
        ),
        if (d.description != null) ...[
          const SizedBox(height: Space.md),
          Text(d.description!, style: AppType.body.copyWith(color: c.text)),
        ],
        if (current != null) ...[
          const SectionHeader('WHERE IT IS'),
          AppCard(child: _AssignmentFacts(a: current)),
          if (open.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'This item has more than one open assignment. Sort that out on the web app.',
                style: AppType.helper.copyWith(color: c.warning),
              ),
            ),
        ],
        const SizedBox(height: Space.xl),
        if (canAssign && canChooseProject)
          AppButton(
            label: 'Assign to a project',
            icon: Icons.add_location_alt_outlined,
            onPressed: () => context.push('/equipment/${s.id}/assign'),
          ),
        if (canManage && returnable != null)
          AppButton(
            label: 'Mark returned',
            icon: Icons.keyboard_return_rounded,
            loading: _busy,
            onPressed: _busy ? null : () => _return(d, returnable),
          ),
        if (canAssign && !canChooseProject)
          Text(
            'Assigning needs access to projects, which your role does not have.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        if (canManage && s.isInUse && returnable == null && open.length <= 1)
          Text(
            'This item is in use, but its open assignment is not in the recent list. Return it on the web app.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        if (canManage) ...[
          const SizedBox(height: Space.sm),
          if (!s.isInUse) _StatusButtons(equipment: s),
          AppButton(
            label: 'Edit details',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => context.push('/equipment/${s.id}/edit'),
          ),
        ],
        if (d.assignments.isNotEmpty) ...[
          SectionHeader('RECENT ASSIGNMENTS ${d.assignments.length}'),
          for (final a in d.assignments)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(child: _AssignmentFacts(a: a, history: true)),
            ),
        ],
      ],
    );
  }
}

/// Moving an item that is not out on a project between available, maintenance
/// and retired. Each is a plain status change, confirmed first.
class _StatusButtons extends ConsumerStatefulWidget {
  const _StatusButtons({required this.equipment});
  final EquipmentSummary equipment;

  @override
  ConsumerState<_StatusButtons> createState() => _StatusButtonsState();
}

class _StatusButtonsState extends ConsumerState<_StatusButtons> {
  bool _busy = false;

  Future<void> _move(String status, String title, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await confirmAction(
        context,
        title: title,
        message: message,
        confirmLabel: 'Confirm',
      );
      if (!ok || !mounted) return;
      await ref
          .read(equipmentActionsProvider)
          .setStatus(widget.equipment.id, status);
      if (mounted) Snack.show(context, 'Status changed.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.equipment;
    final buttons = <Widget>[
      if (e.status == EquipmentStatus.available)
        AppButton(
          label: 'Put in maintenance',
          icon: Icons.build_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: _busy
              ? null
              : () => _move(
                  EquipmentStatus.maintenance,
                  'Put ${e.name} in maintenance?',
                  'It cannot be assigned to a project until it is available again.',
                ),
        ),
      if (e.status == EquipmentStatus.maintenance)
        AppButton(
          label: 'Mark as available',
          icon: Icons.check_circle_outline_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: _busy
              ? null
              : () => _move(
                  EquipmentStatus.available,
                  'Mark ${e.name} as available?',
                  'It can then be assigned to a project.',
                ),
        ),
      if (e.status == EquipmentStatus.retired)
        AppButton(
          label: 'Return to service',
          icon: Icons.restore_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: _busy
              ? null
              : () => _move(
                  EquipmentStatus.available,
                  'Return ${e.name} to service?',
                  'It becomes available to assign to a project again.',
                ),
        ),
      if (e.status != EquipmentStatus.retired)
        AppButton(
          label: 'Retire',
          icon: Icons.archive_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: _busy
              ? null
              : () => _move(
                  EquipmentStatus.retired,
                  'Retire ${e.name}?',
                  'It stays in the list as retired and cannot be assigned. You can return it to service later.',
                ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in buttons) ...[b, const SizedBox(height: Space.sm)],
      ],
    );
  }
}

class _AssignmentFacts extends StatelessWidget {
  const _AssignmentFacts({required this.a, this.history = false});
  final EquipmentAssignment a;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final range = StringBuffer(Fmt.calendarDay(a.startDate));
    if (a.returnedAt != null) {
      range.write(' → returned ${Fmt.day(a.returnedAt!)}');
    } else if (a.endDate != null) {
      range.write(' → due back ${Fmt.calendarDay(a.endDate!)}');
    } else {
      range.write(' → ongoing');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.projectName, style: AppType.bodyStrong.copyWith(color: c.text)),
        const SizedBox(height: Space.xs),
        Text(
          range.toString(),
          style: AppType.bodySmall.copyWith(color: c.textMuted),
        ),
        Text(
          'Assigned by ${a.assignedBy}',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        if (a.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(a.notes!, style: AppType.body.copyWith(color: c.text)),
          ),
      ],
    );
  }
}

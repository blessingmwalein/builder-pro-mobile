import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/reason_sheet.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/status_badge.dart';
import '../application/project_actions.dart';
import '../application/projects_providers.dart';
import '../data/project_models.dart';
import 'person_picker.dart';

/// What each status means, in the words shown beside it.
String _statusMeaning(String status) => switch (status) {
  ProjectStatus.draft => 'Not started yet. Planning only.',
  ProjectStatus.active => 'Work is under way.',
  ProjectStatus.onHold => 'Paused for now. Nothing is lost.',
  ProjectStatus.completed =>
    'Finished. This closes the project with a final cost summary.',
  ProjectStatus.archived => 'Put away. Nothing is deleted.',
  _ => '',
};

/// "Change status" on a project: choose the new status, read what it does,
/// confirm. Completed is a closing step (it also records the end date and a final
/// cost summary) and offers closing notes; the others only change the status.
///
/// The caller holds its own busy flag around this, so a second tap cannot start
/// a second change while one is open or being sent.
Future<void> changeProjectStatus(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary p,
) async {
  final target = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _StatusSheet(current: p.status),
  );
  if (target == null || !context.mounted) return;

  final actions = ref.read(projectActionsProvider);
  final name = ProjectStatus.label(target);
  try {
    final String? note;
    if (target == ProjectStatus.completed) {
      final open = ref
          .read(projectTasksProvider(p.id))
          .value
          ?.items
          .where((t) => !t.isDone)
          .length;
      final notes = await showReasonSheet(
        context,
        title: 'Mark ${p.name} as completed?',
        subtitle:
            'The project is closed: it is marked 100% complete, today is recorded as its end date, and a final cost summary is saved. Tasks are not changed.'
            '${open == null || open == 0 ? '' : ' $open ${open == 1 ? 'task is' : 'tasks are'} still open.'}',
        confirmLabel: 'Mark as completed',
        fieldLabel: 'Closing notes (optional)',
        hint: 'Anything worth keeping with the final summary',
        destructive: false,
      );
      if (notes == null || !context.mounted) return;
      note = await actions.close(p, notes: notes);
    } else {
      final leaving = p.status == ProjectStatus.completed
          ? ' Its progress stays at 100% and the record saved when it was closed is kept.'
          : '';
      final ok = await confirmAction(
        context,
        title: 'Change the status to $name?',
        message:
            '${p.name} goes from ${ProjectStatus.label(p.status)} to $name. ${_statusMeaning(target)}$leaving',
        confirmLabel: 'Set to $name',
        destructive: target == ProjectStatus.archived,
      );
      if (!ok || !context.mounted) return;
      note = await actions.changeStatus(p, target);
    }
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      Snack.show(context, note ?? '${p.name} is now $name.');
    }
  } on AppException catch (e) {
    if (context.mounted) Snack.error(context, e);
  }
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Change the status',
            style: AppType.sectionTitle.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Text(
                'Now',
                style: AppType.bodySmall.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: Space.sm),
              StatusBadge.status(current),
            ],
          ),
          const SizedBox(height: Space.md),
          for (final s in ProjectStatus.all)
            if (s != current)
              InkWell(
                onTap: () => Navigator.of(context).pop(s),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: Sizes.touchTarget + 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 112,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StatusBadge.status(s),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _statusMeaning(s),
                            style: AppType.bodySmall.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// "Assign a manager" (or change one): choose a person, confirm, save. Seeing
/// everyone in the company needs permission to view the team; without it only the
/// project's own team can be chosen.
Future<void> assignProjectManager(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary p,
) async {
  final hasDirectory = ref.read(permissionsProvider).hasAny(Feature.team);
  final choice = await choosePerson(
    context,
    title: p.projectManagerId == null
        ? 'Choose the project manager'
        : 'Choose a new project manager',
    directory: hasDirectory,
    members: p.members,
    selectedId: p.projectManagerId,
  );
  if (choice == null || !context.mounted) return;
  final onTeam = p.members.any((m) => m.id == choice.id);
  final ok = await confirmAction(
    context,
    title: p.projectManagerId == null
        ? 'Make ${choice.name} the project manager?'
        : 'Change the project manager to ${choice.name}?',
    message:
        '${choice.name} is set as the manager of ${p.name}.'
        '${onTeam ? '' : ' They are not on the project team, and this does not add them to it.'}',
    confirmLabel: 'Assign manager',
  );
  if (!ok || !context.mounted) return;
  try {
    final note = await ref
        .read(projectActionsProvider)
        .assignManager(p, choice.id);
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      Snack.show(context, note ?? '${choice.name} is now the project manager.');
    }
  } on AppException catch (e) {
    if (context.mounted) Snack.error(context, e);
  }
}

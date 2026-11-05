import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../projects/application/projects_providers.dart';
import '../application/tasks_providers.dart';
import '../data/task_models.dart';

/// Choose who works on a task, from the project's team. Each tap is saved at
/// once; the list reflects what the server has.
Future<void> showAssigneeSheet(
  BuildContext context, {
  required String taskId,
  required String projectId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _AssigneeSheet(taskId: taskId, projectId: projectId),
  );
}

class _AssigneeSheet extends ConsumerStatefulWidget {
  const _AssigneeSheet({required this.taskId, required this.projectId});
  final String taskId;
  final String projectId;

  @override
  ConsumerState<_AssigneeSheet> createState() => _AssigneeSheetState();
}

class _AssigneeSheetState extends ConsumerState<_AssigneeSheet> {
  /// People whose change is in flight (their row is locked).
  final _busy = <String>{};

  Future<void> _toggle(TaskAssignee person, bool assigned) async {
    if (!_busy.add(person.id)) return;
    setState(() {});
    try {
      await ref
          .read(taskDetailProvider(widget.taskId).notifier)
          .setAssigned(person, assigned: assigned);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      _busy.remove(person.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final team = ref.watch(projectDetailProvider(widget.projectId));
    final detail = ref.watch(taskDetailProvider(widget.taskId)).value;
    final assigned = detail?.task.assignees ?? const <TaskAssignee>[];
    final assignedIds = assigned.map((a) => a.id).toSet();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xxl,
              Space.sm,
              Space.xxl,
              Space.md,
            ),
            child: Text(
              'Who is working on this?',
              style: AppType.sectionTitle.copyWith(color: c.text),
            ),
          ),
          Flexible(
            child: team.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.xxl),
                child: SkeletonList(rows: 3, rowHeight: 52),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: ErrorPanel(
                  error: e,
                  compact: true,
                  onRetry: () =>
                      ref.invalidate(projectDetailProvider(widget.projectId)),
                ),
              ),
              data: (project) {
                // The project team, plus anyone already on the task who is no
                // longer on the team (so they can still be removed).
                final people = <TaskAssignee>[
                  for (final m in project.members)
                    TaskAssignee(id: m.id, name: m.name),
                  for (final a in assigned)
                    if (!project.members.any((m) => m.id == a.id)) a,
                ];
                if (people.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(Space.xxl),
                    child: Text(
                      'This project has no team yet. Add people to the project on the web app first.',
                      style: AppType.body.copyWith(color: c.textMuted),
                    ),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in people)
                      _PersonRow(
                        person: p,
                        selected: assignedIds.contains(p.id),
                        busy: _busy.contains(p.id),
                        onTap: () => _toggle(p, !assignedIds.contains(p.id)),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xxl,
              Space.md,
              Space.xxl,
              Space.xxl,
            ),
            child: AppButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final TaskAssignee person;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      checked: selected,
      enabled: !busy,
      label: person.name,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.touchTarget + 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: busy
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: c.primary,
                          ),
                        )
                      : Icon(
                          selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: selected ? c.primary : c.borderStrong,
                        ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Text(
                    person.name,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../projects/application/projects_providers.dart';
import '../../projects/data/project_models.dart';
import '../application/task_authoring.dart';
import '../application/tasks_providers.dart';
import '../data/task_models.dart';
import '../../../shared/components/status_badge.dart';
import '../../stages/application/stages_providers.dart';
import '../../stages/data/stage_models.dart';

/// Validation message for the "estimated hours" field, or null when acceptable.
/// The API stores at most 2 decimals.
String? validateHours(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null; // optional
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number of hours';
  if (v <= 0) return 'Enter more than zero';
  if (v > 10000) return 'That is too many hours. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

String? validateTitle(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Give the task a title';
  if (t.length > 200) return 'Keep the title under 200 characters';
  return null;
}

/// Noon local time on [day], so the due date stays on the same calendar day for
/// any timezone within 12 hours of the phone's (the API stores an instant).
DateTime dueInstant(DateTime day) => DateTime(day.year, day.month, day.day, 12);

/// New task (when [editing] is null) or the details of an existing one.
///
/// Creating is never repeated blindly; editing needs `tasks.*`. The API cannot
/// clear a due date or an estimate once set, and the form says so.
class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, required this.projectId, this.editing});
  final String projectId;
  final TaskItem? editing;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.editing?.title);
  late final _description = TextEditingController(
    text: widget.editing?.description,
  );
  late final _hours = TextEditingController(
    text: widget.editing?.estimatedHours == null
        ? ''
        : Fmt.quantity(widget.editing!.estimatedHours!),
  );
  late String _priority = widget.editing?.priority ?? 'MEDIUM';
  late DateTime? _due = widget.editing?.dueDate?.toLocal();
  final _assignees = <PersonRef>{};

  /// The timeline stage the task is linked to (null = none).
  late String? _stageId = widget.editing?.stageId;
  bool _saving = false;
  AppException? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _pickAssignees(List<PersonRef> team) async {
    final chosen = await showModalBottomSheet<Set<PersonRef>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _PeopleSheet(team: team, selected: _assignees),
    );
    if (chosen != null && mounted) {
      setState(() {
        _assignees
          ..clear()
          ..addAll(chosen);
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final hoursText = _hours.text.trim().replaceAll(',', '.');
    final hours = hoursText.isEmpty ? null : double.parse(hoursText);
    final description = _description.text.trim();
    final authoring = ref.read(taskAuthoringProvider);

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await authoring.update(
          widget.editing!.id,
          title: _title.text.trim(),
          // An empty description is sent so it can be cleared.
          description: description,
          priority: _priority,
          dueDate: _due == null ? null : dueInstant(_due!),
          estimatedHours: hours,
          // The stage can be changed or removed, so it is always sent.
          stageId: _stageId,
          setStage: true,
        );
        ref.invalidate(taskDetailProvider(widget.editing!.id));
        if (!mounted) return;
        Snack.show(context, 'Task updated.');
        context.pop();
      } else {
        final created = await authoring.create(
          NewTaskInput(
            projectId: widget.projectId,
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
            priority: _priority,
            dueDate: _due == null ? null : dueInstant(_due!),
            estimatedHours: hours,
            assigneeIds: [for (final p in _assignees) p.id],
            stageId: _stageId,
          ),
        );
        if (!mounted) return;
        Snack.show(context, created.note ?? 'Task added.');
        context.pop();
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final perms = ref.watch(permissionsProvider);
    final allowed = _isEdit
        ? perms.hasAny(Feature.tasksEdit)
        : perms.hasAny(Feature.tasksCreate);
    final team = !_isEdit && perms.hasAny(Feature.projects)
        ? ref.watch(projectDetailProvider(widget.projectId))
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit task' : 'New task')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot change tasks.',
              )
            : PageBody(
                children: [
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          label: 'Title',
                          controller: _title,
                          hint: 'What needs doing?',
                          maxLength: 200,
                          validator: validateTitle,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Description (optional)',
                          controller: _description,
                          minLines: 3,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: Space.lg),
                        Text(
                          'Priority',
                          style: AppType.label.copyWith(color: c.text),
                        ),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final p in const [
                              'LOW',
                              'MEDIUM',
                              'HIGH',
                              'CRITICAL',
                            ])
                              ChoiceChip(
                                label: Text(_priorityLabel(p)),
                                selected: _priority == p,
                                onSelected: (_) =>
                                    setState(() => _priority = p),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Due date (optional)',
                          icon: Icons.event_rounded,
                          value: _due == null ? null : Fmt.day(_due!),
                          placeholder: 'No due date',
                          onTap: _pickDue,
                        ),
                        if (_due != null && !_isEdit)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _due = null),
                              child: const Text('Remove due date'),
                            ),
                          ),
                        if (_isEdit && widget.editing?.dueDate != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              'A due date can be changed here but not removed; use the web app to remove it.',
                              style: AppType.helper.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Estimated hours (optional)',
                          controller: _hours,
                          suffixText: 'h',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          validator: validateHours,
                        ),
                        if (_isEdit && widget.editing?.estimatedHours != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              'An estimate can be changed here but not removed.',
                              style: AppType.helper.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ),
                        if (perms.hasAny(Feature.stagesView))
                          _StagePicker(
                            projectId: widget.projectId,
                            stageId: _stageId,
                            onChanged: (id) => setState(() => _stageId = id),
                          ),
                        if (team != null) ...[
                          const SizedBox(height: Space.lg),
                          team.when(
                            loading: () => const SkeletonBox(
                              height: 52,
                              radius: Corners.md,
                            ),
                            error: (_, _) => Text(
                              'The project team could not be loaded, so people cannot be assigned now. You can assign them after saving.',
                              style: AppType.helper.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                            data: (project) => PickerField(
                              label: 'Assign to (optional)',
                              icon: Icons.group_outlined,
                              value: _assignees.isEmpty
                                  ? null
                                  : _assignees.map((p) => p.name).join(', '),
                              placeholder: project.members.isEmpty
                                  ? 'No one on this project yet'
                                  : 'Nobody yet',
                              enabled: project.members.isNotEmpty,
                              onTap: () => _pickAssignees(project.members),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: _isEdit ? 'Save changes' : 'Add task',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _priorityLabel(String p) => '${p[0]}${p.substring(1).toLowerCase()}';
}

/// "Timeline stage": links the task to one of the project's stages. Hidden when
/// the project has none or they cannot be read, so it never blocks saving.
class _StagePicker extends ConsumerWidget {
  const _StagePicker({
    required this.projectId,
    required this.stageId,
    required this.onChanged,
  });
  final String projectId;
  final String? stageId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = ref.watch(projectStagesProvider(projectId));
    return stages.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.lg),
        child: SkeletonBox(height: 52, radius: Corners.md),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        ProjectStage? current;
        for (final s in list) {
          if (s.id == stageId) current = s;
        }
        return Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: PickerField(
            label: 'Timeline stage (optional)',
            icon: Icons.timeline_rounded,
            value: stageId == null
                ? null
                : (current == null ? 'A stage of this project' : current.name),
            placeholder: 'Not linked to a stage',
            onTap: () async {
              final picked = await pickOne<ProjectStage>(
                context,
                title: 'Link to a stage',
                selected: current,
                clearLabel: 'Not linked to a stage',
                options: [
                  for (final s in list)
                    PickerOption(
                      value: s,
                      title: s.name,
                      subtitle:
                          '${workflowLabel(s.workflowCode)} · ${statusInfo(s.status).label}',
                    ),
                ],
              );
              if (picked != null) onChanged(picked.value?.id);
            },
          ),
        );
      },
    );
  }
}

class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({required this.team, required this.selected});
  final List<PersonRef> team;
  final Set<PersonRef> selected;

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  late final Set<PersonRef> _chosen = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              'Assign to',
              style: AppType.sectionTitle.copyWith(color: c.text),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in widget.team)
                  Semantics(
                    container: true,
                    checked: _chosen.contains(p),
                    label: p.name,
                    child: InkWell(
                      onTap: () => setState(() {
                        _chosen.contains(p)
                            ? _chosen.remove(p)
                            : _chosen.add(p);
                      }),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: Sizes.touchTarget + 4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.xxl,
                          ),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  _chosen.contains(p)
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  color: _chosen.contains(p)
                                      ? c.primary
                                      : c.borderStrong,
                                ),
                              ),
                              const SizedBox(width: Space.lg),
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: AppType.bodyStrong.copyWith(
                                    color: c.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
              onPressed: () => Navigator.of(context).pop(_chosen),
            ),
          ),
        ],
      ),
    );
  }
}

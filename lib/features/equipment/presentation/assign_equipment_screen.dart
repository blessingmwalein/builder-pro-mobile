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
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../projects/data/project_models.dart';
import '../../projects/presentation/project_picker.dart';
import '../application/equipment_providers.dart';

String? validateAssignNotes(String? raw) {
  if ((raw ?? '').trim().length > 500) {
    return 'Keep the note under 500 characters';
  }
  return null;
}

/// Sends an available item to a project. Never sent twice: see
/// [EquipmentActions.assign].
class AssignEquipmentScreen extends ConsumerStatefulWidget {
  const AssignEquipmentScreen({super.key, required this.equipmentId});
  final String equipmentId;

  @override
  ConsumerState<AssignEquipmentScreen> createState() =>
      _AssignEquipmentScreenState();
}

class _AssignEquipmentScreenState extends ConsumerState<AssignEquipmentScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  ProjectSummary? _project;
  late DateTime _start = _today();
  DateTime? _end;
  String? _projectError;
  String? _dateError;
  bool _saving = false;
  bool _pickingProject = false;
  AppException? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickProject() async {
    if (_pickingProject) return;
    setState(() => _pickingProject = true);
    try {
      final picked = await chooseProject(
        context,
        ref,
        title: 'Choose a project',
        selected: _project,
      );
      if (picked != null && picked.value != null && mounted) {
        setState(() {
          _project = picked.value;
          _projectError = null;
        });
      }
    } finally {
      if (mounted) setState(() => _pickingProject = false);
    }
  }

  Future<DateTime?> _pickDate(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
  }

  Future<void> _pickStart() async {
    final picked = await _pickDate(_start);
    if (picked != null && mounted) {
      setState(() {
        _start = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDate(_end ?? _start);
    if (picked != null && mounted) {
      setState(() {
        _end = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    final valid = _form.currentState!.validate();
    final projectError = _project == null ? 'Choose a project' : null;
    final dateError = _end != null && _end!.isBefore(_start)
        ? 'The return-by date cannot be before the start date'
        : null;
    setState(() {
      _projectError = projectError;
      _dateError = dateError;
    });
    if (!valid || projectError != null || dateError != null) return;
    setState(() => _saving = true);
    try {
      final note = await ref
          .read(equipmentActionsProvider)
          .assign(
            widget.equipmentId,
            projectId: _project!.id,
            start: _start,
            end: _end,
            notes: _notes.text,
          );
      if (!mounted) return;
      Snack.show(context, note ?? 'Assigned to ${_project!.name}.');
      context.pop();
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
    final allowed =
        perms.hasAny(Feature.equipmentManage) && perms.hasAny(Feature.projects);
    final detail = ref.watch(equipmentDetailProvider(widget.equipmentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value == null
              ? 'Assign equipment'
              : 'Assign ${detail.value!.summary.name}',
        ),
      ),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot assign equipment to projects.',
              )
            : detail.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 80),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(
                    equipmentDetailProvider(widget.equipmentId),
                  ),
                ),
                data: (d) => !d.summary.isAvailable && !_saving
                    ? EmptyState(
                        icon: Icons.construction_outlined,
                        title: 'Not available right now',
                        message:
                            '${d.summary.name} is ${statusInfo(d.summary.status).label.toLowerCase()}.',
                      )
                    : PageBody(
                        children: [
                          Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PickerField(
                                  label: 'Project',
                                  icon: Icons.apartment_rounded,
                                  value: _project?.label,
                                  placeholder: 'Choose a project',
                                  onTap: _pickingProject || _saving
                                      ? null
                                      : _pickProject,
                                ),
                                if (_projectError != null)
                                  _FieldError(_projectError!),
                                const SizedBox(height: Space.lg),
                                PickerField(
                                  label: 'Start date',
                                  icon: Icons.event_rounded,
                                  value: Fmt.day(_start),
                                  onTap: _saving ? null : _pickStart,
                                ),
                                const SizedBox(height: Space.lg),
                                PickerField(
                                  label: 'Return-by date (optional)',
                                  icon: Icons.event_available_rounded,
                                  value: _end == null ? null : Fmt.day(_end!),
                                  placeholder: 'No return date',
                                  onTap: _saving ? null : _pickEnd,
                                ),
                                if (_end != null)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => setState(() {
                                              _end = null;
                                              _dateError = null;
                                            }),
                                      child: const Text('Clear return date'),
                                    ),
                                  ),
                                if (_dateError != null)
                                  _FieldError(_dateError!),
                                const SizedBox(height: Space.lg),
                                AppTextField(
                                  label: 'Note (optional)',
                                  controller: _notes,
                                  hint: 'e.g. Needed for the slab pour',
                                  minLines: 2,
                                  maxLines: 4,
                                  validator: validateAssignNotes,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: Space.lg),
                                  ErrorPanel(error: _error!, compact: true),
                                ],
                                const SizedBox(height: Space.xxl),
                                AppButton(
                                  label: 'Assign',
                                  icon: Icons.check_rounded,
                                  loading: _saving,
                                  onPressed: _save,
                                ),
                                const SizedBox(height: Space.md),
                                Text(
                                  'The item shows as in use until someone marks it returned.',
                                  style: AppType.helper.copyWith(
                                    color: c.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Text(message, style: AppType.helper.copyWith(color: c.danger)),
    );
  }
}

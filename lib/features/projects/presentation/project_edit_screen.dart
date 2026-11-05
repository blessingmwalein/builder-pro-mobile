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
import '../../clients/presentation/client_picker.dart';
import '../application/project_actions.dart';
import '../application/projects_providers.dart';
import '../data/project_models.dart';

String? validateProjectName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Give the project a name';
  if (t.length > 120) return 'Keep the name under 120 characters';
  return null;
}

String? validateProjectText(String? raw, {required int max}) {
  if ((raw ?? '').trim().length > max) return 'Keep it under $max characters';
  return null;
}

/// A date the server keeps as a calendar day (UTC midnight) as the same day on
/// this phone, so it never slips a day in a time zone behind UTC.
DateTime? _asLocalDay(DateTime? t) {
  if (t == null) return null;
  final u = t.toUtc();
  return DateTime(u.year, u.month, u.day);
}

bool _sameDay(DateTime? a, DateTime? b) => a == null || b == null
    ? a == b
    : a.year == b.year && a.month == b.month && a.day == b.day;

/// Change a project's basic details: name, about, type, site, dates and client.
/// Needs `projects.*`. Only what was changed is sent. The server cannot clear a
/// date or the client, so those can be changed to another but not emptied, and
/// the form says so. The status and the manager are changed from the project
/// page.
class ProjectEditScreen extends ConsumerWidget {
  const ProjectEditScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.projectsManage);
    final detail = ref.watch(projectDetailProvider(projectId));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit project')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot change a project.',
              )
            : detail.when(
                // Keep the form (and what was typed) if the project is read
                // again while it is open.
                skipLoadingOnReload: true,
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 4, rowHeight: 64),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(projectDetailProvider(projectId)),
                ),
                data: (p) => _EditForm(project: p),
              ),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.project});
  final ProjectSummary project;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project.name);
  late final _description = TextEditingController(
    text: widget.project.description,
  );
  late final _site = TextEditingController(text: widget.project.siteAddress);
  late String? _type = widget.project.projectType;
  late DateTime? _start = _asLocalDay(widget.project.startDate);
  late DateTime? _end = _asLocalDay(widget.project.endDate);
  late String? _clientId = widget.project.clientId;
  late String? _clientName = widget.project.clientName;
  String? _dateError;
  bool _saving = false;
  AppException? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _site.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 15),
    );
  }

  Future<void> _pickType() async {
    final picked = await pickOne<String>(
      context,
      title: 'Type of project',
      selected: _type,
      options: [
        for (final t in ProjectKind.all)
          PickerOption(value: t, title: ProjectKind.label(t)),
      ],
    );
    if (picked?.value != null && mounted) setState(() => _type = picked!.value);
  }

  Future<void> _pickClient() async {
    final picked = await chooseClient(context, title: 'Choose the client');
    if (picked != null && mounted) {
      setState(() {
        _clientId = picked.id;
        _clientName = picked.name;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _dateError = _start != null && _end != null && _end!.isBefore(_start!)
          ? 'The end cannot be before the start'
          : null;
    });
    if (!_form.currentState!.validate() || _dateError != null) return;

    final p = widget.project;
    String? changed(String now, String? before) =>
        now.trim() == (before ?? '').trim() ? null : now.trim();
    final edit = ProjectEdit(
      name: changed(_name.text, p.name),
      description: changed(_description.text, p.description),
      siteAddress: changed(_site.text, p.siteAddress),
      projectType: _type == p.projectType ? null : _type,
      startDate: _sameDay(_start, _asLocalDay(p.startDate)) ? null : _start,
      endDate: _sameDay(_end, _asLocalDay(p.endDate)) ? null : _end,
      clientId: _clientId == p.clientId ? null : _clientId,
    );
    if (edit.isEmpty) {
      Snack.show(context, 'Nothing was changed.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(projectActionsProvider).updateDetails(p.id, edit);
      if (!mounted) return;
      Snack.show(context, 'Project updated.');
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
    final canPickClient = ref.watch(permissionsProvider).hasAny(Feature.crm);
    return PageBody(
      children: [
        Text(
          widget.project.label,
          style: AppType.bodyStrong.copyWith(color: c.text),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Change the basic details. The status and the project manager are changed from the project page.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Project name',
                controller: _name,
                enabled: !_saving,
                validator: validateProjectName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'About the project (optional)',
                controller: _description,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                validator: (v) => validateProjectText(v, max: 2000),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Type',
                icon: Icons.category_outlined,
                value: _type == null ? null : ProjectKind.label(_type!),
                placeholder: 'Choose the type',
                enabled: !_saving,
                onTap: _pickType,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Site address (optional)',
                controller: _site,
                enabled: !_saving,
                validator: (v) => validateProjectText(v, max: 200),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Starts',
                icon: Icons.event_available_rounded,
                value: _start == null ? null : Fmt.day(_start!),
                placeholder: 'No start date',
                enabled: !_saving,
                onTap: () async {
                  final d = await _pick(_start);
                  if (d != null && mounted) setState(() => _start = d);
                },
              ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Ends',
                icon: Icons.event_rounded,
                value: _end == null ? null : Fmt.day(_end!),
                placeholder: 'No end date',
                enabled: !_saving,
                onTap: () async {
                  final d = await _pick(_end ?? _start);
                  if (d != null && mounted) setState(() => _end = d);
                },
              ),
              if (_dateError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    _dateError!,
                    style: AppType.helper.copyWith(color: c.danger),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'A date can be changed to another, but not removed.',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ),
              if (canPickClient) ...[
                const SizedBox(height: Space.lg),
                PickerField(
                  label: 'Client',
                  icon: Icons.business_outlined,
                  value: _clientName,
                  placeholder: 'No client',
                  enabled: !_saving,
                  onTap: _pickClient,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

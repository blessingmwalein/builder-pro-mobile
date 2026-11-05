import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../time/data/time_models.dart';
import '../application/materials_providers.dart';
import '../data/material_models.dart';
import '../../../core/permissions/feature_permissions.dart';

/// Parses what a worker types into a quantity. Accepts a comma as the decimal
/// mark (common on phones in many regions). Null when it is not a usable number.
double? parseQuantity(String raw) {
  final cleaned = raw.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null || !v.isFinite) return null;
  return v;
}

/// Validation message for a quantity field, or null when it is acceptable.
/// The API stores at most 3 decimals.
String? validateQuantity(String? raw) {
  final v = parseQuantity(raw ?? '');
  if (v == null) return 'Enter how much you used';
  if (v <= 0) return 'Enter more than zero';
  if (v > 1000000) return 'That is too large. Check the number';
  final text = (raw ?? '').trim().replaceAll(',', '.');
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 3) return 'Use at most 3 decimals';
  return null;
}

/// Log material used on a project. Confirms first because it changes stock and
/// project cost for the whole company.
class LogUsageScreen extends ConsumerStatefulWidget {
  const LogUsageScreen({super.key, required this.material});
  final MaterialItem material;

  @override
  ConsumerState<LogUsageScreen> createState() => _LogUsageScreenState();
}

class _LogUsageScreenState extends ConsumerState<LogUsageScreen> {
  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _notes = TextEditingController();
  ProjectRef? _project;
  bool _saving = false;
  AppException? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(ProjectRef? project) async {
    if (_saving) return;
    setState(() => _error = null);
    if (project == null) {
      Snack.show(context, 'Choose the project first.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    final qty = parseQuantity(_quantity.text)!;
    final m = widget.material;

    final offline = ref.read(connectivityProvider).value == false;
    final ok = await confirmAction(
      context,
      title: 'Log this usage?',
      message:
          '${Fmt.quantity(qty)} ${m.unit} of ${m.name} on ${project.name}. '
          'This reduces stock and is added to the project cost.'
          '${offline ? ' There is no connection, so it is saved on this phone and sent when there is one.' : ''}',
      confirmLabel: 'Log usage',
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(materialUsageActionsProvider)
          .logUsage(
            material: m,
            projectId: project.id,
            projectName: project.name,
            quantity: qty,
            notes: _notes.text,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Snack.show(
        context,
        result.note ?? 'Logged ${Fmt.quantity(qty)} ${m.unit} of ${m.name}.',
        // A usage saved on the phone is not recorded yet: say so, don't tick.
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
    final c = context.colors;
    final m = widget.material;
    final projects = ref.watch(workProjectsProvider);
    final loadingProjects = ref.watch(tasksProvider).isLoading;
    final project = _project ?? (projects.length == 1 ? projects.first : null);
    final qty = parseQuantity(_quantity.text);
    final overStock = qty != null && qty > m.stockOnHand;

    return Scaffold(
      appBar: AppBar(title: const Text('Log material')),
      body: SafeArea(
        child: PageBody(
          children: [
            AppCard(
              child: Row(
                children: [
                  const IconTile(Icons.inventory_2_outlined),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          style: AppType.bodyStrong.copyWith(color: c.text),
                        ),
                        Text(
                          '${Fmt.quantity(m.stockOnHand)} ${m.unit} in stock',
                          style: AppType.bodySmall.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (ref
                .watch(permissionsProvider)
                .hasAny(Feature.materialsInventory))
              Wrap(
                spacing: Space.sm,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/materials/edit', extra: m),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit this material'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/materials/count', extra: m),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Correct the stock count'),
                  ),
                ],
              ),
            const SizedBox(height: Space.lg),
            if (projects.isEmpty && !loadingProjects)
              AppCard(
                child: Text(
                  'You can log materials on projects where you have a task. Ask your supervisor to assign you one.',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
              )
            else
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PickerField(
                      label: 'Project',
                      icon: Icons.apartment_rounded,
                      value: project?.label,
                      placeholder: loadingProjects
                          ? 'Loading…'
                          : 'Choose a project',
                      onTap: () async {
                        final picked = await pickOne<ProjectRef>(
                          context,
                          title: 'Choose a project',
                          selected: project,
                          options: [
                            for (final p in projects)
                              PickerOption(
                                value: p,
                                title: p.name,
                                subtitle: p.code,
                              ),
                          ],
                        );
                        if (picked?.value != null) {
                          setState(() => _project = picked!.value);
                        }
                      },
                    ),
                    const SizedBox(height: Space.lg),
                    AppTextField(
                      label: 'How much did you use?',
                      controller: _quantity,
                      suffixText: m.unit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      validator: validateQuantity,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.next,
                    ),
                    if (overStock)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Text(
                          'That is more than the ${Fmt.quantity(m.stockOnHand)} ${m.unit} on record. It will still be logged.',
                          style: AppType.bodySmall.copyWith(color: c.warning),
                        ),
                      ),
                    const SizedBox(height: Space.lg),
                    AppTextField(
                      label: 'Notes (optional)',
                      controller: _notes,
                      hint: 'Where or what it was used for',
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.lg),
                      ErrorPanel(error: _error!, compact: true),
                    ],
                    const SizedBox(height: Space.xxl),
                    AppButton(
                      label: 'Log usage',
                      icon: Icons.check_rounded,
                      loading: _saving,
                      onPressed: () => _submit(project),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

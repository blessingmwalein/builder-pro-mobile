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
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/change_requests_providers.dart';
import '../data/change_request_models.dart';

String? validateCrTitle(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Give it a short title';
  if (t.length > 120) return 'Keep the title under 120 characters';
  return null;
}

String? validateCrDescription(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Say what is being asked for';
  if (t.length > 2000) return 'Keep it under 2000 characters';
  return null;
}

String? validateCrLine(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Say what the cost is for';
  if (t.length > 200) return 'Keep it under 200 characters';
  return null;
}

/// Optional number with at most [decimals] decimals, not negative.
String? validateCrNumber(String? raw, {required int decimals}) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number';
  if (v < 0) return 'Cannot be negative';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > decimals) {
    return 'Use at most $decimals decimals';
  }
  return null;
}

class _LineDraft {
  final description = TextEditingController();
  final quantity = TextEditingController();
  final unitCost = TextEditingController();

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitCost.dispose();
  }

  NewCrItem toItem() {
    double? n(TextEditingController c) {
      final t = c.text.trim().replaceAll(',', '.');
      return t.isEmpty ? null : double.parse(t);
    }

    return NewCrItem(
      description: description.text.trim(),
      quantity: n(quantity),
      unitCost: n(unitCost),
    );
  }
}

/// Raise a change request on a project: a title, what is asked for, its type and
/// (optionally) cost lines. Saved as a draft, or submitted for review straight
/// away. Never sent twice: see [ChangeRequestActions.create].
class NewChangeRequestScreen extends ConsumerStatefulWidget {
  const NewChangeRequestScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<NewChangeRequestScreen> createState() =>
      _NewChangeRequestScreenState();
}

class _NewChangeRequestScreenState
    extends ConsumerState<NewChangeRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _lines = <_LineDraft>[];
  String _type = CrType.clientInitiated;
  bool _saving = false;
  AppException? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _save({required bool submit}) async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(changeRequestActionsProvider)
          .create(
            widget.projectId,
            title: _title.text,
            description: _description.text,
            type: _type,
            items: [for (final l in _lines) l.toItem()],
            submit: submit,
          );
      if (!mounted) return;
      final message = result.submitError != null
          ? 'Saved as a draft, but it could not be submitted: ${result.submitError!.message} Open it to try again.'
          : result.note ??
                (result.submitted
                    ? 'Submitted for review.'
                    : 'Saved as a draft.');
      Snack.show(context, message);
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
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.changeRequests);
    return Scaffold(
      appBar: AppBar(title: const Text('New change request')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot raise change requests.',
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
                          hint: 'e.g. Extra window on the east wall',
                          validator: validateCrTitle,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        Text(
                          'Type',
                          style: AppType.label.copyWith(color: c.text),
                        ),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final t in CrType.all)
                              ChoiceChip(
                                label: Text(crTypeLabel(t)),
                                selected: _type == t,
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(() => _type = t),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'What is asked for',
                          controller: _description,
                          hint: 'Describe the change and why',
                          minLines: 3,
                          maxLines: 8,
                          validator: validateCrDescription,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        for (var i = 0; i < _lines.length; i++) ...[
                          SectionHeader(
                            'COST LINE ${i + 1}',
                            trailing: TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _lines.removeAt(i).dispose(),
                                    ),
                              child: const Text('Remove'),
                            ),
                          ),
                          AppCard(
                            key: ObjectKey(_lines[i]),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AppTextField(
                                  label: 'What it is for',
                                  controller: _lines[i].description,
                                  validator: validateCrLine,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                ),
                                const SizedBox(height: Space.md),
                                AppTextField(
                                  label: 'Quantity (optional)',
                                  controller: _lines[i].quantity,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  validator: (v) =>
                                      validateCrNumber(v, decimals: 3),
                                ),
                                const SizedBox(height: Space.md),
                                AppTextField(
                                  label: 'Cost each (optional)',
                                  controller: _lines[i].unitCost,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  validator: (v) =>
                                      validateCrNumber(v, decimals: 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: Space.md),
                        AppButton(
                          label: 'Add a cost line',
                          icon: Icons.add_rounded,
                          variant: AppButtonVariant.secondary,
                          onPressed: _saving
                              ? null
                              : () => setState(() => _lines.add(_LineDraft())),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: 'Submit for review',
                          icon: Icons.send_rounded,
                          loading: _saving,
                          onPressed: () => _save(submit: true),
                        ),
                        const SizedBox(height: Space.sm),
                        AppButton(
                          label: 'Save as draft',
                          variant: AppButtonVariant.secondary,
                          onPressed: _saving
                              ? null
                              : () => _save(submit: false),
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'A draft can be submitted later from its page. Once submitted, a reviewer starts the review from the same page.',
                          style: AppType.helper.copyWith(color: c.textMuted),
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

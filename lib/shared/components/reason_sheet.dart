import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';
import 'app_button.dart';

/// Asks for a written reason before a consequential action (reject, decline…).
/// Returns the reason (possibly empty), or null when cancelled. With
/// [required] the confirm button stays off until something is written, so the
/// result is never empty.
Future<String?> showReasonSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? subtitle,
  String fieldLabel = 'Reason (optional)',
  String? hint,
  bool destructive = true,
  bool required = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ReasonSheet(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      fieldLabel: fieldLabel,
      hint: hint,
      destructive: destructive,
      required: required,
    ),
  );
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({
    required this.title,
    required this.confirmLabel,
    required this.fieldLabel,
    required this.destructive,
    required this.required,
    this.subtitle,
    this.hint,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;
  final String fieldLabel;
  final String? hint;
  final bool destructive;
  final bool required;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
            widget.title,
            style: AppType.sectionTitle.copyWith(color: c.text),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              widget.subtitle!,
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          ],
          const SizedBox(height: Space.lg),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: Space.xl),
          ListenableBuilder(
            listenable: _reason,
            builder: (context, _) => AppButton(
              label: widget.confirmLabel,
              variant: widget.destructive
                  ? AppButtonVariant.danger
                  : AppButtonVariant.primary,
              onPressed: widget.required && _reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_reason.text.trim()),
            ),
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

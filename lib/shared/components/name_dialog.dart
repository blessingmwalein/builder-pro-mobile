import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Asks for one short name (a new category, say). Returns the trimmed text, or
/// null when cancelled or left empty.
Future<String?> askForName(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, label: label, hint: hint),
  );
  final t = name?.trim();
  return t == null || t.isEmpty ? null : t;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label, this.hint});
  final String title;
  final String label;
  final String? hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: AppTextField(
        label: widget.label,
        controller: _name,
        hint: widget.hint,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_name.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

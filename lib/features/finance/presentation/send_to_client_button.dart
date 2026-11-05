import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';

/// "Send to client" on a draft invoice or quote.
///
/// Sending contacts someone outside the company, so the choice is spelled out
/// first: send it and email the client at the address on file, or only mark it
/// as sent (when you will deliver it yourself). Nothing is sent until one of the
/// two is chosen, and the action runs once per choice.
class SendToClientButton extends StatefulWidget {
  const SendToClientButton({
    super.key,
    required this.kind,
    required this.number,
    required this.clientName,
    required this.onSend,
    this.clientEmail,
  });

  /// `invoice` or `quote`, as it reads in a sentence.
  final String kind;
  final String number;
  final String clientName;
  final String? clientEmail;

  /// Sends it; [email] says whether to email the client. Returns a note when
  /// the outcome needs explaining, and throws [AppException] when nothing was
  /// recorded.
  final Future<String?> Function(bool email) onSend;

  @override
  State<SendToClientButton> createState() => _SendToClientButtonState();
}

class _SendToClientButtonState extends State<SendToClientButton> {
  bool _busy = false;

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final choice = await pickOne<bool>(
        context,
        title: 'Send ${widget.kind} ${widget.number}?',
        options: [
          if (widget.clientEmail != null)
            PickerOption(
              value: true,
              title: 'Send and email it',
              subtitle: 'Emails ${widget.clientName} at ${widget.clientEmail}',
            ),
          PickerOption(
            value: false,
            title: widget.clientEmail == null
                ? 'Mark as sent'
                : "Mark as sent, don't email",
            subtitle: widget.clientEmail == null
                ? 'There is no email address for ${widget.clientName}, so nothing is emailed'
                : 'You will send it to ${widget.clientName} yourself',
          ),
        ],
      );
      final email = choice?.value;
      if (email == null || !mounted) return;
      final note = await widget.onSend(email);
      if (!mounted) return;
      Snack.show(
        context,
        note ??
            (email
                ? 'Sent and emailed to ${widget.clientEmail}.'
                : 'Marked as sent.'),
      );
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Send to client',
          icon: Icons.send_rounded,
          loading: _busy,
          onPressed: _busy ? null : _send,
        ),
        const SizedBox(height: Space.sm),
        Text(
          'You choose whether the client is emailed before anything is sent.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

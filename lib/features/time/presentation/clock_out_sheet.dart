import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../data/time_models.dart';

/// Asks for the unpaid break, then returns the minutes (or null if cancelled).
Future<int?> showClockOutSheet(BuildContext context, TimeEntry entry) {
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ClockOutSheet(entry: entry),
  );
}

class _ClockOutSheet extends StatefulWidget {
  const _ClockOutSheet({required this.entry});
  final TimeEntry entry;

  @override
  State<_ClockOutSheet> createState() => _ClockOutSheetState();
}

class _ClockOutSheetState extends State<_ClockOutSheet> {
  static const _choices = [0, 15, 30, 45, 60, 90];
  int _break = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final worked =
        widget.entry.workedAt(DateTime.now()) - Duration(minutes: _break);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Clock out?',
            style: AppType.sectionTitle.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.sm),
          Text(
            '${widget.entry.project.label} · started ${Fmt.time(widget.entry.clockInAt)}',
            style: AppType.body.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.xl),
          Text('Unpaid break', style: AppType.label.copyWith(color: c.text)),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in _choices)
                ChoiceChip(
                  label: Text(m == 0 ? 'None' : '$m min'),
                  selected: _break == m,
                  onSelected: (_) => setState(() => _break = m),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Text(
            'You worked ${Fmt.duration(worked)}',
            style: AppType.bodyStrong.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Clock out',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(_break),
          ),
          const SizedBox(height: Space.sm),
          AppButton(
            label: 'Keep working',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

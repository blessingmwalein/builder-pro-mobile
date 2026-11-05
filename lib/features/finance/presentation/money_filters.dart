import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../data/money_models.dart';

/// The earliest day the period pickers offer.
final _earliest = DateTime(2000);

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Chooses what a money screen looks at: all time, one day, one month or a range
/// of dates, and (with [projectName] and the callbacks) one project.
class MoneyFilterBar extends StatelessWidget {
  const MoneyFilterBar({
    super.key,
    required this.period,
    required this.onPeriod,
    required this.projectName,
    required this.onPickProject,
    required this.onClearProject,
  });

  final MoneyPeriod period;
  final ValueChanged<MoneyPeriod> onPeriod;

  /// The chosen project's name, or null for all projects.
  final String? projectName;
  final VoidCallback onPickProject;
  final VoidCallback onClearProject;

  void _switchTo(PeriodKind kind) {
    if (kind == period.kind) return;
    final anchor = period.start ?? _today();
    onPeriod(switch (kind) {
      PeriodKind.all => MoneyPeriod.all,
      PeriodKind.day => MoneyPeriod.day(anchor),
      PeriodKind.month => MoneyPeriod.month(anchor),
      PeriodKind.range => MoneyPeriod.range(
        _today().subtract(const Duration(days: 6)),
        _today(),
      ),
    });
  }

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: period.start ?? _today(),
      firstDate: _earliest,
      lastDate: _today(),
    );
    if (picked != null) onPeriod(MoneyPeriod.day(picked));
  }

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: period.start ?? _today(),
      firstDate: _earliest,
      lastDate: _today(),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Pick any day in the month',
    );
    if (picked != null) onPeriod(MoneyPeriod.month(picked));
  }

  Future<void> _pickRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _earliest,
      lastDate: _today(),
      initialDateRange: period.start == null || period.end == null
          ? null
          : DateTimeRange(start: period.start!, end: period.end!),
    );
    if (picked != null) onPeriod(MoneyPeriod.range(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PeriodKind>(
          showSelectedIcon: false,
          style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.padded),
          segments: const [
            ButtonSegment(value: PeriodKind.all, label: Text('All time')),
            ButtonSegment(value: PeriodKind.day, label: Text('Day')),
            ButtonSegment(value: PeriodKind.month, label: Text('Month')),
            ButtonSegment(value: PeriodKind.range, label: Text('Range')),
          ],
          selected: {period.kind},
          onSelectionChanged: (s) => _switchTo(s.first),
        ),
        const SizedBox(height: Space.xs),
        switch (period.kind) {
          PeriodKind.all => Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Text(
              'Every date',
              textAlign: TextAlign.center,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
          ),
          PeriodKind.day || PeriodKind.month => Row(
            children: [
              IconButton(
                tooltip: period.kind == PeriodKind.day
                    ? 'Previous day'
                    : 'Previous month',
                onPressed: () => onPeriod(period.shifted(-1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => period.kind == PeriodKind.day
                      ? _pickDay(context)
                      : _pickMonth(context),
                  child: Text(
                    period.label,
                    textAlign: TextAlign.center,
                    style: AppType.bodyStrong,
                  ),
                ),
              ),
              IconButton(
                tooltip: period.kind == PeriodKind.day
                    ? 'Next day'
                    : 'Next month',
                onPressed: period.canGoLater(now)
                    ? () => onPeriod(period.shifted(1))
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          PeriodKind.range => Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _pickRange(context),
                  icon: const Icon(Icons.date_range_rounded, size: 20),
                  label: Text(
                    period.label,
                    textAlign: TextAlign.center,
                    style: AppType.bodyStrong,
                  ),
                ),
              ),
            ],
          ),
        },
        Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            avatar: const Icon(Icons.apartment_rounded, size: 18),
            label: Text(projectName ?? 'All projects'),
            onPressed: onPickProject,
            onDeleted: projectName == null ? null : onClearProject,
            deleteButtonTooltipMessage: 'Show all projects',
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ],
    );
  }
}

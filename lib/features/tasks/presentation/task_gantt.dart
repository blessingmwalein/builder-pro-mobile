import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/status_badge.dart';
import '../application/gantt_layout.dart';
import '../data/task_models.dart';
import 'task_row.dart';

/// A Gantt chart of tasks on a calendar, made for a phone: one row per task with
/// its name across the full width and, under it, a bar from its start date to
/// its due date on a calendar that always fits the screen. Week, Month or Quarter
/// chooses how much time is shown (with arrows to move along), so there is no
/// sideways scrolling and nothing is squeezed into a narrow column.
///
/// Every task's bar has its own colour. The status is never left to colour: it is
/// written in the row, a done task's bar is outlined with a tick, and an overdue
/// task's bar has a red edge and a mark. Tasks with no dates cannot be placed, so
/// they are listed under the chart. Tapping a row opens the task.
class TaskGantt extends StatefulWidget {
  const TaskGantt({
    super.key,
    required this.tasks,
    required this.scale,
    required this.onScaleChanged,
    required this.onOpenTask,
    this.now,
  });

  final List<TaskItem> tasks;
  final GanttScale scale;
  final ValueChanged<GanttScale> onScaleChanged;
  final ValueChanged<TaskItem> onOpenTask;

  /// Today, for tests; the clock otherwise.
  final DateTime? now;

  @override
  State<TaskGantt> createState() => _TaskGanttState();
}

class _TaskGanttState extends State<TaskGantt> {
  late int _anchor = calendarDay(widget.now ?? DateTime.now());

  DateTime get _now => widget.now ?? DateTime.now();
  int get _today => calendarDay(_now);

  @override
  void didUpdateWidget(TaskGantt old) {
    super.didUpdateWidget(old);
    // A different scale starts from the period that holds today.
    if (old.scale != widget.scale) _anchor = _today;
  }

  void _move(int steps) =>
      setState(() => _anchor = shiftAnchor(widget.scale, _anchor, steps));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final window = windowFor(widget.scale, _anchor);
    final plan = planGantt(widget.tasks);
    final rows = plan.inWindow(window);
    final unit = switch (widget.scale) {
      GanttScale.week => 'week',
      GanttScale.month => 'month',
      GanttScale.quarter => 'quarter',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<GanttScale>(
          showSelectedIcon: false,
          style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.padded),
          segments: [
            for (final s in GanttScale.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {widget.scale},
          onSelectionChanged: (s) => widget.onScaleChanged(s.first),
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous $unit',
              onPressed: () => _move(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                windowLabel(widget.scale, window),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyStrong.copyWith(color: c.text),
              ),
            ),
            IconButton(
              tooltip: 'Next $unit',
              onPressed: () => _move(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            TextButton(
              onPressed: window.contains(_today)
                  ? null
                  : () => setState(() => _anchor = _today),
              child: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        if (plan.bars.isEmpty)
          _Note(
            plan.unscheduled.isEmpty ? 'There are no tasks to chart.' : 'None of these tasks has a start or due date, so there is nothing to chart.',
          )
        else if (rows.isEmpty)
          _Note(
            'Nothing is scheduled this $unit. ${plan.bars.length} ${plan.bars.length == 1 ? 'task is' : 'tasks are'} scheduled in other periods. Use the arrows to find them.',
          )
        else
          _Chart(
            window: window,
            scale: widget.scale,
            rows: rows,
            today: _today,
            now: _now,
            onOpen: widget.onOpenTask,
          ),
        if (plan.bars.isNotEmpty &&
            rows.isNotEmpty &&
            rows.length < plan.bars.length)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              '${plan.bars.length - rows.length} more ${plan.bars.length - rows.length == 1 ? 'task is' : 'tasks are'} scheduled in other periods.',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ),
        if (plan.unscheduled.isNotEmpty) ...[
          SectionHeader('NO DATES ${plan.unscheduled.length}'),
          Text(
            'These have no start or due date, so they cannot be placed on the chart.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.sm),
          for (final t in plan.unscheduled)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: TaskRow(task: t, onTap: () => widget.onOpenTask(t)),
            ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Text(text, style: AppType.body.copyWith(color: c.textMuted)),
    );
  }
}

/// The card: the calendar's dates across the top, then a row for each task. Every
/// row's bar track is exactly as wide as the dates above it, so they line up.
class _Chart extends StatelessWidget {
  const _Chart({
    required this.window,
    required this.scale,
    required this.rows,
    required this.today,
    required this.now,
    required this.onOpen,
  });

  final GanttWindow window;
  final GanttScale scale;
  final List<GanttBar> rows;
  final int today;
  final DateTime now;
  final ValueChanged<TaskItem> onOpen;

  static const _pad = Space.md;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    // Room for the day names (two lines in a week, one line otherwise).
    final axisH = (scale == GanttScale.week ? 2 : 1) * 16.0 * text + 12;
    return LayoutBuilder(
      builder: (context, box) {
        final trackW = math.max(1.0, box.maxWidth - 2 * _pad);
        final px = trackW / window.days;
        return Material(
          color: c.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corners.card),
            side: BorderSide(color: c.borderSoft, width: Sizes.cardBorderWidth),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _pad),
                child: _Axis(
                  window: window,
                  scale: scale,
                  px: px,
                  width: trackW,
                  height: axisH,
                  today: today,
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.border),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: c.borderSoft),
                _TaskCell(
                  bar: rows[i],
                  window: window,
                  scale: scale,
                  px: px,
                  trackW: trackW,
                  today: today,
                  now: now,
                  onTap: () => onOpen(rows[i].task),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The dates above the rows: the days of a week, the Mondays of a month, or the
/// months of a quarter.
class _Axis extends StatelessWidget {
  const _Axis({
    required this.window,
    required this.scale,
    required this.px,
    required this.width,
    required this.height,
    required this.today,
  });

  final GanttWindow window;
  final GanttScale scale;
  final double px;
  final double width;
  final double height;
  final int today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = <Widget>[];
    switch (scale) {
      case GanttScale.week:
        for (var i = 0; i < window.days; i++) {
          final day = window.startDay + i;
          final d = dayToDate(day);
          final isToday = day == today;
          labels.add(
            Positioned(
              left: i * px,
              width: px,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${DateFormat('E').format(d)}\n',
                        style: AppType.helper.copyWith(
                          color: isToday ? c.primaryText : c.textMuted,
                        ),
                      ),
                      TextSpan(
                        text: '${d.day}',
                        style: AppType.label.copyWith(
                          color: isToday ? c.primaryText : c.text,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          );
        }
      case GanttScale.month:
        for (var i = 0; i < window.days; i++) {
          final d = dayToDate(window.startDay + i);
          if (d.weekday != DateTime.monday) continue;
          labels.add(_edgeLabel(c, i * px, 7 * px, '${d.day}'));
        }
      case GanttScale.quarter:
        for (final m in monthSpans(window)) {
          labels.add(_edgeLabel(c, m.offsetDays * px, m.days * px, m.label));
        }
    }
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                colors: c,
                window: window,
                scale: scale,
                px: px,
                today: today,
              ),
            ),
          ),
          ...labels,
        ],
      ),
    );
  }

  /// A label at the left edge of a column, clipped rather than wrapped.
  Widget _edgeLabel(AppColors c, double left, double w, String text) {
    return Positioned(
      left: left + 3,
      width: w,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
      ),
    );
  }
}

/// One task: a coloured dot, its name and status, its dates, and its bar.
class _TaskCell extends StatelessWidget {
  const _TaskCell({
    required this.bar,
    required this.window,
    required this.scale,
    required this.px,
    required this.trackW,
    required this.today,
    required this.now,
    required this.onTap,
  });

  final GanttBar bar;
  final GanttWindow window;
  final GanttScale scale;
  final double px;
  final double trackW;
  final int today;
  final DateTime now;
  final VoidCallback onTap;

  static const _dot = 10.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = bar.task;
    final overdue = t.isOverdue(now);
    final span = spanLabel(bar.startDay, bar.endDay);
    final days = '${bar.length} ${bar.length == 1 ? 'day' : 'days'}';

    final title = Text(
      t.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: AppType.bodyStrong.copyWith(color: c.text),
    );
    final badge = StatusBadge.status(t.status, dense: true);
    // The badge sits beside the name, or under it when text is enlarged, so
    // neither is squeezed out.
    final heading = MediaQuery.textScalerOf(context).scale(1) > 1.3
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: Space.xs),
              badge,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: Space.sm),
              badge,
            ],
          );

    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          '${t.title}, ${statusInfo(t.status).label}'
          '${overdue ? ', overdue' : ''}, $span, $days',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    // Level with the middle of the name's first line.
                    padding: const EdgeInsets.only(top: 6, right: Space.sm),
                    child: SizedBox(
                      width: _dot,
                      height: _dot,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.seriesAt(bar.slot),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: heading),
                ],
              ),
              const SizedBox(height: Space.xs),
              Padding(
                padding: const EdgeInsets.only(left: _dot + Space.sm),
                child: Text(
                  overdue ? 'Overdue · $span · $days' : '$span · $days',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.helper.copyWith(
                    color: overdue ? c.danger : c.textMuted,
                    fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              _Track(
                bar: bar,
                window: window,
                scale: scale,
                px: px,
                width: trackW,
                today: today,
                overdue: overdue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The strip under a task's name: the calendar's lines with the task's bar on it.
class _Track extends StatelessWidget {
  const _Track({
    required this.bar,
    required this.window,
    required this.scale,
    required this.px,
    required this.width,
    required this.today,
    required this.overdue,
  });

  final GanttBar bar;
  final GanttWindow window;
  final GanttScale scale;
  final double px;
  final double width;
  final int today;
  final bool overdue;

  static const _height = 28.0;
  static const _barH = 18.0;
  static const _icon = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = bar.task.isDone;
    final series = c.seriesAt(bar.slot);
    // Marks on a solid bar use whichever of light or dark reads on its colour.
    final onSeries =
        ThemeData.estimateBrightnessForColor(series) == Brightness.dark
        ? c.textOnPrimary
        : c.background;
    final fg = done ? series : onSeries;

    final place = placeBar(bar, window);
    final barW = math.max(6.0, place.spanDays * px - 2);
    final left = (place.offsetDays * px + 1)
        .clamp(0.0, math.max(0.0, width - barW))
        .toDouble();
    const round = Radius.circular(9);
    const square = Radius.circular(2);

    // A tick for done, a mark for overdue, arrows where it runs past the edge of
    // the period: only as many as fit inside the bar.
    final middle = done
        ? Icons.check_rounded
        : overdue
        ? Icons.priority_high_rounded
        : null;
    final needed =
        ((place.continuesBefore ? 1 : 0) +
            (place.continuesAfter ? 1 : 0) +
            (middle == null ? 0 : 1)) *
        _icon;
    final showMarks = needed > 0 && barW >= needed + 6;

    return SizedBox(
      width: width,
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                colors: c,
                window: window,
                scale: scale,
                px: px,
                today: today,
              ),
            ),
          ),
          Positioned(
            left: left,
            top: (_height - _barH) / 2,
            width: barW,
            height: _barH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: done ? series.withValues(alpha: 0.22) : series,
                border: Border.all(
                  color: overdue ? c.danger : series,
                  width: overdue ? 2 : 1.5,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: place.continuesBefore ? square : round,
                  bottomLeft: place.continuesBefore ? square : round,
                  topRight: place.continuesAfter ? square : round,
                  bottomRight: place.continuesAfter ? square : round,
                ),
              ),
              child: showMarks
                  ? Row(
                      children: [
                        if (place.continuesBefore)
                          Icon(
                            Icons.chevron_left_rounded,
                            size: _icon,
                            color: fg,
                          ),
                        Expanded(
                          child: Center(
                            child: middle == null
                                ? const SizedBox.shrink()
                                : Icon(middle, size: _icon, color: fg),
                          ),
                        ),
                        if (place.continuesAfter)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: _icon,
                            color: fg,
                          ),
                      ],
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The calendar behind the dates and each bar: weekend shading, the lines between
/// days (a week), Mondays (a month) or months (a quarter), and today.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.colors,
    required this.window,
    required this.scale,
    required this.px,
    required this.today,
  });

  final AppColors colors;
  final GanttWindow window;
  final GanttScale scale;
  final double px;
  final int today;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final weekend = Paint()..color = colors.surfaceMuted.withValues(alpha: 0.7);
    final line = Paint()
      ..color = colors.borderSoft
      ..strokeWidth = 1;
    final strong = Paint()
      ..color = colors.border
      ..strokeWidth = 1;

    for (var i = 0; i < window.days; i++) {
      final date = dayToDate(window.startDay + i);
      final x = i * px;
      // A quarter is too dense for a stripe a day.
      if (scale != GanttScale.quarter &&
          (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)) {
        canvas.drawRect(Rect.fromLTWH(x, 0, px, h), weekend);
      }
      if (i == 0) continue;
      final Paint? paint = switch (scale) {
        GanttScale.week => line,
        GanttScale.month => date.weekday == DateTime.monday ? line : null,
        GanttScale.quarter =>
          date.day == 1
              ? strong
              : date.weekday == DateTime.monday
              ? line
              : null,
      };
      if (paint != null) canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
    }
    if (window.contains(today)) {
      final x = (today - window.startDay) * px;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, math.max(px, 3.0), h),
        Paint()..color = colors.primary.withValues(alpha: 0.10),
      );
      canvas.drawRect(
        Rect.fromLTWH(x + px / 2 - 1, 0, 2, h),
        Paint()..color = colors.primary.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.colors != colors ||
      old.window.startDay != window.startDay ||
      old.window.days != window.days ||
      old.scale != scale ||
      old.px != px ||
      old.today != today;
}

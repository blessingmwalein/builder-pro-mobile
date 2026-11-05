import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../data/task_models.dart';

/// How much time the Gantt chart shows at once.
enum GanttScale {
  week('Week'),
  month('Month'),
  quarter('Quarter');

  const GanttScale(this.label);
  final String label;
}

/// A calendar day as a whole number (days since 1970-01-01), so spans and
/// positions are plain integer arithmetic that daylight-saving changes cannot
/// shift by a day.
int calendarDay(DateTime t) {
  final l = t.toLocal();
  return DateTime.utc(l.year, l.month, l.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// The date (as a UTC midnight, used only for its year, month, day and weekday).
DateTime dayToDate(int day) => DateTime.fromMillisecondsSinceEpoch(
  day * Duration.millisecondsPerDay,
  isUtc: true,
);

int _dayOf(DateTime utcDate) =>
    utcDate.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// The stretch of days the chart shows.
class GanttWindow {
  const GanttWindow(this.startDay, this.days);

  final int startDay;
  final int days;

  int get endDay => startDay + days - 1;

  bool contains(int day) => day >= startDay && day <= endDay;

  bool overlaps(int from, int to) => from <= endDay && to >= startDay;
}

/// The window of [scale] that holds [anchorDay]: the Monday-to-Sunday week, the
/// calendar month, or the calendar quarter.
GanttWindow windowFor(GanttScale scale, int anchorDay) {
  final a = dayToDate(anchorDay);
  switch (scale) {
    case GanttScale.week:
      return GanttWindow(anchorDay - (a.weekday - DateTime.monday), 7);
    case GanttScale.month:
      final first = DateTime.utc(a.year, a.month, 1);
      final next = DateTime.utc(a.year, a.month + 1, 1);
      return GanttWindow(_dayOf(first), _dayOf(next) - _dayOf(first));
    case GanttScale.quarter:
      final firstMonth = ((a.month - 1) ~/ 3) * 3 + 1;
      final first = DateTime.utc(a.year, firstMonth, 1);
      final next = DateTime.utc(a.year, firstMonth + 3, 1);
      return GanttWindow(_dayOf(first), _dayOf(next) - _dayOf(first));
  }
}

/// A day inside the window [steps] periods after (or before, when negative)
/// the one holding [anchorDay].
int shiftAnchor(GanttScale scale, int anchorDay, int steps) {
  final start = windowFor(scale, anchorDay).startDay;
  final a = dayToDate(start);
  switch (scale) {
    case GanttScale.week:
      return start + 7 * steps;
    case GanttScale.month:
      return _dayOf(DateTime.utc(a.year, a.month + steps, 1));
    case GanttScale.quarter:
      return _dayOf(DateTime.utc(a.year, a.month + 3 * steps, 1));
  }
}

/// `26 Oct – 1 Nov 2026`, `October 2026`, `Q4 2026 · Oct – Dec`.
String windowLabel(GanttScale scale, GanttWindow w) {
  final start = dayToDate(w.startDay);
  final end = dayToDate(w.endDay);
  switch (scale) {
    case GanttScale.week:
      final sameYear = start.year == end.year;
      final from = DateFormat(sameYear ? 'd MMM' : 'd MMM y').format(start);
      return '$from – ${DateFormat('d MMM y').format(end)}';
    case GanttScale.month:
      return DateFormat('MMMM y').format(start);
    case GanttScale.quarter:
      final q = (start.month - 1) ~/ 3 + 1;
      return 'Q$q ${start.year} · ${DateFormat('MMM').format(start)} – ${DateFormat('MMM').format(end)}';
  }
}

/// `26 Oct`, or `26 Oct – 2 Nov`, or `26 Oct 2025 – 2 Nov 2026` across years.
String spanLabel(int startDay, int endDay) {
  final s = dayToDate(startDay);
  final e = dayToDate(endDay);
  if (startDay == endDay) return DateFormat('d MMM').format(s);
  if (s.year != e.year) {
    return '${DateFormat('d MMM y').format(s)} – ${DateFormat('d MMM y').format(e)}';
  }
  return '${DateFormat('d MMM').format(s)} – ${DateFormat('d MMM').format(e)}';
}

/// One task's span on the calendar, inclusive of both days.
class GanttBar {
  const GanttBar({
    required this.task,
    required this.startDay,
    required this.endDay,
    this.slot = 0,
  });

  final TaskItem task;
  final int startDay;
  final int endDay;

  /// Which colour this task's bar takes. [planGantt] numbers the bars in
  /// start-date order, so neighbours differ and a task keeps its colour as the
  /// chart moves from one period to the next.
  final int slot;

  int get length => endDay - startDay + 1;

  GanttBar withSlot(int slot) =>
      GanttBar(task: task, startDay: startDay, endDay: endDay, slot: slot);
}

/// The span of [t]: from its start date to its due date. A task with only one of
/// them is a single day. Null when it has neither, so it cannot be placed.
GanttBar? ganttBarFor(TaskItem t) {
  final s = t.startDate == null ? null : calendarDay(t.startDate!);
  final e = t.dueDate == null ? null : calendarDay(t.dueDate!);
  if (s == null && e == null) return null;
  final a = s ?? e!;
  final b = e ?? s!;
  // A due date before the start date is a data slip: show it as one span rather
  // than a bar of negative length.
  return GanttBar(task: t, startDay: math.min(a, b), endDay: math.max(a, b));
}

/// What the chart draws for a set of tasks.
class GanttPlan {
  const GanttPlan({required this.bars, required this.unscheduled});

  /// Every task with at least one date, earliest first.
  final List<GanttBar> bars;

  /// Tasks with no start and no due date.
  final List<TaskItem> unscheduled;

  /// The bars that fall (wholly or partly) inside [window].
  List<GanttBar> inWindow(GanttWindow window) => [
    for (final b in bars)
      if (window.overlaps(b.startDay, b.endDay)) b,
  ];
}

GanttPlan planGantt(Iterable<TaskItem> tasks) {
  final bars = <GanttBar>[];
  final none = <TaskItem>[];
  for (final t in tasks) {
    final bar = ganttBarFor(t);
    if (bar == null) {
      none.add(t);
    } else {
      bars.add(bar);
    }
  }
  bars.sort((a, b) {
    final s = a.startDay.compareTo(b.startDay);
    if (s != 0) return s;
    final e = a.endDay.compareTo(b.endDay);
    if (e != 0) return e;
    return a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
  });
  return GanttPlan(
    bars: [for (var i = 0; i < bars.length; i++) bars[i].withSlot(i)],
    unscheduled: none,
  );
}

/// Where a bar sits inside [window], in days from the window's first day, and
/// whether it carries on past either edge.
class GanttPlacement {
  const GanttPlacement({
    required this.offsetDays,
    required this.spanDays,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final int offsetDays;
  final int spanDays;
  final bool continuesBefore;
  final bool continuesAfter;
}

GanttPlacement placeBar(GanttBar bar, GanttWindow window) {
  final from = math.max(bar.startDay, window.startDay);
  final to = math.min(bar.endDay, window.endDay);
  return GanttPlacement(
    offsetDays: from - window.startDay,
    spanDays: to - from + 1,
    continuesBefore: bar.startDay < window.startDay,
    continuesAfter: bar.endDay > window.endDay,
  );
}

/// One month's share of the window, for the header above the days.
class GanttMonthSpan {
  const GanttMonthSpan({
    required this.offsetDays,
    required this.days,
    required this.label,
  });

  final int offsetDays;
  final int days;

  /// `Oct 2026` for the first span, `Nov` for the ones after it.
  final String label;
}

List<GanttMonthSpan> monthSpans(GanttWindow w) {
  final spans = <GanttMonthSpan>[];
  var day = w.startDay;
  while (day <= w.endDay) {
    final d = dayToDate(day);
    final nextFirst = _dayOf(DateTime.utc(d.year, d.month + 1, 1));
    final last = math.min(nextFirst - 1, w.endDay);
    spans.add(
      GanttMonthSpan(
        offsetDays: day - w.startDay,
        days: last - day + 1,
        label: DateFormat(spans.isEmpty ? 'MMM y' : 'MMM').format(d),
      ),
    );
    day = last + 1;
  }
  return spans;
}

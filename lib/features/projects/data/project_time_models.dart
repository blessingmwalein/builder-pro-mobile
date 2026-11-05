import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// How far back the project's time figures look.
enum TimeWindow {
  all('All time', null),
  week('Last 7 days', 7),
  month('Last 30 days', 30);

  const TimeWindow(this.label, this.days);
  final String label;

  /// The window is this many local days ending today (today counts). Null for all
  /// time.
  final int? days;
}

/// One clock-in on a project, reduced to what the time figures need. The entry the
/// server sends also carries the worker's hourly rate and cost; those are never
/// read, so no pay reaches the phone's memory (backend-gaps G44).
@immutable
class TimeSlice {
  const TimeSlice({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.clockInAt,
    this.clockOutAt,
    this.breakMinutes = 0,
    this.hours = 0,
    this.status = 'PENDING',
    this.isManual = false,
  });

  final String id;
  final String workerId;
  final String workerName;
  final DateTime clockInAt;

  /// Null while the person is still clocked in.
  final DateTime? clockOutAt;
  final int breakMinutes;

  /// Regular plus overtime hours the server stored when the entry was closed.
  final double hours;

  /// `PENDING` (waiting for approval), `APPROVED` or `REJECTED`.
  final String status;
  final bool isManual;

  bool get isOpen => clockOutAt == null;
  bool get isRejected => status == 'REJECTED';

  /// Time on the clock so far for an open entry: since clock-in, minus breaks,
  /// never below zero.
  Duration elapsedAt(DateTime now) {
    final d = now.difference(clockInAt) - Duration(minutes: breakMinutes);
    return d.isNegative ? Duration.zero : d;
  }

  /// The hours this entry counts for: what the server stored once it is closed,
  /// the time so far while it is open.
  double hoursAt(DateTime now) =>
      isOpen ? elapsedAt(now).inSeconds / 3600 : hours;

  static TimeSlice? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final clockIn = J.date(m['clockInAt']);
    if (id == null || clockIn == null) return null;
    final worker = J.map(m['worker']);
    final name =
        '${J.strOr(worker['firstName'])} ${J.strOr(worker['lastName'])}'.trim();
    return TimeSlice(
      id: id,
      workerId: J.strOr(m['workerId'], J.strOr(worker['id'], id)),
      workerName: name.isEmpty ? 'Team member' : name,
      clockInAt: clockIn,
      clockOutAt: J.date(m['clockOutAt']),
      breakMinutes: J.integer(m['breakMinutes']) ?? 0,
      hours:
          (J.number(m['regularHours']) ?? 0) +
          (J.number(m['overtimeHours']) ?? 0),
      status: J.strOr(m['status'], 'PENDING'),
      isManual: J.boolean(m['isManualEntry']),
    );
  }
}

/// Every time entry read for one project, and whether reading stopped before the
/// end (the newest are read first).
@immutable
class ProjectTimeData {
  const ProjectTimeData({required this.slices, required this.truncated});
  final List<TimeSlice> slices;
  final bool truncated;
}

/// Total hours worked on a project, from every entry that is not rejected.
double projectTotalHours(Iterable<TimeSlice> slices, DateTime now) => slices
    .where((s) => !s.isRejected)
    .fold(0.0, (sum, s) => sum + s.hoursAt(now));

/// Someone who is clocked in on the project right now.
@immutable
class OnSiteEntry {
  const OnSiteEntry({
    required this.workerId,
    required this.name,
    required this.since,
    required this.elapsed,
  });
  final String workerId;
  final String name;
  final DateTime since;
  final Duration elapsed;
}

/// One person's share of the hours in the window.
@immutable
class PersonTime {
  const PersonTime({
    required this.workerId,
    required this.name,
    required this.hours,
    required this.daysWorked,
    required this.averageHoursPerDay,
    required this.lastDay,
    required this.isOnSite,
  });
  final String workerId;
  final String name;
  final double hours;
  final int daysWorked;
  final double averageHoursPerDay;
  final DateTime lastDay;
  final bool isOnSite;
}

/// The hours worked on one local day (all people added up).
@immutable
class DayHours {
  const DayHours(this.day, this.hours);
  final DateTime day;
  final double hours;
}

/// The figures on the project's Time tab.
@immutable
class ProjectTimeStats {
  const ProjectTimeStats({
    required this.totalHours,
    required this.approvedHours,
    required this.pendingHours,
    required this.daysWorked,
    required this.averageHoursPerDay,
    required this.peopleCount,
    required this.averagePeoplePerDay,
    required this.firstDay,
    required this.lastDay,
    required this.hoursThisWeek,
    required this.onSiteNow,
    required this.perPerson,
    required this.dailyHours,
    required this.entryCount,
    required this.recordedEntries,
  });

  /// Hours in the window.
  final double totalHours;

  /// Of [totalHours], what is approved and what still waits for approval.
  final double approvedHours;
  final double pendingHours;

  /// Local calendar days in the window with at least one entry.
  final int daysWorked;

  /// [totalHours] over [daysWorked]; zero when nothing was worked.
  final double averageHoursPerDay;

  /// Different people in the window, and how many were on a worked day on average.
  final int peopleCount;
  final double averagePeoplePerDay;

  /// The first and last worked day in the window.
  final DateTime? firstDay;
  final DateTime? lastDay;

  /// This week (Monday to now), whatever the window.
  final double hoursThisWeek;

  /// Everyone clocked in now, whatever the window. Earliest clock-in first.
  final List<OnSiteEntry> onSiteNow;

  /// Hours in the window by person, most hours first.
  final List<PersonTime> perPerson;

  /// The last 14 local days, oldest first (zero for a day with nothing),
  /// whatever the window.
  final List<DayHours> dailyHours;

  /// Entries in the window, and entries of any date (rejected ones left out).
  final int entryCount;
  final int recordedEntries;

  bool get hasAnyEntries => recordedEntries > 0;
}

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// How many days the daily bars cover.
const dailyBarDays = 14;

/// Works the project's time figures out from its entries. Pure: [now] is passed
/// in.
///
/// * A rejected entry is left out of everything.
/// * A closed entry counts the hours the server stored; an open one counts the
///   time since clock-in minus breaks (never below zero) and also appears in
///   [ProjectTimeStats.onSiteNow].
/// * An entry belongs to the local day it started, even if the shift runs past
///   midnight.
/// * The window keeps entries that started within the last N local days, today
///   included. [ProjectTimeStats.hoursThisWeek], [ProjectTimeStats.onSiteNow] and
///   [ProjectTimeStats.dailyHours] do not depend on it.
ProjectTimeStats buildProjectTimeStats(
  List<TimeSlice> entries, {
  required DateTime now,
  TimeWindow window = TimeWindow.all,
}) {
  final today = _dayOf(now);
  final counted = entries.where((s) => !s.isRejected).toList();

  final days = window.days;
  final from = days == null
      ? null
      : DateTime(today.year, today.month, today.day - (days - 1));
  final inWindow = [
    for (final s in counted)
      if (from == null || !_dayOf(s.clockInAt).isBefore(from)) s,
  ];

  var total = 0.0;
  var approved = 0.0;
  var pending = 0.0;
  final hoursByDay = <DateTime, double>{};
  final workersByDay = <DateTime, Set<String>>{};
  final workers = <String, _PersonAcc>{};
  for (final s in inWindow) {
    final h = s.hoursAt(now);
    final day = _dayOf(s.clockInAt);
    total += h;
    if (s.status == 'APPROVED') approved += h;
    if (s.status == 'PENDING') pending += h;
    hoursByDay[day] = (hoursByDay[day] ?? 0) + h;
    (workersByDay[day] ??= <String>{}).add(s.workerId);
    final p = workers[s.workerId] ??= _PersonAcc(s.workerName);
    p.hours += h;
    p.days.add(day);
  }

  final workedDays = hoursByDay.keys.toList()..sort();
  final dayCount = workedDays.length;
  final peopleDays = workersByDay.values.fold(0, (sum, w) => sum + w.length);

  final open = [
    for (final s in counted)
      if (s.isOpen) s,
  ]..sort((a, b) => a.clockInAt.compareTo(b.clockInAt));
  final onSite = [
    for (final s in open)
      OnSiteEntry(
        workerId: s.workerId,
        name: s.workerName,
        since: s.clockInAt.toLocal(),
        elapsed: s.elapsedAt(now),
      ),
  ];
  final onSiteIds = open.map((s) => s.workerId).toSet();

  final people =
      [
        for (final e in workers.entries)
          PersonTime(
            workerId: e.key,
            name: e.value.name,
            hours: e.value.hours,
            daysWorked: e.value.days.length,
            averageHoursPerDay: e.value.hours / e.value.days.length,
            lastDay: e.value.days.reduce((a, b) => a.isAfter(b) ? a : b),
            isOnSite: onSiteIds.contains(e.key),
          ),
      ]..sort((a, b) {
        final byHours = b.hours.compareTo(a.hours);
        return byHours != 0 ? byHours : a.name.compareTo(b.name);
      });

  // This week and the daily bars look at every entry, whatever the window.
  final weekStart = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - DateTime.monday),
  );
  var thisWeek = 0.0;
  final everyDay = <DateTime, double>{};
  for (final s in counted) {
    final h = s.hoursAt(now);
    final day = _dayOf(s.clockInAt);
    everyDay[day] = (everyDay[day] ?? 0) + h;
    if (!day.isBefore(weekStart)) thisWeek += h;
  }
  final daily = [
    for (var i = dailyBarDays - 1; i >= 0; i--)
      () {
        final d = DateTime(today.year, today.month, today.day - i);
        return DayHours(d, everyDay[d] ?? 0);
      }(),
  ];

  return ProjectTimeStats(
    totalHours: total,
    approvedHours: approved,
    pendingHours: pending,
    daysWorked: dayCount,
    averageHoursPerDay: dayCount == 0 ? 0 : total / dayCount,
    peopleCount: workers.length,
    averagePeoplePerDay: dayCount == 0 ? 0 : peopleDays / dayCount,
    firstDay: workedDays.isEmpty ? null : workedDays.first,
    lastDay: workedDays.isEmpty ? null : workedDays.last,
    hoursThisWeek: thisWeek,
    onSiteNow: onSite,
    perPerson: people,
    dailyHours: daily,
    entryCount: inWindow.length,
    recordedEntries: counted.length,
  );
}

class _PersonAcc {
  _PersonAcc(this.name);
  final String name;
  double hours = 0;
  final days = <DateTime>{};
}

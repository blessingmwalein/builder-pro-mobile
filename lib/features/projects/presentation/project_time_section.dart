import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/project_time_providers.dart';
import '../data/project_time_models.dart';
import '../data/project_time_repository.dart';

/// An open entry this old is probably a forgotten clock-out.
const _longShift = Duration(hours: 14);

/// The team's clock-in figures for one project, for people who may see everyone's
/// time: total hours, the average per day worked, who is on site now, the last
/// two weeks day by day, and each person's share. Rejected entries are left out
/// and pay rates are never read.
class ProjectTimeSection extends ConsumerStatefulWidget {
  const ProjectTimeSection({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectTimeSection> createState() => _ProjectTimeSectionState();
}

class _ProjectTimeSectionState extends ConsumerState<ProjectTimeSection> {
  TimeWindow _window = TimeWindow.all;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // How long people have been on site is worked out from the clock, so the
    // minutes keep moving while the tab stays open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(projectTimeProvider(widget.projectId));
    return data.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.sm),
        child: SkeletonList(rows: 3, rowHeight: 96),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: ErrorPanel(
          error: e,
          onRetry: () => ref.invalidate(projectTimeProvider(widget.projectId)),
        ),
      ),
      data: _body,
    );
  }

  Widget _body(ProjectTimeData data) {
    final now = DateTime.now();
    final stats = buildProjectTimeStats(data.slices, now: now, window: _window);
    if (!stats.hasAnyEntries) {
      return const Padding(
        padding: EdgeInsets.only(top: Space.x3),
        child: EmptyState(
          icon: Icons.schedule_rounded,
          title: 'No time recorded on this project yet',
          message: 'Hours appear here when people clock in on it.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.sm),
        StatusFilterRow(
          options: [for (final w in TimeWindow.values) (w.name, w.label)],
          selected: _window.name,
          onSelected: (v) => setState(
            () => _window = TimeWindow.values.firstWhere(
              (w) => w.name == v,
              orElse: () => _window,
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        _Tiles(stats: stats),
        _OnSite(entries: stats.onSiteNow, now: now),
        _LastDays(days: stats.dailyHours, today: now),
        _Team(stats: stats),
        if (data.truncated)
          _Note(
            'Based on the latest ${ProjectTimeRepository.maxEntries} time entries.',
          ),
        const _Note(
          'Hours come from clock-ins on this project. Rejected entries are left out. Pay rates are never shown.',
        ),
      ],
    );
  }
}

String? _span(DateTime? a, DateTime? b) {
  if (a == null || b == null) return null;
  final f = DateFormat(a.year == b.year ? 'd MMM' : 'd MMM y');
  return a == b ? f.format(a) : '${f.format(a)} – ${f.format(b)}';
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});
  final ProjectTimeStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    Widget row(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: Space.md),
          Expanded(child: b),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          MetricTile(
            label: 'TOTAL HOURS',
            value: Fmt.hours(s.totalHours),
            caption:
                'Approved ${Fmt.hours(s.approvedHours)} · Waiting ${Fmt.hours(s.pendingHours)}',
          ),
          MetricTile(
            label: 'DAYS WORKED',
            value: '${s.daysWorked}',
            caption: _span(s.firstDay, s.lastDay) ?? 'None in this period',
          ),
        ),
        const SizedBox(height: Space.md),
        row(
          MetricTile(
            label: 'AVERAGE PER DAY',
            value: Fmt.hours(s.averageHoursPerDay),
            caption: 'per day worked',
          ),
          MetricTile(
            label: 'THIS WEEK',
            value: Fmt.hours(s.hoursThisWeek),
            caption: 'Monday to now',
          ),
        ),
      ],
    );
  }
}

class _OnSite extends StatelessWidget {
  const _OnSite({required this.entries, required this.now});
  final List<OnSiteEntry> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = DateTime(now.year, now.month, now.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          entries.isEmpty ? 'ON SITE NOW' : 'ON SITE NOW ${entries.length}',
        ),
        AppCard(
          child: entries.isEmpty
              ? Text(
                  'Nobody is clocked in on this project.',
                  style: AppType.body.copyWith(color: c.textMuted),
                )
              : Column(
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0) Divider(height: Space.xl, color: c.borderSoft),
                      _OnSiteRow(entry: entries[i], today: today),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _OnSiteRow extends StatelessWidget {
  const _OnSiteRow({required this.entry, required this.today});
  final OnSiteEntry entry;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final sinceDay = DateTime(e.since.year, e.since.month, e.since.day);
    final since = sinceDay == today ? Fmt.time(e.since) : Fmt.dayTime(e.since);
    final long = e.elapsed >= _longShift;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.name, style: AppType.bodyStrong.copyWith(color: c.text)),
        Text(
          'Since $since · ${Fmt.duration(e.elapsed)}',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        if (long)
          Text(
            'Still open after a long time: the clock-out may have been forgotten.',
            style: AppType.helper.copyWith(color: c.warning),
          ),
      ],
    );
  }
}

class _LastDays extends StatelessWidget {
  const _LastDays({required this.days, required this.today});
  final List<DayHours> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final width = 64.0 * scale;
    final top = days.fold(0.0, (m, d) => d.hours > m ? d.hours : m);
    final todayDay = DateTime(today.year, today.month, today.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('LAST 14 DAYS'),
        AppCard(
          child: Column(
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: width,
                        child: Text(
                          d.day == todayDay
                              ? 'Today'
                              : DateFormat('E d').format(d.day),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.helper.copyWith(
                            color: d.day == todayDay
                                ? c.primaryText
                                : c.textMuted,
                            fontWeight: d.day == todayDay
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: top > 0
                                ? (d.hours / top).clamp(0.0, 1.0)
                                : 0,
                            minHeight: 8,
                            color: c.primary,
                            backgroundColor: c.surfaceMuted,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: Text(
                          d.hours > 0 ? Fmt.hours(d.hours) : '–',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppType.helper.copyWith(
                            color: d.hours > 0 ? c.text : c.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({required this.stats});
  final ProjectTimeStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(s.peopleCount == 0 ? 'TEAM' : 'TEAM ${s.peopleCount}'),
        if (s.perPerson.isEmpty)
          AppCard(
            child: Text(
              'Nobody worked on this project in this period.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'About ${s.averagePeoplePerDay.toStringAsFixed(1)} ${s.averagePeoplePerDay == 1 ? 'person' : 'people'} on site on a day worked.',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ),
          for (final p in s.perPerson)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _PersonCard(person: p),
            ),
        ],
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});
  final PersonTime person;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = person;
    final days = '${p.daysWorked} ${p.daysWorked == 1 ? 'day' : 'days'}';
    final detail =
        '$days · ${Fmt.hours(p.averageHoursPerDay)} a day · last worked ${DateFormat('d MMM').format(p.lastDay)}';
    return AppCard(
      semanticLabel:
          '${p.name}, ${Fmt.hours(p.hours)}, $detail${p.isOnSite ? ', on site now' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: AppType.bodyStrong.copyWith(color: c.text)),
                if (p.isOnSite)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: const StatusBadge(
                      label: 'On site',
                      tone: StatusTone.success,
                      dense: true,
                    ),
                  ),
              ],
            ),
            end: Text(
              Fmt.hours(p.hours),
              style: AppType.amount.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(detail, style: AppType.helper.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.sm),
    child: Text(
      text,
      style: AppType.helper.copyWith(color: context.colors.textMuted),
    ),
  );
}

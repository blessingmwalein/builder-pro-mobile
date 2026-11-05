import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../change_requests/application/change_requests_providers.dart';
import '../../change_requests/presentation/change_requests_section.dart';
import '../../documents/application/documents_providers.dart';
import '../../documents/presentation/project_documents_section.dart';
import '../../finance/application/finance_providers.dart';
import '../../messaging/application/messaging_providers.dart';
import '../../messaging/presentation/start_chat.dart';
import '../../stages/application/stages_providers.dart';
import '../../stages/presentation/stages_section.dart';
import '../../tasks/application/tasks_view_providers.dart';
import '../../tasks/data/task_models.dart';
import '../../tasks/presentation/task_gantt.dart';
import '../../tasks/presentation/task_row.dart';
import '../../tasks/presentation/tasks_view_toggle.dart';
import '../application/project_actions.dart';
import '../application/project_time_providers.dart';
import '../application/projects_providers.dart';
import '../data/project_models.dart';
import '../data/project_time_models.dart';
import 'budget_variance_card.dart';
import 'project_budget_section.dart';
import 'project_management_flows.dart';
import 'project_time_section.dart';
import 'projects_screen.dart' show ProgressLine;

/// The parts of a project, one at a time. Which ones a person sees follows what
/// they may open.
enum _Tab {
  overview('Overview', Icons.dashboard_outlined),
  tasks('Tasks', Icons.checklist_rounded),
  time('Time', Icons.schedule_rounded),
  timeline('Timeline', Icons.timeline_rounded),
  budget('Budget', Icons.account_balance_wallet_outlined),
  changes('Changes', Icons.published_with_changes_outlined),
  documents('Documents', Icons.folder_open_outlined);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// One project. A short header (name, status, progress) with "Details" and
/// "Team" that open bottom sheets, then a row of tabs so nobody has to scroll
/// past every section: Overview (what is going on, each part a tap away), Tasks,
/// Timeline (stages), Budget, Changes and Documents. The budget and spending are
/// shown only to people who may read financials.
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  _Tab _tab = _Tab.overview;
  bool _showDone = false;

  /// A status or manager change is open or being sent: no second one starts.
  bool _changing = false;

  String get _id => widget.projectId;

  Future<void> _guarded(Future<void> Function() run) async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(projectDetailProvider(_id));
    ref.invalidate(projectTasksProvider(_id));
    ref.invalidate(projectTimeProvider(_id));
    ref.invalidate(projectStagesProvider(_id));
    ref.invalidate(projectBudgetProvider(_id));
    ref.invalidate(projectSpendingProvider(_id));
    ref.invalidate(projectChangeRequestsProvider(_id));
    ref.invalidate(projectDocumentsProvider(_id));
    try {
      await ref.read(projectDetailProvider(_id).future);
    } catch (_) {
      // The error state is shown by the screen itself.
    }
  }

  List<_Tab> _tabsFor() {
    final perms = ref.watch(permissionsProvider);
    return [
      _Tab.overview,
      if (perms.hasAny(Feature.tasks)) _Tab.tasks,
      if (perms.hasAny(Feature.timesheetsViewAll)) _Tab.time,
      if (perms.hasAny(Feature.stagesView)) _Tab.timeline,
      if (perms.hasAny(Feature.financials)) _Tab.budget,
      if (perms.hasAny(Feature.changeRequests)) _Tab.changes,
      if (perms.hasAny(Feature.projects)) _Tab.documents,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(projectDetailProvider(_id));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.name ?? 'Project')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 110),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(projectDetailProvider(_id)),
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(ProjectSummary p) {
    final c = context.colors;
    final tabs = _tabsFor();
    // A tab that is no longer allowed (permissions changed) falls back.
    final current = tabs.contains(_tab) ? _tab : _Tab.overview;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: c.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Space.sm,
                ),
                sliver: SliverToBoxAdapter(child: _header(p)),
              ),
              if (tabs.length > 1)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedRow(
                    height: 60 * scale,
                    background: c.background,
                    child: _tabRow(tabs, current),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Space.x4,
                ),
                sliver: SliverToBoxAdapter(child: _tabBody(current, p)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- header ------------------------------------------------------------

  Widget _header(ProjectSummary p) {
    final c = context.colors;
    final canManage = ref
        .watch(permissionsProvider)
        .hasAny(Feature.projectsManage);
    final dates = [
      if (p.startDate != null) 'Starts ${Fmt.day(p.startDate!)}',
      if (p.endDate != null) 'Ends ${Fmt.day(p.endDate!)}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (canManage)
              _StatusButton(
                status: p.status,
                onTap: _changing
                    ? null
                    : () =>
                          _guarded(() => changeProjectStatus(context, ref, p)),
              )
            else
              StatusBadge.status(p.status),
            if (p.code != null)
              Text(p.code!, style: AppType.label.copyWith(color: c.textMuted)),
            Text(
              '${p.completionPercent}% complete',
              style: AppType.label.copyWith(color: c.textMuted),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        ProgressLine(percent: p.completionPercent),
        if (dates.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(dates, style: AppType.bodySmall.copyWith(color: c.textMuted)),
        ],
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            _SheetChip(
              icon: Icons.info_outline_rounded,
              label: 'Details',
              onTap: () => _showSheet(
                _DetailsSheet(
                  project: p,
                  onAssignManager: canManage && !_changing
                      ? () => _guarded(
                          () => assignProjectManager(context, ref, p),
                        )
                      : null,
                ),
              ),
            ),
            _SheetChip(
              icon: Icons.group_outlined,
              label: 'Team ${p.members.length}',
              onTap: () => _showSheet(_TeamSheet(project: p)),
            ),
            if (canManage)
              _SheetChip(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: _changing
                    ? null
                    : () => context.push('/projects/$_id/edit'),
              ),
          ],
        ),
        if (canManage && p.projectManagerId == null) ...[
          const SizedBox(height: Space.md),
          _NoManagerBanner(
            onAssign: _changing
                ? null
                : () => _guarded(() => assignProjectManager(context, ref, p)),
          ),
        ],
      ],
    );
  }

  void _showSheet(Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  }

  // ---- tabs --------------------------------------------------------------

  Widget _tabRow(List<_Tab> tabs, _Tab current) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: ChoiceChip(
                label: Text(_labelFor(t)),
                avatar: Icon(t.icon, size: 18),
                selected: t == current,
                onSelected: (_) => setState(() => _tab = t),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
        ],
      ),
    );
  }

  /// The tab's name, with a count where one is already known.
  String _labelFor(_Tab t) {
    int? n;
    switch (t) {
      case _Tab.tasks:
        n = ref.watch(projectTasksProvider(_id)).value?.total;
      case _Tab.changes:
        n = ref.watch(projectChangeRequestsProvider(_id)).value?.length;
      case _Tab.documents:
        n = ref.watch(projectDocumentsProvider(_id)).value?.length;
      case _Tab.overview || _Tab.time || _Tab.timeline || _Tab.budget:
        n = null;
    }
    return n == null || n == 0 ? t.label : '${t.label} $n';
  }

  Widget _tabBody(_Tab tab, ProjectSummary p) {
    switch (tab) {
      case _Tab.overview:
        return _Overview(
          projectId: _id,
          onOpen: (t) => setState(() => _tab = t),
        );
      case _Tab.tasks:
        return _tasks();
      case _Tab.time:
        return ProjectTimeSection(projectId: _id);
      case _Tab.timeline:
        return StagesSection(projectId: _id);
      case _Tab.budget:
        return ProjectBudgetSection(projectId: _id);
      case _Tab.changes:
        return ChangeRequestsSection(projectId: _id);
      case _Tab.documents:
        return ProjectDocumentsSection(projectId: _id);
    }
  }

  // ---- tasks tab ---------------------------------------------------------

  Widget _tasks() {
    final addTask = ref.watch(permissionsProvider).hasAny(Feature.tasksCreate);
    final tasks = ref.watch(projectTasksProvider(_id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (addTask)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: AppButton(
              label: 'Add task',
              icon: Icons.add_rounded,
              onPressed: () => context.push('/projects/$_id/new-task'),
            ),
          ),
        tasks.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: Space.xl),
            child: SkeletonList(rows: 2, rowHeight: 96),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.only(top: Space.xl),
            child: ErrorPanel(
              error: e,
              compact: true,
              onRetry: () => ref.invalidate(projectTasksProvider(_id)),
            ),
          ),
          data: (page) {
            final byStatus = <String, List<TaskItem>>{};
            for (final t in page.items) {
              byStatus.putIfAbsent(t.status, () => []).add(t);
            }
            const order = [
              TaskStatus.blocked,
              TaskStatus.inProgress,
              TaskStatus.review,
              TaskStatus.todo,
            ];
            final done = byStatus[TaskStatus.done] ?? const <TaskItem>[];
            final open = [for (final s in order) ...?byStatus[s]];
            final c = context.colors;
            final view = ref.watch(tasksViewProvider);
            final gantt = view.mode == TasksViewMode.gantt;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader('TASKS ${page.total}'),
                if (page.items.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: Space.sm),
                    child: TasksViewToggle(),
                  ),
                if (page.items.isEmpty)
                  const EmptyState(
                    icon: Icons.checklist_rounded,
                    title: 'No tasks yet',
                    message: 'Tasks added to this project will appear here.',
                  ),
                if (gantt && page.items.isNotEmpty)
                  TaskGantt(
                    tasks: [...open, if (_showDone) ...done],
                    scale: view.scale,
                    onScaleChanged: (s) =>
                        ref.read(tasksViewProvider.notifier).setScale(s),
                    onOpenTask: (t) => context.push('/tasks/${t.id}'),
                  )
                else
                  for (final s in order)
                    if ((byStatus[s] ?? const <TaskItem>[]).isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: Space.md,
                          bottom: Space.sm,
                        ),
                        child: Text(
                          '${statusInfo(s).label.toUpperCase()} ${byStatus[s]!.length}',
                          style: AppType.overline.copyWith(color: c.textMuted),
                        ),
                      ),
                      for (final t in byStatus[s]!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: TaskRow(
                            task: t,
                            onTap: () => context.push('/tasks/${t.id}'),
                          ),
                        ),
                    ],
                if (done.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  AppButton(
                    label: _showDone
                        ? 'Hide ${done.length} done'
                        : 'Show ${done.length} done',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => setState(() => _showDone = !_showDone),
                  ),
                  if (_showDone && !gantt)
                    for (final t in done)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: TaskRow(
                          task: t,
                          onTap: () => context.push('/tasks/${t.id}'),
                        ),
                      ),
                ],
                if (page.truncated)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: Text(
                      'Showing the first ${page.items.length} of ${page.total} tasks.',
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                  ),
                if (open.isEmpty && done.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: Text(
                      'Every task is done.',
                      style: AppType.body.copyWith(color: c.success),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Keeps the tab row on screen while the page scrolls under it.
class _PinnedRow extends SliverPersistentHeaderDelegate {
  _PinnedRow({
    required this.height,
    required this.child,
    required this.background,
  });
  final double height;
  final Widget child;
  final Color background;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: background,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  @override
  bool shouldRebuild(covariant _PinnedRow old) => true;
}

/// A small tappable chip that opens a bottom sheet.
/// The status as a badge that opens the status choices.
class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onTap});
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Status: ${statusInfo(status).label}. Change the status',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusBadge.status(status),
              const SizedBox(width: Space.xs),
              Icon(Icons.expand_more_rounded, size: 20, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown to people who may assign one when the project has no manager.
class _NoManagerBanner extends StatelessWidget {
  const _NoManagerBanner({required this.onAssign});
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = c.tone(StatusTone.warning);
    return AppCard(
      color: tone.background,
      child: Row(
        children: [
          Icon(Icons.engineering_outlined, color: tone.foreground),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'No project manager yet.',
              style: AppType.bodySmall.copyWith(color: tone.foreground),
            ),
          ),
          const SizedBox(width: Space.sm),
          AppButton(
            label: 'Assign',
            compact: true,
            expand: false,
            variant: AppButtonVariant.secondary,
            onPressed: onAssign,
          ),
        ],
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  const _SheetChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onPressed: onTap,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

// ---- overview ------------------------------------------------------------

/// What is going on in the project, one tile per part, each a tap from its tab.
class _Overview extends ConsumerWidget {
  const _Overview({required this.projectId, required this.onOpen});
  final String projectId;
  final ValueChanged<_Tab> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final tiles = <Widget>[];

    if (perms.hasAny(Feature.tasks)) {
      final t = ref.watch(projectTasksProvider(projectId));
      tiles.add(
        _Glance(
          icon: _Tab.tasks.icon,
          label: 'Tasks',
          value: t.when(
            data: (p) => '${p.items.where((i) => !i.isDone).length} open',
            loading: () => '…',
            error: (_, _) => '—',
          ),
          caption: t.value == null ? null : 'of ${t.value!.total}',
          onTap: () => onOpen(_Tab.tasks),
        ),
      );
    }
    if (perms.hasAny(Feature.timesheetsViewAll)) {
      final t = ref.watch(projectTimeProvider(projectId));
      tiles.add(
        _Glance(
          icon: _Tab.time.icon,
          label: 'Time',
          value: t.when(
            data: (d) => Fmt.hours(projectTotalHours(d.slices, DateTime.now())),
            loading: () => '…',
            error: (_, _) => '—',
          ),
          caption: 'Tap for the team\'s hours',
          onTap: () => onOpen(_Tab.time),
        ),
      );
    }
    if (perms.hasAny(Feature.stagesView)) {
      final s = ref.watch(projectStagesProvider(projectId));
      tiles.add(
        _Glance(
          icon: _Tab.timeline.icon,
          label: 'Timeline',
          value: s.when(
            data: (list) => list.isEmpty
                ? 'No stages'
                : '${list.where((x) => x.isFinished).length} of ${list.length}',
            loading: () => '…',
            error: (_, _) => '—',
          ),
          caption: s.value == null || s.value!.isEmpty ? null : 'stages done',
          onTap: () => onOpen(_Tab.timeline),
        ),
      );
    }
    if (perms.hasAny(Feature.changeRequests)) {
      final r = ref.watch(projectChangeRequestsProvider(projectId));
      tiles.add(
        _Glance(
          icon: _Tab.changes.icon,
          label: 'Changes',
          value: r.when(
            data: (list) => list.isEmpty ? 'None' : '${list.length}',
            loading: () => '…',
            error: (_, _) => '—',
          ),
          caption: r.value == null || r.value!.isEmpty ? null : 'requests',
          onTap: () => onOpen(_Tab.changes),
        ),
      );
    }
    if (perms.hasAny(Feature.projects)) {
      final d = ref.watch(projectDocumentsProvider(projectId));
      tiles.add(
        _Glance(
          icon: _Tab.documents.icon,
          label: 'Documents',
          value: d.when(
            data: (list) => list.isEmpty ? 'None' : '${list.length}',
            loading: () => '…',
            error: (_, _) => '—',
          ),
          caption: d.value == null || d.value!.isEmpty ? null : 'files',
          onTap: () => onOpen(_Tab.documents),
        ),
      );
    }

    final showBudget = perms.hasAny(Feature.financials);
    if (tiles.isEmpty && !showBudget) {
      return const Padding(
        padding: EdgeInsets.only(top: Space.x3),
        child: EmptyState(
          icon: Icons.dashboard_outlined,
          title: 'Nothing more to show',
          message: 'Your role can see this project\'s summary above.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The budget variance and its alerts come first: it is what needs
        // attention soonest.
        if (showBudget)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: BudgetVarianceCard(
              projectId: projectId,
              onOpen: () => onOpen(_Tab.budget),
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            // Two to a row; one per row when text is enlarged.
            final wide = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
            final w = wide ? (box.maxWidth - Space.sm) / 2 : box.maxWidth;
            return Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [for (final t in tiles) SizedBox(width: w, child: t)],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Glance extends StatelessWidget {
  const _Glance({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.caption,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      semanticLabel: '$label: $value${caption == null ? '' : ', $caption'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: Sizes.iconSm, color: c.textMuted),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppType.label.copyWith(color: c.textMuted),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.textMuted),
            ],
          ),
          const SizedBox(height: Space.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppType.sectionTitle.copyWith(color: c.text),
            ),
          ),
          if (caption != null)
            Text(caption!, style: AppType.helper.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}

// ---- bottom sheets ---------------------------------------------------------

/// Everything about the project that is not a number: about, site, dates and the
/// client, with calling and emailing the contact.
class _DetailsSheet extends ConsumerWidget {
  const _DetailsSheet({required this.project, this.onAssignManager});
  final ProjectSummary project;

  /// Set for people who may change the manager.
  final VoidCallback? onAssignManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = project;
    final launcher = ref.read(contactLauncherProvider);
    final managerId = p.projectManagerId;
    // The manager is usually on the team; otherwise the directory (which needs
    // permission to see the team) is asked for the name.
    final managerName = managerId == null
        ? null
        : p.members.where((m) => m.id == managerId).firstOrNull?.name ??
              (ref.watch(permissionsProvider).hasAny(Feature.team)
                  ? ref.watch(personNameProvider(managerId)).value
                  : null);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Details', style: AppType.sectionTitle.copyWith(color: c.text)),
          const SizedBox(height: Space.md),
          if (p.description != null) ...[
            Text(p.description!, style: AppType.body.copyWith(color: c.text)),
            const SizedBox(height: Space.md),
          ],
          if (p.siteAddress != null)
            _Fact(Icons.place_outlined, 'Site', p.siteAddress!),
          if (p.projectType != null)
            _Fact(
              Icons.category_outlined,
              'Type',
              ProjectKind.label(p.projectType!),
            ),
          _Fact(
            Icons.engineering_outlined,
            'Manager',
            managerId == null ? 'Not assigned' : (managerName ?? 'Assigned'),
          ),
          if (onAssignManager != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAssignManager!();
                },
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: Text(
                  managerId == null ? 'Assign a manager' : 'Change the manager',
                ),
              ),
            ),
          if (p.startDate != null)
            _Fact(
              Icons.event_available_rounded,
              'Starts',
              Fmt.day(p.startDate!),
            ),
          if (p.endDate != null)
            _Fact(Icons.event_rounded, 'Ends', Fmt.day(p.endDate!)),
          if (p.clientName != null)
            _Fact(Icons.business_outlined, 'Client', p.clientName!),
          if (p.clientContact != null)
            _Fact(Icons.person_outline_rounded, 'Contact', p.clientContact!),
          if (p.clientPhone != null)
            _Fact(Icons.phone_outlined, 'Phone', p.clientPhone!),
          if (p.clientEmail != null)
            _Fact(Icons.mail_outline_rounded, 'Email', p.clientEmail!),
          if (p.clientPhone != null) ...[
            const SizedBox(height: Space.md),
            AppButton(
              label: 'Call the client',
              icon: Icons.call_outlined,
              onPressed: () async {
                final ok = await launcher.call(p.clientPhone!);
                if (!ok && context.mounted) {
                  Snack.show(
                    context,
                    'Could not start the call. The number is ${p.clientPhone}.',
                  );
                }
              },
            ),
          ],
          if (p.clientEmail != null) ...[
            const SizedBox(height: Space.sm),
            AppButton(
              label: 'Email the client',
              icon: Icons.mail_outline_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                final ok = await launcher.email(p.clientEmail!);
                if (!ok && context.mounted) {
                  Snack.show(
                    context,
                    'Could not open email. The address is ${p.clientEmail}.',
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamSheet extends ConsumerStatefulWidget {
  const _TeamSheet({required this.project});
  final ProjectSummary project;

  @override
  ConsumerState<_TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends ConsumerState<_TeamSheet> {
  String? _opening;

  bool _isManager(PersonRef m) => m.id == widget.project.projectManagerId;

  /// Opens the chat with [m] (making it when there is none) and closes the sheet
  /// to show it.
  Future<void> _message(PersonRef m) async {
    if (_opening != null) return;
    setState(() => _opening = m.id);
    final router = GoRouter.of(context);
    try {
      final id = await ref.read(chatActionsProvider).openDirect(m.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      router.push('/messages/$id');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final members = widget.project.members;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Team ${members.length}',
            style: AppType.sectionTitle.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.md),
          if (members.isEmpty)
            Text(
              'No one has been added to this project yet.',
              style: AppType.body.copyWith(color: c.textMuted),
            )
          else
            for (final m in members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: c.primarySoft,
                      child: Text(
                        m.name.isEmpty ? '?' : m.name[0].toUpperCase(),
                        style: AppType.label.copyWith(color: c.primaryText),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isManager(m) ? '${m.name} (manager)' : m.name,
                            style: AppType.bodyStrong.copyWith(color: c.text),
                          ),
                          if (m.role != null)
                            Text(
                              m.role!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.bodySmall.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (canMessage(ref, m.id))
                      _opening == m.id
                          ? const Padding(
                              padding: EdgeInsets.all(Space.md),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Message ${m.name}',
                              onPressed: _opening == null
                                  ? () => _message(m)
                                  : null,
                              icon: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: c.primary,
                              ),
                            ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: Sizes.iconSm, color: c.textMuted),
          const SizedBox(width: Space.md),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

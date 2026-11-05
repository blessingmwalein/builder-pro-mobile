import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/projects_providers.dart';
import '../data/project_models.dart';

/// Projects the supervisor or manager can open.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(projectsCatalogProvider.notifier).search(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectsCatalogProvider);
    final notifier = ref.read(projectsCatalogProvider.notifier);

    const filters = <(String?, String)>[
      (null, 'All'),
      (ProjectStatus.active, 'Active'),
      (ProjectStatus.onHold, 'On hold'),
      (ProjectStatus.completed, 'Completed'),
      (ProjectStatus.draft, 'Draft'),
    ];

    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        const PageTitle('Projects'),
        AppTextField(
          label: 'Search projects',
          controller: _search,
          hint: 'Name or code',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: _onSearch,
          onSubmitted: notifier.search,
        ),
        const SizedBox(height: Space.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (value, label) in filters)
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: state.status == value,
                    onSelected: (_) => notifier.setStatus(value),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        ..._list(state, notifier),
      ],
    );
  }

  List<Widget> _list(ProjectsState state, ProjectsCatalog notifier) {
    if (state.loading) return const [SkeletonList(rows: 4, rowHeight: 110)];
    if (state.error != null) {
      return [
        ErrorPanel(
          error: state.error!,
          compact: true,
          onRetry: notifier.refresh,
        ),
      ];
    }
    if (state.items.isEmpty) {
      final filtered = state.query.isNotEmpty || state.status != null;
      return [
        Padding(
          padding: const EdgeInsets.only(top: Space.x3),
          child: EmptyState(
            icon: Icons.apartment_rounded,
            title: filtered ? 'No projects match' : 'No projects yet',
            message: filtered
                ? 'Try another word or status.'
                : 'Projects created on the web app will appear here.',
          ),
        ),
      ];
    }
    return [
      for (final p in state.items)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: _ProjectCard(
            project: p,
            onTap: () => context.push('/projects/${p.id}'),
          ),
        ),
      if (state.loadMoreError != null)
        ErrorPanel(
          error: state.loadMoreError!,
          compact: true,
          onRetry: notifier.loadMore,
        ),
      if (state.hasMore && state.loadMoreError == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: AppButton(
            label: 'Show more',
            variant: AppButtonVariant.secondary,
            loading: state.loadingMore,
            onPressed: notifier.loadMore,
          ),
        ),
    ];
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = project;
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '${p.label}, ${statusInfo(p.status).label}, ${p.completionPercent} percent complete',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
              ),
              const SizedBox(width: Space.sm),
              StatusBadge.status(p.status),
            ],
          ),
          if (p.code != null || p.clientName != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                [
                  if (p.code != null) p.code!,
                  if (p.clientName != null) p.clientName!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          const SizedBox(height: Space.md),
          ProgressLine(percent: p.completionPercent),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            children: [
              _Meta(Icons.checklist_rounded, '${p.taskCount} tasks'),
              _Meta(Icons.group_outlined, '${p.memberCount} on team'),
              if (p.endDate != null)
                _Meta(Icons.event_rounded, 'Ends ${Fmt.day(p.endDate!)}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Completion bar with the percentage written out (never colour alone).
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$percent percent complete',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
                color: c.primary,
                backgroundColor: c.surfaceMuted,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Text('$percent%', style: AppType.label.copyWith(color: c.text)),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c.textMuted),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(text, style: AppType.helper.copyWith(color: c.textMuted)),
        ),
      ],
    );
  }
}

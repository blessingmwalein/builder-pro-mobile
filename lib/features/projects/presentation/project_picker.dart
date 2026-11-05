import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../application/projects_providers.dart';
import '../data/project_models.dart';

/// How many pages of projects the picker loads (20 each).
const projectPickerPages = 5;

/// Lets the user choose a project from the company's list, whatever search or
/// status filter the Projects screen currently has applied (it reads its own
/// pages, not that screen's list). Returns null when dismissed or when the list
/// could not be loaded (the error is shown); a result with a null value means
/// "no project" when [clearLabel] was offered.
Future<({ProjectSummary? value})?> chooseProject(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  ProjectSummary? selected,
  String? clearLabel,
}) async {
  final repo = ref.read(projectsRepositoryProvider);
  final projects = <ProjectSummary>[];
  try {
    for (var page = 1; page <= projectPickerPages; page++) {
      final result = await repo.list(page: page);
      final known = projects.map((p) => p.id).toSet();
      projects.addAll(result.items.where((p) => !known.contains(p.id)));
      if (!result.hasMore) break;
    }
  } on AppException catch (e) {
    if (context.mounted) Snack.error(context, e);
    return null;
  }
  if (!context.mounted) return null;
  // Fresh objects: match the current choice by id so it shows as selected.
  final current = projects.where((p) => p.id == selected?.id).firstOrNull;
  return pickOne<ProjectSummary>(
    context,
    title: title,
    selected: current,
    clearLabel: clearLabel,
    emptyMessage: 'No projects to choose from.',
    options: [
      for (final p in projects)
        PickerOption(value: p, title: p.name, subtitle: p.code),
    ],
  );
}

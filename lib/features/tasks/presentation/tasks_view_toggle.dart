import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/tasks_view_providers.dart';

/// Switches a list of tasks between tiles and the Gantt chart. The choice is
/// kept for next time.
class TasksViewToggle extends ConsumerWidget {
  const TasksViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(tasksViewProvider.select((v) => v.mode));
    return SegmentedButton<TasksViewMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.padded),
      segments: const [
        ButtonSegment(
          value: TasksViewMode.tiles,
          icon: Icon(Icons.view_agenda_outlined),
          label: Text('Tiles'),
        ),
        ButtonSegment(
          value: TasksViewMode.gantt,
          icon: Icon(Icons.align_horizontal_left_rounded),
          label: Text('Gantt'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) =>
          ref.read(tasksViewProvider.notifier).setMode(s.first),
    );
  }
}

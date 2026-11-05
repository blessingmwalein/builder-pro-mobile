import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/preferences_store.dart';
import 'gantt_layout.dart';

/// How a list of tasks is shown: as tiles, or as a Gantt chart on a calendar.
enum TasksViewMode { tiles, gantt }

/// The person's choice of view, and how much time the chart covers.
class TasksView {
  const TasksView({
    this.mode = TasksViewMode.tiles,
    this.scale = GanttScale.week,
  });

  final TasksViewMode mode;
  final GanttScale scale;

  TasksView copyWith({TasksViewMode? mode, GanttScale? scale}) =>
      TasksView(mode: mode ?? this.mode, scale: scale ?? this.scale);
}

/// The view choice, kept per person on this phone so the screen opens the way
/// it was left. Starts as tiles until the saved choice has been read, and
/// nothing about it is ever sent anywhere.
class TasksViewPreference extends Notifier<TasksView> {
  String? get _key {
    final uid = ref.read(currentUserIdProvider);
    return uid == null ? null : 'bp_tasks_view_$uid';
  }

  @override
  TasksView build() {
    ref.watch(currentUserIdProvider);
    Future<void>.microtask(_load);
    return const TasksView();
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    final saved = await ref.read(preferencesStoreProvider).readString(key);
    if (!ref.mounted || saved == null) return;
    final parts = saved.split(',');
    final mode = TasksViewMode.values
        .where((m) => m.name == parts.first)
        .firstOrNull;
    final scale = parts.length > 1
        ? GanttScale.values.where((s) => s.name == parts[1]).firstOrNull
        : null;
    state = TasksView(mode: mode ?? state.mode, scale: scale ?? state.scale);
  }

  Future<void> _save() async {
    final key = _key;
    if (key == null) return;
    await ref
        .read(preferencesStoreProvider)
        .writeString(key, '${state.mode.name},${state.scale.name}');
  }

  Future<void> setMode(TasksViewMode mode) async {
    state = state.copyWith(mode: mode);
    await _save();
  }

  Future<void> setScale(GanttScale scale) async {
    state = state.copyWith(scale: scale);
    await _save();
  }
}

final tasksViewProvider = NotifierProvider<TasksViewPreference, TasksView>(
  TasksViewPreference.new,
);

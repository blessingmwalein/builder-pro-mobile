import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';
import '../../time/data/time_models.dart';

/// Task statuses the backend accepts, in the order shown to the worker.
abstract final class TaskStatus {
  static const todo = 'TODO';
  static const inProgress = 'IN_PROGRESS';
  static const blocked = 'BLOCKED';
  static const review = 'REVIEW';
  static const done = 'DONE';

  static const all = [todo, inProgress, blocked, review, done];
}

@immutable
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.content,
    required this.isDone,
  });

  final String id;
  final String content;
  final bool isDone;

  ChecklistItem copyWith({bool? isDone}) =>
      ChecklistItem(id: id, content: content, isDone: isDone ?? this.isDone);

  static ChecklistItem? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return ChecklistItem(
      id: id,
      content: J.strOr(m['content']),
      isDone: J.boolean(m['isDone']),
    );
  }
}

@immutable
class Checklist {
  const Checklist({required this.id, required this.title, required this.items});

  final String id;
  final String title;
  final List<ChecklistItem> items;

  int get doneCount => items.where((i) => i.isDone).length;

  Checklist withItem(String itemId, bool isDone) => Checklist(
    id: id,
    title: title,
    items: [
      for (final i in items)
        if (i.id == itemId) i.copyWith(isDone: isDone) else i,
    ],
  );

  static Checklist? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return Checklist(
      id: id,
      title: J.strOr(m['title'], 'Checklist'),
      items: J
          .maps(m['items'])
          .map(ChecklistItem.tryParse)
          .whereType<ChecklistItem>()
          .toList(),
    );
  }
}

@immutable
class TaskComment {
  const TaskComment({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.authorName,
    this.authorId,
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final String authorName;
  final String? authorId;

  static TaskComment? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final user = J.map(m['user']);
    final name = '${J.strOr(user['firstName'])} ${J.strOr(user['lastName'])}'
        .trim();
    return TaskComment(
      id: id,
      content: J.strOr(m['content']),
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      authorName: name.isEmpty ? 'Team member' : name,
      authorId: J.str(user['id']) ?? J.str(m['userId']),
    );
  }
}

@immutable
class TaskAttachment {
  const TaskAttachment({
    required this.id,
    required this.fileName,
    this.contentType,
    this.sizeBytes,
  });

  final String id;
  final String fileName;
  final String? contentType;
  final int? sizeBytes;

  bool get isImage => (contentType ?? '').startsWith('image/');

  static TaskAttachment? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return TaskAttachment(
      id: id,
      fileName: J.strOr(m['fileName'], 'Attachment'),
      contentType: J.str(m['contentType']),
      sizeBytes: J.integer(m['sizeBytes']),
    );
  }
}

@immutable
class SubTask {
  const SubTask({required this.id, required this.title, required this.status});
  final String id;
  final String title;
  final String status;
}

/// A person assigned to a task.
@immutable
class TaskAssignee {
  const TaskAssignee({required this.id, required this.name});
  final String id;
  final String name;

  static TaskAssignee? tryParse(Map<String, dynamic> assignment) {
    final u = J.map(assignment['user']);
    final id = J.str(u['id']) ?? J.str(assignment['userId']);
    if (id == null) return null;
    final name = '${J.strOr(u['firstName'])} ${J.strOr(u['lastName'])}'.trim();
    return TaskAssignee(
      id: id,
      name: name.isEmpty ? J.strOr(u['email'], 'Team member') : name,
    );
  }
}

/// A task as returned by `my-queue` or `GET /tasks/:id` (the detail adds
/// comments and subtasks). [raw] is the original JSON, kept so the offline
/// cache stores exactly what the server sent.
@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.project,
    this.description,
    this.dueDate,
    this.startDate,
    this.estimatedHours,
    this.createdAt,
    this.stageId,
    this.assignees = const [],
    this.checklists = const [],
    this.commentCount = 0,
    this.attachmentCount = 0,
    this.comments = const [],
    this.subtasks = const [],
    this.raw = const {},
  });

  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final ProjectRef project;
  final DateTime? dueDate;
  final DateTime? startDate;
  final double? estimatedHours;
  final DateTime? createdAt;

  /// The project stage (a step of its timeline) this task belongs to, if any.
  final String? stageId;
  final List<TaskAssignee> assignees;
  final List<Checklist> checklists;
  final int commentCount;
  final int attachmentCount;
  final List<TaskComment> comments;
  final List<SubTask> subtasks;
  final Map<String, dynamic> raw;

  List<String> get assigneeNames => [for (final a in assignees) a.name];

  int get checklistTotal => checklists.fold(0, (s, c) => s + c.items.length);
  int get checklistDone => checklists.fold(0, (s, c) => s + c.doneCount);
  bool get isDone => status == TaskStatus.done;

  bool isOverdue(DateTime now) {
    final due = dueDate?.toLocal();
    if (due == null || isDone) return false;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(due.year, due.month, due.day).isBefore(today);
  }

  TaskItem copyWith({
    String? status,
    List<Checklist>? checklists,
    List<TaskComment>? comments,
    int? commentCount,
    int? attachmentCount,
    List<TaskAssignee>? assignees,
  }) => TaskItem(
    id: id,
    title: title,
    description: description,
    status: status ?? this.status,
    priority: priority,
    project: project,
    dueDate: dueDate,
    startDate: startDate,
    estimatedHours: estimatedHours,
    createdAt: createdAt,
    stageId: stageId,
    assignees: assignees ?? this.assignees,
    checklists: checklists ?? this.checklists,
    commentCount: commentCount ?? this.commentCount,
    attachmentCount: attachmentCount ?? this.attachmentCount,
    comments: comments ?? this.comments,
    subtasks: subtasks,
    // Keep the cached JSON in step with the status the user just set.
    raw: status == null ? raw : {...raw, 'status': status},
  );

  static TaskItem? tryParse(Object? json) {
    final m = J.map(json);
    final id = J.str(m['id']);
    if (id == null) return null;
    final count = J.map(m['_count']);
    final project =
        ProjectRef.tryParse(m['project']) ??
        ProjectRef(id: J.strOr(m['projectId']), name: 'Project');
    return TaskItem(
      id: id,
      title: J.strOr(m['title'], 'Untitled task'),
      description: J.str(m['description']),
      status: J.strOr(m['status'], TaskStatus.todo),
      priority: J.strOr(m['priority'], 'MEDIUM'),
      project: project,
      dueDate: J.date(m['dueDate']),
      startDate: J.date(m['startDate']),
      estimatedHours: J.number(m['estimatedHours']),
      createdAt: J.date(m['createdAt']),
      stageId: J.str(m['stageId']),
      assignees: J
          .maps(m['assignees'])
          .map(TaskAssignee.tryParse)
          .whereType<TaskAssignee>()
          .toList(),
      checklists: J
          .maps(m['checklists'])
          .map(Checklist.tryParse)
          .whereType<Checklist>()
          .toList(),
      commentCount:
          J.integer(count['comments']) ?? J.list(m['comments']).length,
      attachmentCount: J.integer(count['attachments']) ?? 0,
      comments: J
          .maps(m['comments'])
          .map(TaskComment.tryParse)
          .whereType<TaskComment>()
          .toList(),
      subtasks: [
        for (final s in J.maps(m['subtasks']))
          if (J.str(s['id']) != null)
            SubTask(
              id: J.strOr(s['id']),
              title: J.strOr(s['title'], 'Subtask'),
              status: J.strOr(s['status'], TaskStatus.todo),
            ),
      ],
      raw: m,
    );
  }
}

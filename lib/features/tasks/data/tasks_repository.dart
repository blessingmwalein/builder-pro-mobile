import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'task_models.dart';

/// `/tasks/*` for the worker experience.
class TasksRepository {
  TasksRepository(this._api);

  final ApiClient _api;

  /// `GET /tasks/my-queue`: a plain array (at most 50), already limited to the
  /// caller's assignments and excluding DONE.
  Future<List<TaskItem>> myQueue() async {
    final body = await _api.get('tasks/my-queue');
    final rows = body is List ? body : J.list(J.map(body)['items']);
    return rows.map(TaskItem.tryParse).whereType<TaskItem>().toList();
  }

  Future<TaskItem> detail(String id) async {
    final body = await _api.get('tasks/$id');
    final task = TaskItem.tryParse(body);
    if (task == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected task response.',
      );
    }
    return task;
  }

  Future<List<TaskAttachment>> attachments(String id) async {
    final body = await _api.get('tasks/$id/attachments');
    return J
        .maps(body is List ? body : J.map(body)['items'])
        .map(TaskAttachment.tryParse)
        .whereType<TaskAttachment>()
        .toList();
  }

  /// `PUT /tasks/:id/status`. Setting a status is idempotent, so it is safe to
  /// queue offline and to repeat.
  Future<void> updateStatus(String id, String status) async {
    await _api.put('tasks/$id/status', body: {'status': status});
  }

  /// `PUT …/toggle` FLIPS the item on the server, so it is NOT idempotent: it
  /// must never be queued or retried blindly. Callers re-read the task after an
  /// uncertain failure.
  Future<void> toggleChecklistItem({
    required String taskId,
    required String checklistId,
    required String itemId,
  }) async {
    await _api.put(
      'tasks/$taskId/checklists/$checklistId/items/$itemId/toggle',
    );
  }

  /// `POST /tasks`. NOT idempotent: every call makes another task, so callers
  /// never repeat it blindly.
  Future<TaskItem> createTask({
    required String projectId,
    required String title,
    String? description,
    String priority = 'MEDIUM',
    DateTime? dueDate,
    double? estimatedHours,
    List<String> assigneeIds = const [],
    String? stageId,
  }) async {
    final body = await _api.post(
      'tasks',
      body: {
        'projectId': projectId,
        'stageId': ?stageId,
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'priority': priority,
        if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
        'estimatedHours': ?estimatedHours,
        if (assigneeIds.isNotEmpty) 'assigneeIds': assigneeIds,
      },
    );
    final task = TaskItem.tryParse(body);
    if (task == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The task may have been created.',
      );
    }
    return task;
  }

  /// `PUT /tasks/:id` (needs `tasks.*`). Sets the given fields, so it is safe to
  /// repeat. The API cannot CLEAR a due date or an estimate, so null means
  /// "leave as it is"; an empty [description] clears the description.
  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    String? priority,
    DateTime? dueDate,
    double? estimatedHours,
    String? stageId,
    bool setStage = false,
  }) async {
    await _api.put(
      'tasks/$id',
      body: {
        // The stage is the one field that can be cleared: null (sent as null)
        // unlinks the task, so it is only sent when [setStage] says to.
        if (setStage) 'stageId': stageId,
        'title': ?title,
        'description': ?description,
        'priority': ?priority,
        if (dueDate != null) 'dueDate': dueDate.toUtc().toIso8601String(),
        'estimatedHours': ?estimatedHours,
      },
    );
  }

  /// `POST /tasks/:id/assignees/:userId`. An upsert on the server, so repeating
  /// it is harmless.
  Future<void> addAssignee(String taskId, String userId) async {
    await _api.post('tasks/$taskId/assignees/$userId');
  }

  /// `DELETE /tasks/:id/assignees/:userId`. Idempotent as well.
  Future<void> removeAssignee(String taskId, String userId) async {
    await _api.delete('tasks/$taskId/assignees/$userId');
  }

  Future<TaskComment> addComment(String taskId, String content) async {
    final body = await _api.post(
      'tasks/$taskId/comments',
      body: {'content': content},
    );
    final comment = TaskComment.tryParse(J.map(body));
    if (comment == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. Your comment may have been saved.',
      );
    }
    return comment;
  }

  /// Multipart field `file`; jpeg/png/webp/pdf/doc/docx up to 20 MB (no HEIC).
  Future<TaskAttachment> uploadAttachment({
    required String taskId,
    required String path,
    required String fileName,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final body = await _api.postMultipart(
      'tasks/$taskId/attachments',
      () => FormData.fromMap({
        'file': MultipartFile.fromFileSync(
          path,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      }),
      onProgress: onProgress,
    );
    final attachment = TaskAttachment.tryParse(J.map(body));
    if (attachment == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The photo may have been saved.',
      );
    }
    return attachment;
  }
}

/// Mime types the backend accepts for task attachments.
const taskAttachmentMimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
};

/// Null when the extension is not accepted (e.g. HEIC from some iPhones).
String? mimeTypeForAttachment(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  return taskAttachmentMimeTypes[fileName.substring(dot + 1).toLowerCase()];
}

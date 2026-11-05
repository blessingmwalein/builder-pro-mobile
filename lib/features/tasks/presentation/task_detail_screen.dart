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
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/services/photo_picker.dart';
import '../application/tasks_providers.dart';
import 'assignee_sheet.dart';
import '../data/task_models.dart';
import '../data/tasks_repository.dart';
import '../../stages/application/stages_providers.dart';
import '../../stages/data/stage_models.dart';

class _StatusAction {
  const _StatusAction(
    this.label,
    this.target,
    this.icon, {
    this.primary = false,
  });
  final String label;
  final String target;
  final IconData icon;
  final bool primary;
}

/// What the worker can do next from each status.
List<_StatusAction> _actionsFor(String status) {
  const start = _StatusAction(
    'Start work',
    TaskStatus.inProgress,
    Icons.play_arrow_rounded,
    primary: true,
  );
  const done = _StatusAction(
    'Mark done',
    TaskStatus.done,
    Icons.check_circle_outline_rounded,
    primary: true,
  );
  const review = _StatusAction(
    'Send for review',
    TaskStatus.review,
    Icons.rate_review_outlined,
  );
  const blocked = _StatusAction(
    'Mark blocked',
    TaskStatus.blocked,
    Icons.block_rounded,
  );
  const resume = _StatusAction(
    'Resume work',
    TaskStatus.inProgress,
    Icons.play_arrow_rounded,
    primary: true,
  );
  const reopen = _StatusAction(
    'Reopen',
    TaskStatus.inProgress,
    Icons.replay_rounded,
  );
  return switch (status) {
    TaskStatus.todo => [start],
    TaskStatus.inProgress => [done, review, blocked],
    TaskStatus.blocked => [resume],
    TaskStatus.review => [done, resume],
    TaskStatus.done => [reopen],
    _ => const [],
  };
}

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _comment = TextEditingController();
  bool _changingStatus = false;
  bool _sendingComment = false;
  double? _uploadProgress;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  TaskDetailController get _controller =>
      ref.read(taskDetailProvider(widget.taskId).notifier);

  Future<void> _setStatus(String target) async {
    if (target == TaskStatus.done) {
      final ok = await confirmAction(
        context,
        title: 'Mark this task done?',
        message: 'It will show as done for everyone on the project.',
        confirmLabel: 'Mark done',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _changingStatus = true);
    try {
      final outcome = await ref
          .read(taskActionsProvider)
          .setStatus(widget.taskId, target);
      _controller.applyStatus(target);
      if (!mounted) return;
      if (outcome == StatusOutcome.queued) {
        Snack.show(
          context,
          'Saved on your phone. It will be sent when you are back online.',
        );
      } else if (target == TaskStatus.done) {
        Snack.show(context, 'Task marked done.');
      }
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _changingStatus = false);
    }
  }

  Future<void> _toggle(String checklistId, String itemId) async {
    try {
      await _controller.toggleItem(checklistId, itemId);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      await _controller.addComment(text);
      _comment.clear();
    } on AppException catch (e) {
      // The text stays in the box so nothing typed on site is lost.
      if (mounted) {
        Snack.error(context, e);
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _addPhoto() async {
    final source = await pickOne<PhotoSource>(
      context,
      title: 'Add a photo',
      options: const [
        PickerOption(value: PhotoSource.camera, title: 'Take a photo'),
        PickerOption(value: PhotoSource.gallery, title: 'Choose from gallery'),
      ],
    );
    final chosen = source?.value;
    if (chosen == null || !mounted) return;

    final PickedPhoto? photo;
    try {
      photo = await ref.read(photoPickerProvider).pick(chosen);
    } catch (_) {
      if (mounted) {
        Snack.show(
          context,
          'Could not open the ${chosen == PhotoSource.camera ? 'camera' : 'gallery'}. Check the app has permission.',
        );
      }
      return;
    }
    if (photo == null || !mounted) return;

    final mime = mimeTypeForAttachment(photo.name);
    if (mime == null) {
      Snack.show(
        context,
        'That file type is not supported. Use a JPG, PNG, WebP or PDF.',
      );
      return;
    }

    setState(() => _uploadProgress = 0);
    try {
      await _controller.uploadPhoto(
        path: photo.path,
        fileName: photo.name,
        contentType: mime,
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );
      if (mounted) Snack.show(context, 'Photo added.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _uploadProgress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(taskDetailProvider(widget.taskId));
    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 4, rowHeight: 100),
          ),
          error: (e, _) =>
              ErrorPanel(error: e, onRetry: () => _controller.reload()),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(TaskDetailState state) {
    final c = context.colors;
    final perms = ref.watch(permissionsProvider);
    final canComplete = perms.hasAny(Feature.tasksComplete);
    final canCollaborate = perms.hasAny(Feature.tasksCollaborate);
    // Needs the assign right and the project team to choose from; works only
    // online because the change goes straight to the server.
    final canAssign = perms.satisfies(Feature.assignTasks) && !state.fromCache;
    final pending = ref.watch(pendingStatusProvider);
    final task = withPendingStatus(state.task, pending);
    final waiting = pending.containsKey(task.id);
    final now = DateTime.now();

    return Column(
      children: [
        if (state.fromCache)
          const StatusBanner(
            message: 'Offline. Showing saved details. Status changes are saved and sent later; comments, checklist and photos need a connection.',
          ),
        Expanded(
          child: PageBody(
            onRefresh: () => _controller.reload(),
            children: [
              Text(
                task.title,
                style: AppType.pageTitle.copyWith(color: c.text),
              ),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.md,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge.status(task.status),
                  PriorityBadge(priority: task.priority),
                  if (task.dueDate != null)
                    Text(
                      Fmt.due(task.dueDate!, now: now),
                      style: AppType.label.copyWith(
                        color: task.isOverdue(now) ? c.danger : c.textMuted,
                      ),
                    ),
                ],
              ),
              if (waiting)
                Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: StatusBanner(
                    message: 'Status saved on your phone, waiting to be sent.',
                    icon: Icons.cloud_upload_outlined,
                    tone: StatusTone.warning,
                  ),
                ),
              const SizedBox(height: Space.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Fact(
                      Icons.apartment_rounded,
                      'Project',
                      task.project.label,
                    ),
                    _Fact(
                      Icons.group_outlined,
                      'Assigned to',
                      task.assigneeNames.isEmpty
                          ? 'Nobody yet'
                          : task.assigneeNames.join(', '),
                    ),
                    if (task.stageId != null &&
                        ref
                            .watch(permissionsProvider)
                            .hasAny(Feature.stagesView))
                      _StageFact(
                        projectId: task.project.id,
                        stageId: task.stageId!,
                      ),
                    if (task.estimatedHours != null)
                      _Fact(
                        Icons.schedule_rounded,
                        'Estimate',
                        Fmt.hours(task.estimatedHours!),
                      ),
                    if (task.startDate != null)
                      _Fact(
                        Icons.event_available_rounded,
                        'Starts',
                        Fmt.day(task.startDate!),
                      ),
                  ],
                ),
              ),
              if (canAssign) ...[
                const SizedBox(height: Space.sm),
                AppButton(
                  label: 'Change who is assigned',
                  icon: Icons.group_add_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showAssigneeSheet(
                    context,
                    taskId: task.id,
                    projectId: task.project.id,
                  ),
                ),
              ],
              if (task.description != null) ...[
                const SectionHeader('DESCRIPTION'),
                Text(
                  task.description!,
                  style: AppType.body.copyWith(color: c.text),
                ),
              ],
              if (perms.hasAny(Feature.tasksEdit) && !state.fromCache) ...[
                const SizedBox(height: Space.sm),
                AppButton(
                  label: 'Edit task',
                  icon: Icons.edit_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () =>
                      context.push('/tasks/${task.id}/edit', extra: task),
                ),
              ],
              if (canComplete) ...[
                const SectionHeader('UPDATE STATUS'),
                _statusButtons(task),
              ],
              if (task.checklists.isNotEmpty) ...[
                SectionHeader(
                  'CHECKLIST ${task.checklistDone}/${task.checklistTotal}',
                ),
                for (final list in task.checklists)
                  _ChecklistCard(
                    list: list,
                    enabled: canCollaborate && !state.fromCache,
                    onToggle: (itemId) => _toggle(list.id, itemId),
                  ),
              ],
              if (task.subtasks.isNotEmpty) ...[
                const SectionHeader('SUBTASKS'),
                AppCard(
                  child: Column(
                    children: [
                      for (final s in task.subtasks)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.xs,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.title,
                                  style: AppType.body.copyWith(color: c.text),
                                ),
                              ),
                              StatusBadge.status(s.status, dense: true),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              SectionHeader('PHOTOS AND FILES ${state.attachments.length}'),
              _attachments(state, canCollaborate && !state.fromCache),
              SectionHeader('COMMENTS ${task.comments.length}'),
              _comments(task, canCollaborate && !state.fromCache),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusButtons(TaskItem task) {
    final actions = _actionsFor(task.status);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: AppButton(
              label: a.label,
              icon: a.icon,
              variant: a.primary
                  ? AppButtonVariant.primary
                  : AppButtonVariant.secondary,
              loading: _changingStatus,
              onPressed: _changingStatus ? null : () => _setStatus(a.target),
            ),
          ),
      ],
    );
  }

  Widget _attachments(TaskDetailState state, bool canAdd) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.attachments.isEmpty)
          AppCard(
            child: Text(
              'No photos or files yet.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          )
        else
          AppCard(
            child: Column(
              children: [
                for (final a in state.attachments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Row(
                      children: [
                        Icon(
                          a.isImage
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          color: c.textMuted,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            a.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.body.copyWith(color: c.text),
                          ),
                        ),
                        Text(
                          Fmt.bytes(a.sizeBytes),
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (_uploadProgress != null) ...[
          const SizedBox(height: Space.md),
          LinearProgressIndicator(
            value: _uploadProgress == 0 ? null : _uploadProgress,
            color: c.primary,
            backgroundColor: c.surfaceMuted,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
        if (canAdd) ...[
          const SizedBox(height: Space.md),
          AppButton(
            label: 'Add photo',
            icon: Icons.add_a_photo_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: _uploadProgress != null ? null : _addPhoto,
          ),
        ],
      ],
    );
  }

  Widget _comments(TaskItem task, bool canAdd) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (task.comments.isEmpty)
          AppCard(
            child: Text(
              'No comments yet.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          )
        else
          for (final cm in task.comments)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cm.authorName,
                            style: AppType.label.copyWith(color: c.text),
                          ),
                        ),
                        Text(
                          Fmt.ago(cm.createdAt),
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      cm.content,
                      style: AppType.body.copyWith(color: c.text),
                    ),
                  ],
                ),
              ),
            ),
        if (canAdd) ...[
          const SizedBox(height: Space.sm),
          AppTextField(
            label: 'Add a comment',
            controller: _comment,
            hint: 'What is happening on site?',
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_sendingComment,
          ),
          const SizedBox(height: Space.md),
          AppButton(
            label: 'Post comment',
            icon: Icons.send_rounded,
            loading: _sendingComment,
            onPressed: _sendComment,
          ),
        ],
      ],
    );
  }
}

/// The timeline stage a task is linked to, by name. Shows nothing until the
/// project's stages have loaded (or when they cannot be read).
class _StageFact extends ConsumerWidget {
  const _StageFact({required this.projectId, required this.stageId});
  final String projectId;
  final String stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(projectStagesProvider(projectId))
        .maybeWhen(
          data: (list) {
            for (final s in list) {
              if (s.id == stageId) {
                return _Fact(
                  Icons.timeline_rounded,
                  'Stage',
                  '${s.name} · ${workflowLabel(s.workflowCode)}',
                );
              }
            }
            return const SizedBox.shrink();
          },
          orElse: () => const SizedBox.shrink(),
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
            width: 92,
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

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.list,
    required this.enabled,
    required this.onToggle,
  });

  final Checklist list;
  final bool enabled;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.xs,
              ),
              child: Text(
                list.title,
                style: AppType.bodyStrong.copyWith(color: c.text),
              ),
            ),
            for (final item in list.items)
              Semantics(
                container: true,
                checked: item.isDone,
                enabled: enabled,
                label: item.content,
                child: InkWell(
                  onTap: enabled ? () => onToggle(item.id) : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: Sizes.touchTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              item.isDone
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: item.isDone
                                  ? c.success
                                  : (enabled ? c.borderStrong : c.border),
                            ),
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Text(
                              item.content,
                              style: AppType.body.copyWith(
                                color: item.isDone ? c.textMuted : c.text,
                                decoration: item.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

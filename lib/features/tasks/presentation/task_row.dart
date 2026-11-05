import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/status_badge.dart';
import '../data/task_models.dart';

/// One task in a list. [pendingSync] marks a status that is saved on the phone
/// but not sent yet.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.pendingSync = false,
  });

  final TaskItem task;
  final VoidCallback onTap;
  final bool pendingSync;

  /// Title with the status badge beside it; below it when text is enlarged, so
  /// neither gets squeezed out at accessibility text sizes.
  Widget _titleLine(BuildContext context, AppColors c) {
    final title = Text(
      task.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: AppType.bodyStrong.copyWith(color: c.text),
    );
    final badge = StatusBadge.status(task.status);
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: Space.xs),
          badge,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        const SizedBox(width: Space.sm),
        badge,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final overdue = task.isOverdue(now);
    final dueText = task.dueDate == null
        ? null
        : Fmt.due(task.dueDate!, now: now);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Space.lg),
      semanticLabel:
          '${task.title}, ${statusInfo(task.status).label}, ${task.project.name}${dueText == null ? '' : ', $dueText'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleLine(context, c),
          const SizedBox(height: Space.xs),
          Text(
            task.project.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PriorityBadge(priority: task.priority),
              if (dueText != null)
                _Meta(
                  icon: Icons.event_rounded,
                  text: dueText,
                  color: overdue ? c.danger : c.textMuted,
                  bold: overdue,
                ),
              if (task.checklistTotal > 0)
                _Meta(
                  icon: Icons.checklist_rounded,
                  text: '${task.checklistDone}/${task.checklistTotal}',
                  color: c.textMuted,
                ),
              if (task.commentCount > 0)
                _Meta(
                  icon: Icons.chat_bubble_outline_rounded,
                  text: '${task.commentCount}',
                  color: c.textMuted,
                ),
              if (pendingSync)
                _Meta(
                  icon: Icons.cloud_upload_outlined,
                  text: 'Waiting to send',
                  color: c.warning,
                  bold: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.text,
    required this.color,
    this.bold = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: Space.xs),
        // Flexible so very large text wraps instead of overflowing the card.
        Flexible(
          child: Text(
            text,
            style: AppType.helper.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

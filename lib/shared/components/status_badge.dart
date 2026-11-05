import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';

/// Label + tone for a backend status string. Mirrors the web app's
/// `components/shared/status-badge.tsx` so a status looks the same everywhere.
class StatusInfo {
  const StatusInfo(this.label, this.tone);
  final String label;
  final StatusTone tone;
}

StatusInfo statusInfo(String? raw) {
  final key = (raw ?? '').toUpperCase().trim();
  const map = <String, StatusInfo>{
    'TODO': StatusInfo('To Do', StatusTone.neutral),
    'IN_PROGRESS': StatusInfo('In Progress', StatusTone.info),
    'BLOCKED': StatusInfo('Blocked', StatusTone.danger),
    'REVIEW': StatusInfo('Review', StatusTone.review),
    'DONE': StatusInfo('Done', StatusTone.success),
    'PENDING': StatusInfo('Pending', StatusTone.warning),
    'APPROVED': StatusInfo('Approved', StatusTone.success),
    'REJECTED': StatusInfo('Rejected', StatusTone.danger),
    'ACTIVE': StatusInfo('Active', StatusTone.success),
    'ON_HOLD': StatusInfo('On Hold', StatusTone.warning),
    'COMPLETED': StatusInfo('Completed', StatusTone.info),
    'DRAFT': StatusInfo('Draft', StatusTone.neutral),
    'ARCHIVED': StatusInfo('Archived', StatusTone.muted),
    'SENT': StatusInfo('Sent', StatusTone.info),
    'PAID': StatusInfo('Paid', StatusTone.success),
    'PARTIALLY_PAID': StatusInfo('Partial', StatusTone.warning),
    'OVERDUE': StatusInfo('Overdue', StatusTone.danger),
    'VOID': StatusInfo('Void', StatusTone.muted),
    'CANCELED': StatusInfo('Canceled', StatusTone.muted),
    'CANCELLED': StatusInfo('Cancelled', StatusTone.muted),
    'SUBMITTED': StatusInfo('Submitted', StatusTone.sky),
    'EXPIRED': StatusInfo('Expired', StatusTone.muted),
    'ORDERED': StatusInfo('Ordered', StatusTone.accent),
    'PARTIAL': StatusInfo('Part received', StatusTone.warning),
    'RECEIVED': StatusInfo('Received', StatusTone.success),
    'SKIPPED': StatusInfo('Skipped', StatusTone.muted),
    'ON_TRACK': StatusInfo('On track', StatusTone.success),
    'WARNING': StatusInfo('Near limit', StatusTone.warning),
    'OVER_BUDGET': StatusInfo('Over budget', StatusTone.danger),
    'AVAILABLE': StatusInfo('Available', StatusTone.success),
    'IN_USE': StatusInfo('In use', StatusTone.info),
    'MAINTENANCE': StatusInfo('Maintenance', StatusTone.warning),
    'RETIRED': StatusInfo('Retired', StatusTone.muted),
    'CONVERTED': StatusInfo('Converted', StatusTone.accent),
    'UNDER_REVIEW': StatusInfo('Under Review', StatusTone.review),
    'IMPLEMENTED': StatusInfo('Implemented', StatusTone.success),
    'LOW': StatusInfo('Low', StatusTone.neutral),
    'MEDIUM': StatusInfo('Medium', StatusTone.info),
    'HIGH': StatusInfo('High', StatusTone.warning),
    'CRITICAL': StatusInfo('Critical', StatusTone.danger),
  };
  final hit = map[key];
  if (hit != null) return hit;
  if (key.isEmpty) return const StatusInfo('Unknown', StatusTone.muted);
  final words = key
      .toLowerCase()
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');
  return StatusInfo(words.join(' '), StatusTone.neutral);
}

/// Compact status pill. Colour is never the only signal: the text label is always shown.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.dense = false,
  });

  StatusBadge.status(String? status, {super.key, this.dense = false})
    : label = statusInfo(status).label,
      tone = statusInfo(status).tone;

  final String label;
  final StatusTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.colors.tone(tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Space.sm : Space.md - 2,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(Corners.sm),
      ),
      child: Text(
        label,
        style: AppType.badge.copyWith(color: t.foreground),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Priority indicator: a leading flag icon plus label, so it reads without colour.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});
  final String? priority;

  @override
  Widget build(BuildContext context) {
    final info = statusInfo(priority);
    final t = context.colors.tone(info.tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flag_rounded, size: 14, color: t.foreground),
        const SizedBox(width: Space.xs),
        Text(info.label, style: AppType.badge.copyWith(color: t.foreground)),
      ],
    );
  }
}

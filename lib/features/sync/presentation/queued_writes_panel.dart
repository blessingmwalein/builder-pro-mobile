import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/offline/write_queue.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../application/sync_providers.dart';
import '../data/queued_write_models.dart';

/// What was saved on this phone and has not reached the server yet: waiting for
/// a connection, waiting to be checked after no answer came back, or refused by
/// the server and waiting for the person. Shows nothing when there is none.
class QueuedWritesPanel extends ConsumerWidget {
  const QueuedWritesPanel({super.key, required this.kinds});

  /// Which kinds to list (the clock lists its own, materials its own).
  final List<String> kinds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = (ref.watch(queuedWritesProvider).value ?? const [])
        .where((w) => kinds.contains(w.kind))
        .toList();
    if (saved.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('SAVED ON THIS PHONE ${saved.length}'),
        for (final w in saved)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: _SavedRow(write: w),
          ),
      ],
    );
  }
}

/// `Mon 26 Oct · 8:02 AM`, in the phone's own time.
String _when(DateTime at) =>
    '${Fmt.day(at.toLocal())} · ${Fmt.time(at.toLocal())}';

class _SavedRow extends ConsumerWidget {
  const _SavedRow({required this.write});
  final QueuedWrite write;

  ({String title, String when}) _describe() {
    switch (write.kind) {
      case WriteKind.clockIn:
        final p = write.asClockIn;
        return (
          title:
              'Clock in${p?.projectName == null ? '' : ' · ${p!.projectName}'}',
          when: p == null ? '' : _when(p.occurredAt),
        );
      case WriteKind.clockOut:
        final p = write.asClockOut;
        return (
          title: 'Clock out',
          when: p == null
              ? ''
              : '${_when(p.occurredAt)}${p.breakMinutes > 0 ? ' · ${p.breakMinutes} min break' : ''}',
        );
      case WriteKind.materialUsage:
        final p = write.asUsage;
        return (
          title: p == null
              ? 'Material used'
              : '${Fmt.quantity(p.quantity)} ${p.unit} of ${p.materialName}',
          when: p == null ? '' : '${p.projectName} · ${_when(p.occurredAt)}',
        );
    }
    return (title: 'Saved entry', when: '');
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Discard this?',
      message: write.kind == WriteKind.clockIn
          ? 'It will not be recorded, and the clock-out saved after it is discarded too.'
          : 'It will not be recorded.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(writeQueueProvider)?.discard(write.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final d = _describe();
    final status = write.status;
    final needsYou = status == WriteStatus.attention;
    final (icon, tint, line) = switch (status) {
      WriteStatus.attention => (
        Icons.error_outline_rounded,
        c.danger,
        'Not recorded: ${write.lastError ?? 'the server refused it.'}',
      ),
      WriteStatus.unconfirmed => (
        Icons.sync_rounded,
        c.warning,
        'No answer yet. It will be checked before it is sent again.',
      ),
      _ => (
        Icons.cloud_upload_outlined,
        c.textMuted,
        'Waiting for a connection.',
      ),
    };
    return AppCard(
      semanticLabel: '${d.title}, ${d.when}. $line',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    if (d.when.isNotEmpty)
                      Text(
                        d.when,
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                    const SizedBox(height: Space.xs),
                    Text(
                      line,
                      style: AppType.bodySmall.copyWith(
                        color: needsYou ? c.danger : c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status != WriteStatus.unconfirmed)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: Space.sm,
                children: [
                  if (needsYou)
                    TextButton(
                      onPressed: () async {
                        await ref.read(writeQueueProvider)?.retry(write.id);
                        if (context.mounted) {
                          Snack.show(context, 'Trying again.');
                        }
                      },
                      child: const Text('Try again'),
                    ),
                  TextButton(
                    onPressed: () => _discard(context, ref),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/providers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../../shared/services/voice_services.dart';
import '../data/messaging_models.dart';
import 'image_viewer_screen.dart';

/// A person's initials in a circle (a group gets a people icon). The colour comes
/// from the name, so the same person always looks the same.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 44,
    this.group = false,
  });

  final String name;
  final String? url;
  final double size;
  final bool group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = group ? c.primary : c.seriesAt(name.hashCode.abs());
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: group
          ? Icon(Icons.groups_rounded, size: size * 0.52, color: tint)
          : Text(
              chatInitials(name),
              style: AppType.bodyStrong.copyWith(
                color: tint,
                fontSize: size * 0.36,
              ),
            ),
    );
    final address = url;
    if (address == null) return fallback;
    return ClipOval(
      child: Image.network(
        address,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// Text in which the names of tagged people (`@Mary Moyo`) stand out.
class MentionText extends StatelessWidget {
  const MentionText(
    this.text, {
    super.key,
    required this.names,
    required this.style,
    required this.mentionStyle,
  });

  final String text;

  /// The people who can be tagged here.
  final List<String> names;
  final TextStyle style;
  final TextStyle mentionStyle;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty || !text.contains('@')) return Text(text, style: style);
    final ordered = [...names]..sort((a, b) => b.length.compareTo(a.length));
    final pattern = RegExp(
      '@(${ordered.map(RegExp.escape).join('|')})',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(0), style: mentionStyle));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// The message a reply answers, shown as a quote with an accent bar.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.reply,
    required this.textColor,
    required this.accent,
    this.background,
  });

  final ReplyPreview reply;
  final Color textColor;
  final Color accent;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final snippet = reply.snippet;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.xs + 2),
      decoration: BoxDecoration(
        color: background ?? accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Corners.sm),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(Corners.sm),
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.xs + 1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reply.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.helper.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      snippet.isEmpty ? 'Message' : snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.helper.copyWith(color: textColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String voiceTime(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A voice message: play or pause, a bar to move along it, and the time. Only one
/// plays at a time.
class VoiceBubble extends ConsumerWidget {
  const VoiceBubble({
    super.key,
    required this.playbackKey,
    required this.foreground,
    this.url,
    this.path,
    this.durationMs,
  });

  final String playbackKey;
  final Color foreground;
  final String? url;
  final String? path;
  final int? durationMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(voicePlayerProvider);
    final mine = pb.key == playbackKey;
    final known = durationMs == null
        ? null
        : Duration(milliseconds: durationMs!);
    final total = mine && pb.duration != null ? pb.duration! : known;
    final position = mine ? pb.position : Duration.zero;
    final max = (total?.inMilliseconds ?? 0).toDouble();
    final value = max <= 0
        ? 0.0
        : position.inMilliseconds.toDouble().clamp(0.0, max);
    final controller = ref.read(voicePlayerProvider.notifier);
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: mine && pb.loading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: foreground,
                    ),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: mine && pb.playing
                        ? 'Pause voice message'
                        : 'Play voice message',
                    onPressed: () =>
                        controller.toggle(playbackKey, url: url, path: path),
                    icon: Icon(
                      mine && pb.playing
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 34,
                      color: foreground,
                    ),
                  ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: foreground,
                inactiveTrackColor: foreground.withValues(alpha: 0.3),
                thumbColor: foreground,
              ),
              child: Slider(
                value: value,
                max: max <= 0 ? 1 : max,
                onChanged: mine && max > 0
                    ? (v) => controller.seek(Duration(milliseconds: v.round()))
                    : null,
              ),
            ),
          ),
          Text(
            voiceTime(mine && pb.playing ? position : (total ?? Duration.zero)),
            style: AppType.helper.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

IconData _fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => Icons.picture_as_pdf_rounded,
    'doc' || 'docx' || 'txt' => Icons.description_rounded,
    'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

/// A document: its icon, name and size. Opens it outside the app.
class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.name,
    required this.size,
    required this.foreground,
    this.onTap,
  });

  final String name;
  final String size;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$name, $size${onTap == null ? '' : ', tap to open'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, maxWidth: 240),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_fileIcon(name), size: 30, color: foreground),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodySmall.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (size.isNotEmpty)
                      Text(
                        size,
                        style: AppType.helper.copyWith(
                          color: foreground.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo in a message, with a placeholder while it loads and a plain tile when
/// it cannot be loaded.
class ChatImage extends StatelessWidget {
  const ChatImage({
    super.key,
    required this.url,
    required this.path,
    required this.onTap,
    required this.label,
  });

  final String? url;
  final String? path;
  final VoidCallback onTap;
  final String label;

  static const width = 220.0;
  static const height = 170.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget broken() => Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: c.surfaceMuted,
      child: Icon(Icons.broken_image_outlined, color: c.textMuted, size: 36),
    );
    final Widget image;
    if (path != null) {
      image = Image.file(
        File(path!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => broken(),
      );
    } else if (url != null) {
      image = Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => broken(),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: width,
                height: height,
                alignment: Alignment.center,
                color: c.surfaceMuted,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
      );
    } else {
      image = broken();
    }
    return Semantics(
      button: true,
      image: true,
      label: '$label, tap to view',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Corners.md),
          child: image,
        ),
      ),
    );
  }
}

/// The files of one message: photos (tap to view full screen), voice messages and
/// documents. Files still on the phone show from the phone while they upload.
class MessageAttachments extends ConsumerWidget {
  const MessageAttachments({
    super.key,
    required this.message,
    required this.foreground,
  });

  final ChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(appConfigProvider).socketOrigin;
    final images = <ViewerImage>[
      for (final a in message.attachments)
        if (a.isImage)
          ViewerImage(url: a.addressFor(origin), title: a.fileName),
      for (final p in message.pending)
        if (p.isImage) ViewerImage(path: p.path, title: p.name),
    ];

    Future<void> open(String? address) async {
      if (address == null) {
        Snack.show(context, 'This file has no address on the server.');
        return;
      }
      final ok = await ref.read(contactLauncherProvider).openLink(address);
      if (!ok && context.mounted) {
        Snack.show(context, 'Could not open the file. Try again later.');
      }
    }

    final widgets = <Widget>[];
    var imageIndex = 0;
    for (final a in message.attachments) {
      if (a.isImage) {
        final i = imageIndex++;
        widgets.add(
          ChatImage(
            url: a.addressFor(origin),
            path: null,
            label: a.fileName,
            onTap: () => context.push(
              '/messages/image',
              extra: ImageViewerArgs(images: images, index: i),
            ),
          ),
        );
      } else if (a.isAudio) {
        widgets.add(
          VoiceBubble(
            playbackKey: a.id,
            url: a.addressFor(origin),
            durationMs: a.durationMs,
            foreground: foreground,
          ),
        );
      } else {
        widgets.add(
          FileTile(
            name: a.fileName,
            size: a.sizeLabel,
            foreground: foreground,
            onTap: () => open(a.addressFor(origin)),
          ),
        );
      }
    }
    for (final p in message.pending) {
      if (p.isImage) {
        final i = imageIndex++;
        widgets.add(
          ChatImage(
            url: null,
            path: p.path,
            label: p.name,
            onTap: () => context.push(
              '/messages/image',
              extra: ImageViewerArgs(images: images, index: i),
            ),
          ),
        );
      } else if (p.isAudio) {
        widgets.add(
          VoiceBubble(
            playbackKey: p.path,
            path: p.path,
            durationMs: p.durationMs,
            foreground: foreground,
          ),
        );
      } else {
        widgets.add(FileTile(name: p.name, size: '', foreground: foreground));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    final progress = message.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widgets.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.xs + 2),
          widgets[i],
        ],
        if (message.state == SendState.sending &&
            message.pending.isNotEmpty &&
            progress != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs + 2),
            child: SizedBox(
              width: ChatImage.width,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress <= 0 ? null : progress,
                  minHeight: 4,
                  color: foreground,
                  backgroundColor: foreground.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

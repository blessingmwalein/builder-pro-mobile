import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/services/document_picker.dart';
import '../../../shared/services/photo_picker.dart';
import '../../../shared/services/voice_services.dart';
import '../data/messaging_models.dart';
import 'chat_widgets.dart';

enum _AttachSource { camera, gallery, file }

/// The longest voice message the composer records before sending it.
const maxVoiceSeconds = 300;

/// The tagged people in [text]: everyone whose `@Name` appears in it.
List<String> mentionedIn(String text, List<ChatPerson> people) {
  final lower = text.toLowerCase();
  return [
    for (final p in people)
      if (lower.contains('@${p.name.toLowerCase()}')) p.id,
  ];
}

/// The message box of a chat: text, photos and files from the camera, gallery or
/// phone, voice messages, a reply bar, and (in a group) suggestions when you type
/// @ and a name.
class ThreadComposer extends ConsumerStatefulWidget {
  const ThreadComposer({
    super.key,
    required this.isGroup,
    required this.people,
    required this.caps,
    required this.reply,
    required this.onClearReply,
    required this.onSend,
  });

  final bool isGroup;

  /// Who can be tagged.
  final List<ChatPerson> people;
  final ChatCapabilities caps;
  final ReplyPreview? reply;
  final VoidCallback onClearReply;
  final void Function(
    String text,
    List<PendingFile> files,
    List<String> mentionIds,
  )
  onSend;

  @override
  ConsumerState<ThreadComposer> createState() => _ThreadComposerState();
}

class _ThreadComposerState extends ConsumerState<ThreadComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _files = <PendingFile>[];
  bool _recording = false;
  bool _picking = false;
  DateTime? _recordingSince;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _ticker;
  String? _mentionQuery;
  int _mentionStart = -1;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _text.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    if (_recording) {
      // Leaving mid-recording throws it away: nothing is sent unasked.
      ref.read(voiceRecorderProvider).cancel();
    }
    super.dispose();
  }

  void _changed() {
    _updateMention();
    setState(() {});
  }

  void _updateMention() {
    String? query;
    var start = -1;
    final sel = _text.selection;
    if (widget.isGroup && sel.isValid && sel.isCollapsed) {
      final before = _text.text.substring(0, sel.baseOffset);
      final at = before.lastIndexOf('@');
      if (at >= 0 && (at == 0 || RegExp(r'\s').hasMatch(before[at - 1]))) {
        final q = before.substring(at + 1);
        if (!q.contains('\n') && q.length <= 30) {
          query = q;
          start = at;
        }
      }
    }
    _mentionQuery = query;
    _mentionStart = start;
  }

  List<ChatPerson> get _suggestions {
    final q = _mentionQuery;
    if (q == null) return const [];
    final lower = q.toLowerCase();
    return widget.people
        .where((p) => p.name.toLowerCase().contains(lower))
        .take(5)
        .toList();
  }

  void _insertMention(ChatPerson p) {
    final cursor = _text.selection.baseOffset;
    final text = _text.text;
    final next =
        '${text.substring(0, _mentionStart)}@${p.name} ${text.substring(cursor)}';
    final offset = _mentionStart + p.name.length + 2;
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset),
    );
    _focus.requestFocus();
  }

  bool get _hasContent => _text.text.trim().isNotEmpty || _files.isNotEmpty;

  void _send() {
    if (!_hasContent) return;
    final text = _text.text.trim();
    final files = List<PendingFile>.of(_files);
    final mentions = mentionedIn(text, widget.people);
    // Cleared at once: the message is in the list (and can be retried there), so
    // nothing typed is lost if the send fails.
    _text.clear();
    setState(_files.clear);
    widget.onSend(text, files, mentions);
  }

  // ---- files ----

  Future<void> _attach() async {
    if (_picking) return;
    if (!widget.caps.attachments) {
      Snack.show(
        context,
        'Photos and files need the latest server update. Text messages still work.',
      );
      return;
    }
    if (_files.length >= maxChatFiles) {
      Snack.show(context, 'One message can carry up to $maxChatFiles files.');
      return;
    }
    final source = await pickOne<_AttachSource>(
      context,
      title: 'Add to your message',
      options: const [
        PickerOption(value: _AttachSource.camera, title: 'Take a photo'),
        PickerOption(
          value: _AttachSource.gallery,
          title: 'Choose a photo from the gallery',
        ),
        PickerOption(
          value: _AttachSource.file,
          title: 'Choose a document (PDF, Word, Excel, text)',
        ),
      ],
    );
    final chosen = source?.value;
    if (chosen == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final String path;
      final String name;
      int? size;
      if (chosen == _AttachSource.file) {
        final doc = await ref
            .read(documentPickerProvider)
            .pick(extensions: chatFileMimeTypes.keys.toList());
        if (doc == null) return;
        path = doc.path;
        name = doc.name;
        size = doc.sizeBytes;
      } else {
        final photo = await ref
            .read(photoPickerProvider)
            .pick(
              chosen == _AttachSource.camera
                  ? PhotoSource.camera
                  : PhotoSource.gallery,
            );
        if (photo == null) return;
        path = photo.path;
        name = photo.name;
      }
      final type = chatMimeFor(name);
      if (!mounted) return;
      if (type == null) {
        Snack.show(
          context,
          'That kind of file is not accepted. Choose a JPEG, PNG, WebP or GIF picture, or a PDF, Word, Excel or text file.',
        );
        return;
      }
      size ??= File(path).lengthSync();
      if (size > maxChatFileBytes) {
        Snack.show(
          context,
          'That file is ${Fmt.bytes(size)}. The limit is ${Fmt.bytes(maxChatFileBytes)}.',
        );
        return;
      }
      setState(
        () => _files.add(
          PendingFile(
            path: path,
            name: name,
            contentType: type,
            sizeBytes: size!,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        Snack.show(
          context,
          'That could not be opened. Check that the app may use the camera, photos or files.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // ---- voice ----

  Future<void> _startRecording() async {
    if (_recording) return;
    if (!widget.caps.voice) {
      Snack.show(
        context,
        'Voice messages need the latest server update. Text messages still work.',
      );
      return;
    }
    final recorder = ref.read(voiceRecorderProvider);
    final result = await recorder.start();
    if (!mounted) return;
    switch (result) {
      case VoiceStart.denied:
        Snack.show(
          context,
          'Allow the microphone for this app in your phone\'s settings to record voice messages.',
        );
        return;
      case VoiceStart.failed:
        Snack.show(
          context,
          'The microphone could not start. Another app may be using it.',
        );
        return;
      case VoiceStart.started:
        break;
    }
    _focus.unfocus();
    setState(() {
      _recording = true;
      _recordingSince = DateTime.now();
      _elapsed = Duration.zero;
      _level = 0;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      final since = _recordingSince;
      if (since == null || !mounted) return;
      final level = await recorder.level();
      if (!mounted || !_recording) return;
      final elapsed = DateTime.now().difference(since);
      setState(() {
        _elapsed = elapsed;
        _level = level;
      });
      if (elapsed.inSeconds >= maxVoiceSeconds) {
        unawaited(_finishRecording(send: true));
      }
    });
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;
    _ticker?.cancel();
    final recorder = ref.read(voiceRecorderProvider);
    setState(() => _recording = false);
    if (!send) {
      await recorder.cancel();
      return;
    }
    final voice = await recorder.stop();
    if (!mounted) return;
    if (voice == null || voice.duration < const Duration(seconds: 1)) {
      Snack.show(context, 'That was too short. Hold on a little longer.');
      return;
    }
    widget.onSend('', [
      PendingFile(
        path: voice.path,
        name: voice.name,
        contentType: RecordedVoice.contentType,
        sizeBytes: voice.sizeBytes,
        durationMs: voice.duration.inMilliseconds,
      ),
    ], const []);
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final suggestions = _suggestions;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (suggestions.isNotEmpty)
          _Suggestions(people: suggestions, onPick: _insertMention),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border)),
          ),
          padding: const EdgeInsets.fromLTRB(
            Space.sm,
            Space.sm,
            Space.sm,
            Space.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.reply != null)
                _ReplyBar(reply: widget.reply!, onClear: widget.onClearReply),
              if (_files.isNotEmpty && !_recording)
                _FilesStrip(
                  files: _files,
                  onRemove: (f) => setState(() => _files.remove(f)),
                ),
              _recording ? _recordingRow(c) : _inputRow(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _inputRow(AppColors c) {
    final has = _hasContent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Add a photo or file',
          constraints: const BoxConstraints(
            minWidth: Sizes.touchTarget,
            minHeight: Sizes.touchTarget,
          ),
          onPressed: _picking ? null : _attach,
          icon: Icon(Icons.add_circle_outline_rounded, color: c.primary),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(Corners.xl),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: TextField(
              controller: _text,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              style: AppType.body.copyWith(color: c.text),
              decoration: InputDecoration(
                hintText: widget.isGroup
                    ? 'Message, or @ to tag someone'
                    : 'Message',
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.xs),
        if (has)
          Semantics(
            button: true,
            label: 'Send message',
            excludeSemantics: true,
            child: IconButton.filled(
              constraints: const BoxConstraints(
                minWidth: Sizes.touchTarget,
                minHeight: Sizes.touchTarget,
              ),
              onPressed: _send,
              icon: const Icon(Icons.send_rounded),
            ),
          )
        else
          Semantics(
            button: true,
            label: 'Record a voice message',
            excludeSemantics: true,
            child: IconButton.filled(
              constraints: const BoxConstraints(
                minWidth: Sizes.touchTarget,
                minHeight: Sizes.touchTarget,
              ),
              onPressed: _startRecording,
              icon: const Icon(Icons.mic_rounded),
            ),
          ),
      ],
    );
  }

  Widget _recordingRow(AppColors c) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Throw this recording away',
          constraints: const BoxConstraints(
            minWidth: Sizes.touchTarget,
            minHeight: Sizes.touchTarget,
          ),
          onPressed: () => _finishRecording(send: false),
          icon: Icon(Icons.delete_outline_rounded, color: c.danger),
        ),
        Icon(Icons.fiber_manual_record_rounded, color: c.danger, size: 14),
        const SizedBox(width: Space.sm),
        Text(
          voiceTime(_elapsed),
          style: AppType.bodyStrong.copyWith(color: c.text),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _level,
              minHeight: 6,
              color: c.primary,
              backgroundColor: c.surfaceMuted,
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Semantics(
          button: true,
          label: 'Send voice message',
          excludeSemantics: true,
          child: IconButton.filled(
            constraints: const BoxConstraints(
              minWidth: Sizes.touchTarget,
              minHeight: Sizes.touchTarget,
            ),
            onPressed: () => _finishRecording(send: true),
            icon: const Icon(Icons.send_rounded),
          ),
        ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.people, required this.onPick});
  final List<ChatPerson> people;
  final ValueChanged<ChatPerson> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in people)
            InkWell(
              onTap: () => onPick(p),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.gutter,
                    vertical: Space.xs,
                  ),
                  child: Row(
                    children: [
                      ChatAvatar(name: p.name, url: p.avatarUrl, size: 32),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body.copyWith(color: c.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.reply, required this.onClear});
  final ReplyPreview reply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: ReplyQuote(
              reply: reply,
              textColor: c.textMuted,
              accent: c.primary,
            ),
          ),
          IconButton(
            tooltip: 'Cancel the reply',
            onPressed: onClear,
            icon: Icon(Icons.close_rounded, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FilesStrip extends StatelessWidget {
  const _FilesStrip({required this.files, required this.onRemove});
  final List<PendingFile> files;
  final ValueChanged<PendingFile> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: files.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
          itemBuilder: (context, i) {
            final f = files[i];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Corners.md),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: c.surfaceMuted,
                    child: f.isImage
                        ? Image.file(
                            File(f.path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: c.textMuted,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(Space.xs),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.insert_drive_file_rounded,
                                  color: c.primary,
                                ),
                                Text(
                                  f.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: AppType.helper.copyWith(
                                    color: c.text,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: Semantics(
                    button: true,
                    label: 'Remove ${f.name}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => onRemove(f),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: c.text,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: c.surface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

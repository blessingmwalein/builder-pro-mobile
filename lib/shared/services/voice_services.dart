import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A voice message that has been recorded and is waiting to be sent.
class RecordedVoice {
  const RecordedVoice({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.duration,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final Duration duration;

  /// The format the recorder writes (AAC in an MPEG-4 file, `.m4a`).
  static const contentType = 'audio/mp4';
}

enum VoiceStart {
  started,

  /// The person did not allow the microphone.
  denied,

  /// The recorder could not start (no microphone, in use by a call…).
  failed,
}

/// The microphone behind a small interface so screens can be tested without the
/// platform plugin.
abstract class VoiceRecorder {
  bool get isRecording;

  Future<VoiceStart> start();

  /// Ends the recording and returns it, or null when nothing usable was made.
  Future<RecordedVoice?> stop();

  /// Ends the recording and throws it away.
  Future<void> cancel();

  /// How loud it is now, from 0 (silence) to 1, for the meter.
  Future<double> level();

  Future<void> dispose();
}

class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  bool _recording = false;
  DateTime? _startedAt;
  String? _path;

  @override
  bool get isRecording => _recording;

  @override
  Future<VoiceStart> start() async {
    if (_recording) return VoiceStart.started;
    try {
      if (!await _recorder.hasPermission()) return VoiceStart.denied;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _path = path;
      _startedAt = DateTime.now();
      _recording = true;
      return VoiceStart.started;
    } catch (_) {
      return VoiceStart.failed;
    }
  }

  @override
  Future<RecordedVoice?> stop() async {
    if (!_recording) return null;
    _recording = false;
    final started = _startedAt;
    try {
      final path = await _recorder.stop() ?? _path;
      if (path == null || started == null) return null;
      final file = File(path);
      if (!file.existsSync()) return null;
      final size = file.lengthSync();
      if (size <= 0) return null;
      return RecordedVoice(
        path: path,
        name: 'Voice message ${_stamp(started)}.m4a',
        sizeBytes: size,
        duration: DateTime.now().difference(started),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    final wasRecording = _recording;
    _recording = false;
    try {
      if (wasRecording) await _recorder.cancel();
      final p = _path;
      if (p != null) {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      }
    } catch (_) {}
  }

  @override
  Future<double> level() async {
    try {
      final amp = await _recorder.getAmplitude();
      // Decibels run from about -60 (silence) to 0 (as loud as it gets).
      return ((amp.current + 60) / 60).clamp(0.0, 1.0);
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }
}

/// One recorder per open chat; its microphone is released when the chat closes.
final voiceRecorderProvider = Provider.autoDispose<VoiceRecorder>((ref) {
  final recorder = RecordVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

// ---- playing voice messages --------------------------------------------------

/// What the one shared voice player is doing: which message it holds and how far
/// along it is.
class VoicePlayback {
  const VoicePlayback({
    this.key,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
    this.failed = false,
  });

  /// The message being played (or paused), null when nothing is.
  final String? key;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration? duration;
  final bool failed;

  VoicePlayback copyWith({
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    bool? failed,
  }) => VoicePlayback(
    key: key,
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    failed: failed ?? this.failed,
  );
}

/// Plays one voice message at a time: starting another stops the first. Created
/// when a chat opens and released when it closes.
class VoicePlayerController extends Notifier<VoicePlayback> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  VoicePlayback build() {
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _player?.dispose();
    });
    return const VoicePlayback();
  }

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _subs
      ..add(
        p.onPlayerStateChanged.listen((s) {
          if (!ref.mounted) return;
          state = state.copyWith(
            playing: s == PlayerState.playing,
            loading: false,
          );
        }),
      )
      ..add(
        p.onPositionChanged.listen((d) {
          if (ref.mounted) state = state.copyWith(position: d);
        }),
      )
      ..add(
        p.onDurationChanged.listen((d) {
          if (ref.mounted) state = state.copyWith(duration: d);
        }),
      )
      ..add(
        p.onPlayerComplete.listen((_) {
          if (ref.mounted) {
            state = state.copyWith(playing: false, position: Duration.zero);
          }
        }),
      );
    _player = p;
    return p;
  }

  /// Plays [key]'s message from [url] (a message already sent) or [path] (one
  /// still on this phone); pauses or resumes it when it is already the one held.
  Future<void> toggle(String key, {String? url, String? path}) async {
    final player = _ensure();
    try {
      if (state.key == key) {
        if (state.playing) {
          await player.pause();
        } else {
          await player.resume();
        }
        return;
      }
      await player.stop();
      state = VoicePlayback(key: key, loading: true);
      if (path != null) {
        await player.play(DeviceFileSource(path));
      } else if (url != null) {
        await player.play(UrlSource(url));
      } else {
        state = VoicePlayback(key: key, failed: true);
      }
    } catch (_) {
      if (ref.mounted) state = VoicePlayback(key: key, failed: true);
    }
  }

  Future<void> seek(Duration to) async {
    try {
      await _player?.seek(to);
    } catch (_) {}
  }
}

final voicePlayerProvider =
    NotifierProvider.autoDispose<VoicePlayerController, VoicePlayback>(
      VoicePlayerController.new,
    );

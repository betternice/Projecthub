import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    this.url,
    this.filePath,
    this.libraryRef,
    this.startAtMs = 0,
  }) : assert(url != null || filePath != null);

  final String title;
  final String? url;
  final String? filePath;
  final LibraryRef? libraryRef;
  final int startAtMs;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late VideoController _video;
  final _subs = <StreamSubscription<dynamic>>[];

  var _ready = false;
  var _failed = false;
  String? _failMessage;
  var _showChrome = true;
  var _showSettings = false;
  var _showOptions = false;
  var _playing = false;
  var _buffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _openWatchdog;

  BoxFit _fit = BoxFit.contain;
  double _speed = 1.0;
  /// null = อัตโนมัติ (ต้นฉบับ). Default 1080p as requested.
  int? _qualityHeight = kIsWeb ? null : 1080;
  DateTime? _lastBackAt;

  /// Android: setSize / width+height are unsupported — use scale only when lowering.
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  List<VideoTrack> _videoTracks = const [];
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  VideoTrack? _videoTrack;
  AudioTrack? _audio;
  SubtitleTrack? _subtitle;
  var _didPreferTracks = false;
  DateTime _lastPosUi = DateTime.fromMillisecondsSinceEpoch(0);
  final _rootFocus = FocusNode(debugLabel: 'player-root');
  final _closeFocus = FocusNode(debugLabel: 'player-close');
  final _playFocus = FocusNode(debugLabel: 'player-play');
  final _seekFocus = FocusNode(debugLabel: 'player-seek');
  var _seekFocused = false;
  /// Resume seek after duration is known — early seek is often ignored by media_kit.
  int _pendingStartMs = 0;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  static const _fits = <(String, BoxFit)>[
    ('พอดีจอ', BoxFit.contain),
    ('เต็มจอ', BoxFit.cover),
    ('ยืดเต็ม', BoxFit.fill),
  ];
  static const _qualities = <(String, int?)>[
    ('อัตโนมัติ', null),
    ('1080p', 1080),
    ('720p', 720),
    ('480p', 480),
  ];

  @override
  void initState() {
    super.initState();
    // Modest demux buffer — big buffers stall open on 1GB TV boxes.
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: kIsWeb ? 32 * 1024 * 1024 : 16 * 1024 * 1024,
        title: 'Niceflix',
      ),
    );
    // Stable Android path: hardware decode, scale 1.0 — never recreate on open.
    _video = VideoController(_player, configuration: _videoConfig());
    _pendingStartMs = widget.startAtMs;
    _wireStreams();
    _openMedia();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  VideoControllerConfiguration _videoConfig() {
    if (kIsWeb) {
      return const VideoControllerConfiguration(enableHardwareAcceleration: true);
    }
    // Android: setSize/width/height unsupported. Do NOT recreate controller or
    // shrink scale on open — that hung playback on TrueID/TX boxes.
    return VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      vo: 'gpu',
      hwdec: 'mediacodec-copy',
      scale: 1.0,
      height: _isAndroid ? null : _qualityHeight,
      width: _isAndroid || _qualityHeight == null
          ? null
          : (_qualityHeight! * 16 / 9).round(),
    );
  }

  Future<void> _applyOutputSize() async {
    if (kIsWeb || _isAndroid) return; // Android: video-track pick only (see _setQuality)
    if (_qualityHeight == null) {
      await _video.setSize();
    } else {
      final h = _qualityHeight!;
      await _video.setSize(width: (h * 16 / 9).round(), height: h);
    }
  }

  void _wireStreams() {
    _subs.addAll([
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        if (value) _armHide();
      }),
      _player.stream.buffering.listen((value) {
        if (mounted) setState(() => _buffering = value);
      }),
      _player.stream.position.listen((value) {
        if (!mounted) return;
        // Avoid rebuilding chrome every demux tick — major stutter source on TV.
        final now = DateTime.now();
        // Panels / hidden chrome: never rebuild for position ticks.
        if (!_showChrome || _showSettings || _showOptions) {
          _position = value;
          return;
        }
        if (now.difference(_lastPosUi) < const Duration(milliseconds: 500)) {
          _position = value;
          return;
        }
        _lastPosUi = now;
        setState(() => _position = value);
      }),
      _player.stream.duration.listen((value) {
        if (!mounted) return;
        if (value == _duration) return;
        setState(() => _duration = value);
        _applyPendingStartSeek();
      }),
      _player.stream.tracks.listen((tracks) {
        if (!mounted) return;
        setState(() {
          _videoTracks = tracks.video.where((t) => t != VideoTrack.auto() && t != VideoTrack.no()).toList();
          _audioTracks = tracks.audio.where((t) => t != AudioTrack.auto() && t != AudioTrack.no()).toList();
          _subtitleTracks =
              tracks.subtitle.where((t) => t != SubtitleTrack.auto() && t != SubtitleTrack.no()).toList();
        });
        _preferThaiTracks();
      }),
      _player.stream.track.listen((track) {
        if (!mounted) return;
        setState(() {
          _videoTrack = track.video;
          _audio = track.audio;
          _subtitle = track.subtitle;
        });
      }),
      _player.stream.error.listen((message) {
        if (message.isEmpty || !mounted || _ready) return;
        // media_kit ส่ง error ระหว่างโหลดบ่อย — นับเป็นล้มเหลวเฉพาะตอนยังไม่พร้อมเล่น
        if (_isFatalOpenError(message)) {
          _markFailed(message);
        }
      }),
    ]);
  }

  bool _isFatalOpenError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('failed to open') ||
        lower.contains('no decoder') ||
        lower.contains('unsupported') ||
        lower.contains('cannot play') ||
        lower.contains('format error') ||
        lower.contains('not supported');
  }

  String _defaultFailMessage() {
    if (kIsWeb) {
      return 'Chrome เล่นไฟล์ MKV ไม่ได้\nลองรันบน macOS หรือ Android TV — ตัวเล่นเต็มรองรับ MKV/แทร็กเสียง/ซับ';
    }
    return 'เล่นไฟล์นี้ไม่สำเร็จ\nลองไฟล์อื่น หรือตรวจว่าไฟล์ไม่เสีย';
  }

  void _markFailed([String? detail]) {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _failMessage = _defaultFailMessage();
      if (detail != null && detail.trim().isNotEmpty && !kIsWeb) {
        _failMessage = '${_failMessage!}\n($detail)';
      }
    });
  }

  Future<void> _openMedia() async {
    try {
      final path = widget.filePath;
      final Media media;
      if (path != null && path.isNotEmpty) {
        if (kIsWeb) {
          _markFailed();
          return;
        }
        media = Media(path.startsWith('file:') ? path : 'file://$path');
      } else if (widget.url != null) {
        media = Media(widget.url!);
      } else {
        _markFailed();
        return;
      }

      // บนเว็บ MKV แทบไม่เล่นได้ใน HTML5 — แจ้งเร็วๆ ถ้าชื่อไฟล์เป็น mkv
      final name = (widget.libraryRef?.name ?? widget.title).toLowerCase();
      if (kIsWeb && name.endsWith('.mkv')) {
        _markFailed();
        return;
      }

      await _player.setVolume(100);
      _openWatchdog?.cancel();
      _openWatchdog = Timer(const Duration(seconds: 12), () {
        if (mounted && !_ready && !_failed) _markFailed();
      });

      await _player.open(media, play: false);
      if (!mounted) return;

      // Cap output before play (Android uses scale; setSize is desktop-only).
      if (!kIsWeb && _qualityHeight != null && !_isAndroid) {
        await _applyOutputSize();
      }

      await _player.setRate(_speed);
      // เปิดคำบรรยายอัตโนมัติถ้ามีในไฟล์ — ผู้ใช้ปิดได้ในตั้งค่า
      await _player.setSubtitleTrack(SubtitleTrack.auto());
      await _player.setAudioTrack(AudioTrack.auto());
      await _player.play();
      // Resume after play — seek-before-play is dropped on many Android decoders.
      await _applyPendingStartSeek();

      if (!mounted) return;
      _openWatchdog?.cancel();
      setState(() {
        _ready = true;
        _failed = false;
        _failMessage = null;
      });
      _armHide();
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persistProgress());
    } catch (error) {
      _openWatchdog?.cancel();
      _markFailed(error.toString());
    }
  }

  Future<void> _preferThaiTracks() async {
    if (_didPreferTracks) return;
    if (_audioTracks.isEmpty && _subtitleTracks.isEmpty) return;
    _didPreferTracks = true;

    final audioPick = _findPreferred(_audioTracks, (t) => _langOf(t.language, t.title));
    if (audioPick != null) {
      await _player.setAudioTrack(audioPick);
    }

    final subPick = _findPreferred(_subtitleTracks, (t) => _langOf(t.language, t.title));
    if (subPick != null) {
      await _player.setSubtitleTrack(subPick);
    } else if (_subtitleTracks.isNotEmpty) {
      // ไม่มีไทย — เปิดแทร็กแรกที่มีในไฟล์แทนการปิด
      await _player.setSubtitleTrack(_subtitleTracks.first);
    }
  }

  T? _findPreferred<T>(List<T> tracks, String Function(T) langOf) {
    if (tracks.isEmpty) return null;
    for (final track in tracks) {
      final lang = langOf(track);
      if (lang.contains('th') || lang.contains('thai') || lang.contains('ไทย')) return track;
    }
    return null;
  }

  String _langOf(String? language, String? title) =>
      '${language ?? ''} ${title ?? ''}'.toLowerCase();

  Future<void> _applyPendingStartSeek() async {
    final ms = _pendingStartMs;
    if (ms <= 0) return;
    final duration = _player.state.duration.inMilliseconds;
    if (duration <= 0) return;
    _pendingStartMs = 0;
    final clamped = ms.clamp(0, (duration - 2000).clamp(0, duration));
    if (clamped < 1000) return;
    try {
      await _player.seek(Duration(milliseconds: clamped));
      if (mounted) setState(() => _position = Duration(milliseconds: clamped));
    } catch (_) {}
  }

  Future<void> _persistProgress() async {
    final ref = widget.libraryRef;
    if (ref == null) return;
    final position = _player.state.position.inMilliseconds;
    final duration = _player.state.duration.inMilliseconds;
    if (duration <= 0) return;
    if (!mounted) return;
    await AppScope.of(context).saveWatchProgress(
      ref: ref,
      positionMs: position,
      durationMs: duration,
    );
  }

  /// Seek bar ← → steps (5 minutes).
  Future<void> _scrubByStep(int direction) async {
    await _seekBy(Duration(minutes: 5 * direction));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _openWatchdog?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _rootFocus.dispose();
    _closeFocus.dispose();
    _playFocus.dispose();
    _seekFocus.dispose();
    _player.dispose();
    super.dispose();
  }

  bool get _panelOpen => _showSettings || _showOptions;

  void _armHide() {
    if (_panelOpen) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _playing && !_panelOpen) {
        setState(() => _showChrome = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showChrome) _rootFocus.requestFocus();
        });
      }
    });
  }

  void _reveal() {
    final wasHidden = !_showChrome;
    if (wasHidden) setState(() => _showChrome = true);
    _armHide();
    if (wasHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showChrome && !_panelOpen) {
          _playFocus.requestFocus();
        }
      });
    }
  }

  /// Single back path — PopScope + remote both land here (debounced).
  bool _handlePlayerBack() {
    if (!mounted) return true;
    final now = DateTime.now();
    if (_lastBackAt != null && now.difference(_lastBackAt!) < const Duration(milliseconds: 400)) {
      return true;
    }
    _lastBackAt = now;

    if (_showOptions) {
      _closeOptions();
      return true;
    }
    if (_showSettings) {
      _closeSettings();
      return true;
    }
    if (_showChrome) {
      setState(() => _showChrome = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rootFocus.requestFocus();
      });
      return true;
    }
    _close();
    return true;
  }

  /// Hardware path — works even when Transform/focus tree on TV boxes misbehaves.
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      return _handlePlayerBack();
    }

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(const Duration(seconds: 10));
      return true;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(const Duration(seconds: -10));
      return true;
    }

    if (_panelOpen) {
      // TV remotes: force ActivateIntent so list rows receive OK/Select.
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA) {
        final primary = FocusManager.instance.primaryFocus;
        final ctx = primary?.context;
        if (ctx != null) {
          final invoked = Actions.maybeInvoke<ActivateIntent>(ctx, const ActivateIntent());
          if (invoked != null) return true;
        }
      }
      // D-pad: let FocusScope move between rows.
      return false;
    }

    if (!_showChrome) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.gameButtonStart) {
        _reveal();
        _togglePlay();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowUp) {
        // up also reveals chrome for browsing controls
        if (key == LogicalKeyboardKey.arrowRight) {
          _reveal();
          _seekBy(const Duration(seconds: 10));
        } else {
          _reveal();
        }
        return true;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowDown) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          _reveal();
          _seekBy(const Duration(seconds: -10));
        } else {
          _reveal();
        }
        return true;
      }
      _reveal();
      return true;
    }

    // Chrome visible: do not steal D-pad — focused buttons need it.
    // Fallback OK if somehow nothing focused:
    if ((key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA) &&
        FocusManager.instance.primaryFocus == null) {
      _togglePlay();
      return true;
    }
    return false;
  }

  Future<void> _togglePlay() async {
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
      setState(() => _showChrome = true);
      await _persistProgress();
    } else {
      await _player.play();
      _armHide();
    }
  }

  Future<void> _seekBy(Duration delta) async {
    if (!_ready) return;
    final next = _position + delta;
    final end = _duration;
    final clamped = next < Duration.zero ? Duration.zero : (end > Duration.zero && next > end ? end : next);
    await _player.seek(clamped);
    _reveal();
    await _persistProgress();
  }

  Future<void> _seekTo(Duration value) async {
    if (!_ready) return;
    await _player.seek(value);
    _reveal();
    await _persistProgress();
  }

  Future<void> _setSpeed(double speed) async {
    _speed = speed;
    if (mounted) setState(() {});
    try {
      await _player.setRate(speed);
    } catch (_) {}
  }

  void _setFit(BoxFit fit) {
    if (_fit == fit) return;
    setState(() => _fit = fit);
  }

  Future<void> _setQuality(int? height) async {
    _qualityHeight = height;
    await _applyOutputSize();
    // ถ้ามีหลายแทร็กวิดีโอ ให้เลือกแทร็กที่ใกล้ความสูงที่เลือก
    if (height != null && _videoTracks.length > 1) {
      final match = _bestVideoTrackForHeight(height);
      if (match != null) await _player.setVideoTrack(match);
    } else if (height == null && _videoTracks.isNotEmpty) {
      await _player.setVideoTrack(VideoTrack.auto());
    }
    if (mounted) setState(() {});
  }

  VideoTrack? _bestVideoTrackForHeight(int height) {
    VideoTrack? best;
    var bestDelta = 1 << 30;
    for (final track in _videoTracks) {
      final h = track.h;
      if (h == null) continue;
      final delta = (h - height).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = track;
      }
    }
    return best;
  }

  Future<void> _setVideoTrack(VideoTrack track) async {
    await _player.setVideoTrack(track);
    setState(() => _videoTrack = track);
    _reveal();
  }

  String _videoTrackLabel(VideoTrack track) {
    if (track == VideoTrack.auto()) return 'อัตโนมัติ';
    if (track == VideoTrack.no()) return 'ปิดภาพ';
    final parts = <String>[];
    if (track.w != null && track.h != null) {
      parts.add('${track.w}×${track.h}');
    } else if (track.h != null) {
      parts.add('${track.h}p');
    }
    final title = track.title?.trim();
    final language = track.language?.trim();
    if (title != null && title.isNotEmpty) parts.add(title);
    if (language != null && language.isNotEmpty) parts.add(language);
    if (parts.isEmpty) return 'แทร็ก ${track.id}';
    return parts.join(' · ');
  }

  Future<void> _setAudio(AudioTrack track) async {
    _didPreferTracks = true; // don't let auto-prefer overwrite user choice
    try {
      await _player.setAudioTrack(track);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _audio = track);
  }

  Future<void> _setSubtitle(SubtitleTrack track) async {
    _didPreferTracks = true; // don't let auto-prefer overwrite user choice
    try {
      await _player.setSubtitleTrack(track);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _subtitle = track);
  }

  bool _isAudioSelected(AudioTrack track) {
    final current = _audio;
    if (current == null) return track == AudioTrack.auto();
    return current.id == track.id;
  }

  bool _isSubtitleSelected(SubtitleTrack track) {
    final current = _subtitle;
    if (current == null) return track == SubtitleTrack.no();
    return current.id == track.id;
  }

  String _clock(Duration value) {
    final total = value.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _audioLabel(AudioTrack track) {
    if (track == AudioTrack.auto()) return 'อัตโนมัติ';
    if (track == AudioTrack.no()) return 'ปิดเสียง';
    final title = track.title?.trim();
    final language = track.language?.trim();
    if (title != null && title.isNotEmpty && language != null && language.isNotEmpty) {
      return '$title ($language)';
    }
    if (title != null && title.isNotEmpty) return title;
    if (language != null && language.isNotEmpty) return language;
    return 'แทร็ก ${track.id}';
  }

  String _subtitleLabel(SubtitleTrack track) {
    if (track == SubtitleTrack.auto()) return 'อัตโนมัติ';
    if (track == SubtitleTrack.no()) return 'ปิด';
    final title = track.title?.trim();
    final language = track.language?.trim();
    if (title != null && title.isNotEmpty && language != null && language.isNotEmpty) {
      return '$title ($language)';
    }
    if (title != null && title.isNotEmpty) return title;
    if (language != null && language.isNotEmpty) return language;
    return 'แทร็ก ${track.id}';
  }

  Future<void> _close() async {
    _progressTimer?.cancel();
    await _persistProgress();
    if (mounted) Navigator.of(context).pop();
  }

  void _openSettings() {
    setState(() {
      _showSettings = true;
      _showOptions = false;
      _showChrome = true;
    });
    _hideTimer?.cancel();
  }

  void _closeSettings() {
    setState(() => _showSettings = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showChrome) _playFocus.requestFocus();
    });
    _armHide();
  }

  void _openOptions() {
    setState(() {
      _showOptions = true;
      _showSettings = false;
      _showChrome = true;
    });
    _hideTimer?.cancel();
  }

  void _closeOptions() {
    setState(() => _showOptions = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showChrome) _playFocus.requestFocus();
    });
    _armHide();
  }

  Widget _videoSurface() {
    return Video(
      // Key forces viewport rebuild when fit changes (media_kit can keep old params).
      key: ValueKey('fit-${_fit.name}'),
      controller: _video,
      fit: _fit,
      controls: NoVideoControls,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        style: TextStyle(
          height: 1.3,
          fontSize: 28,
          letterSpacing: 0.1,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          backgroundColor: Color(0x88000000),
          shadows: [
            Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black),
          ],
        ),
        textAlign: TextAlign.center,
        padding: EdgeInsets.fromLTRB(40, 0, 40, 96),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePlayerBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          child: MouseRegion(
            opaque: true,
            onHover: (_) => _reveal(),
            onEnter: (_) => _reveal(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Isolate video from chrome setState / focus animations.
                Positioned.fill(
                  child: RepaintBoundary(child: _videoSurface()),
                ),
                // Full-screen spinner only while opening — after ready, small corner hint.
                if (_buffering && !_failed && !_ready)
                  const Center(child: CircularProgressIndicator(color: themeAccent, strokeWidth: 3)),
                if (_buffering && !_failed && _ready)
                  const Positioned(
                    top: 20,
                    right: 20,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: themeAccent, strokeWidth: 2),
                    ),
                  ),
                if (_failed)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Text(
                        _failMessage ?? _defaultFailMessage(),
                        textAlign: TextAlign.center,
                        style: bodyStyle(size: 18, color: themeText),
                      ),
                    ),
                  ),
                if (_showChrome && _ready && !_panelOpen) _playerChrome(progress),
                if (_showSettings) _trackPickerOverlay(),
                if (_showOptions) _optionsOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerChrome(double progress) {
    return Positioned.fill(
      child: MouseRegion(
        onHover: (_) => _reveal(),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Color(0x99000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [Color(0xB3000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Netflix-like: Close → Play/skip → Seek ↔ → ภาษา/ตัวเลือก
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 16, 36, 16),
                  child: Column(
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: _topBar(),
                      ),
                      const Spacer(),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: _centerTransport(),
                      ),
                      const SizedBox(height: 20),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: _seekBar(progress),
                      ),
                      const SizedBox(height: 14),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: _audioSubsButton(),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        const SizedBox(width: 44),
        Expanded(
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(size: 16, weight: FontWeight.w600),
          ),
        ),
        _ChromeIconButton(
          icon: Icons.close_rounded,
          size: 22,
          hitSize: 44,
          focusNode: _closeFocus,
          onPressed: _close,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _playFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
        ),
      ],
    );
  }

  Widget _centerTransport() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChromeIconButton(
          icon: Icons.replay_10_rounded,
          size: 34,
          hitSize: 56,
          onPressed: () => _seekBy(const Duration(seconds: -10)),
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _closeFocus.requestFocus();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _seekFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
        ),
        const SizedBox(width: 40),
        _ChromeIconButton(
          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 48,
          hitSize: 72,
          autofocus: true,
          focusNode: _playFocus,
          emphasized: true,
          onPressed: _togglePlay,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _closeFocus.requestFocus();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _seekFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
        ),
        const SizedBox(width: 40),
        _ChromeIconButton(
          icon: Icons.forward_10_rounded,
          size: 34,
          hitSize: 56,
          onPressed: () => _seekBy(const Duration(seconds: 10)),
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _closeFocus.requestFocus();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _seekFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
        ),
      ],
    );
  }

  /// TV seek — big red thumb when focused; ← → jump 5 minutes.
  Widget _seekBar(double progress) {
    final thumbSize = _seekFocused ? 22.0 : 12.0;
    final trackH = _seekFocused ? 6.0 : 3.0;
    return Focus(
      focusNode: _seekFocus,
      onFocusChange: (hasFocus) {
        if (_seekFocused == hasFocus) return;
        setState(() => _seekFocused = hasFocus);
        if (hasFocus) _reveal();
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft) {
          _scrubByStep(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _scrubByStep(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _playFocus.requestFocus();
          return KeyEventResult.handled;
        }
        // Down → ภาษา/ตัวเลือก (default traversal)
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Text(_clock(_position), style: bodyStyle(size: 13, color: themeText)),
            const SizedBox(width: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final ratio = progress.clamp(0.0, 1.0);
                  final thumb = ratio * w;
                  return SizedBox(
                    height: 28,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: trackH,
                          width: w,
                          decoration: BoxDecoration(
                            color: const Color(0x55FFFFFF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Container(
                          height: trackH,
                          width: thumb,
                          decoration: BoxDecoration(
                            color: themeAccent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Positioned(
                          left: (thumb - thumbSize / 2).clamp(0.0, w - thumbSize),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              color: themeAccent,
                              shape: BoxShape.circle,
                              boxShadow: _seekFocused
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x99E50914),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : const [],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Text(_clock(_duration), style: bodyStyle(size: 13, color: themeMuted)),
          ],
        ),
      ),
    );
  }

  Widget _chromePill({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool autofocus = false,
  }) {
    return TvFocus(
      autofocus: autofocus,
      scale: 1.0,
      borderRadius: 22,
      onPressed: onPressed,
      onFocused: (_) => _reveal(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: themeText),
            const SizedBox(width: 8),
            Text(label, style: bodyStyle(size: 14, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _audioSubsButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chromePill(
          icon: Icons.subtitles_outlined,
          label: 'ภาษา',
          onPressed: _openSettings,
        ),
        const SizedBox(width: 12),
        _chromePill(
          icon: Icons.tune_rounded,
          label: 'ตัวเลือก',
          onPressed: _openOptions,
        ),
      ],
    );
  }

  /// Netflix-style dual column: Audio | Subtitles, D-pad friendly.
  Widget _trackPickerOverlay() {
    final audioOptions = <AudioTrack>[
      if (_audioTracks.isNotEmpty) ..._audioTracks else AudioTrack.auto(),
      AudioTrack.no(),
    ];
    // Prefer "Off" first for subs like the reference.
    final subtitleOptions = <SubtitleTrack>[
      SubtitleTrack.no(),
      ..._subtitleTracks,
      if (_subtitleTracks.isEmpty) SubtitleTrack.auto(),
    ];

    return Positioned.fill(
      child: Material(
        color: const Color(0xE6000000),
        child: SafeArea(
          child: FocusScope(
            autofocus: true,
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Audio & Subtitles', style: displayStyle(size: 28)),
                        const Spacer(),
                        TvFocus(
                          listItem: true,
                          borderRadius: 8,
                          onPressed: _closeSettings,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Text('Close', style: bodyStyle(size: 16, weight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _trackColumn(
                              title: 'Audio',
                              children: [
                                for (var i = 0; i < audioOptions.length; i++)
                                  _trackRow(
                                    label: _audioLabel(audioOptions[i]),
                                    selected: _isAudioSelected(audioOptions[i]),
                                    autofocus: i == 0,
                                    onPressed: () => _setAudio(audioOptions[i]),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 48),
                          Expanded(
                            child: _trackColumn(
                              title: 'Subtitles',
                              children: [
                                for (var i = 0; i < subtitleOptions.length; i++)
                                  _trackRow(
                                    label: _subtitleLabel(subtitleOptions[i]),
                                    selected: _isSubtitleSelected(subtitleOptions[i]),
                                    autofocus: audioOptions.isEmpty && i == 0,
                                    onPressed: () => _setSubtitle(subtitleOptions[i]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '← → สลับคอลัมน์   ↑ ↓ เลือก   OK ยืนยัน   Back ปิด',
                      textAlign: TextAlign.center,
                      style: bodyStyle(size: 13, color: themeFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Options: quality / screen fit / speed — remote-friendly columns.
  Widget _optionsOverlay() {
    return Positioned.fill(
      child: Material(
        color: const Color(0xE6000000),
        child: SafeArea(
          child: FocusScope(
            autofocus: true,
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('ตัวเลือก', style: displayStyle(size: 28)),
                        const Spacer(),
                        TvFocus(
                          listItem: true,
                          borderRadius: 8,
                          onPressed: _closeOptions,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Text('ปิด', style: bodyStyle(size: 16, weight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _trackColumn(
                              title: 'คุณภาพ',
                              children: [
                                for (var i = 0; i < _qualities.length; i++)
                                  _trackRow(
                                    label: _qualities[i].$1,
                                    selected: _qualityHeight == _qualities[i].$2,
                                    autofocus: i == 0,
                                    onPressed: () => _setQuality(_qualities[i].$2),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: _trackColumn(
                              title: 'ขนาดจอ',
                              children: [
                                for (var i = 0; i < _fits.length; i++)
                                  _trackRow(
                                    label: _fits[i].$1,
                                    selected: _fit == _fits[i].$2,
                                    onPressed: () => _setFit(_fits[i].$2),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: _trackColumn(
                              title: 'ความเร็ว',
                              children: [
                                for (var i = 0; i < _speeds.length; i++)
                                  _trackRow(
                                    label: '${_speeds[i]}x',
                                    selected: _speed == _speeds[i],
                                    onPressed: () => _setSpeed(_speeds[i]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '← → สลับคอลัมน์   ↑ ↓ เลือก   OK ยืนยัน   Back ปิด',
                      textAlign: TextAlign.center,
                      style: bodyStyle(size: 13, color: themeFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trackColumn({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 14),
          child: Text(title, style: bodyStyle(size: 22, weight: FontWeight.w700)),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _trackRow({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TvFocus(
        autofocus: autofocus,
        listItem: true,
        borderRadius: 6,
        scale: 1,
        onPressed: onPressed,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: selected
                      ? const Icon(Icons.check_rounded, size: 22, color: Colors.white)
                      : null,
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(
                      size: 18,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.white : const Color(0xFFBDBDC6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.hitSize,
    this.autofocus = false,
    this.emphasized = false,
    this.focusNode,
    this.onKeyEvent,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double? hitSize;
  final bool autofocus;
  final bool emphasized;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final box = hitSize ?? (size + 28);
    return TvFocus(
      autofocus: autofocus,
      focusNode: focusNode,
      scale: emphasized ? 1.04 : 1.0,
      circle: true,
      borderRadius: box / 2,
      onPressed: onPressed,
      onKeyEvent: onKeyEvent,
      child: SizedBox(
        width: box,
        height: box,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: emphasized ? const Color(0xF2FFFFFF) : const Color(0x66FFFFFF),
          ),
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: emphasized ? const Color(0xFF111111) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

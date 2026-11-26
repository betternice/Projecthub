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
  late final VideoController _video;
  final _subs = <StreamSubscription<dynamic>>[];

  var _ready = false;
  var _failed = false;
  String? _failMessage;
  var _showChrome = true;
  var _showSettings = false;
  var _playing = false;
  var _buffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _openWatchdog;

  BoxFit _fit = BoxFit.contain;
  double _speed = 1.0;
  /// null = ความละเอียดต้นฉบับ, อื่นๆ = จำกัดความสูงเอาต์พุต
  int? _qualityHeight;
  List<VideoTrack> _videoTracks = const [];
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  VideoTrack? _videoTrack;
  AudioTrack? _audio;
  SubtitleTrack? _subtitle;
  var _didPreferTracks = false;

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
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        title: 'NICE',
      ),
    );
    _video = VideoController(_player);
    _wireStreams();
    _openMedia();
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
        if (mounted) setState(() => _position = value);
      }),
      _player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
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

      if (widget.startAtMs > 0) {
        await _player.seek(Duration(milliseconds: widget.startAtMs));
      }
      await _player.setRate(_speed);
      // เปิดคำบรรยายอัตโนมัติถ้ามีในไฟล์ — ผู้ใช้ปิดได้ในตั้งค่า
      await _player.setSubtitleTrack(SubtitleTrack.auto());
      await _player.setAudioTrack(AudioTrack.auto());
      await _player.play();

      if (!mounted) return;
      _openWatchdog?.cancel();
      setState(() {
        _ready = true;
        _failed = false;
        _failMessage = null;
      });
      _armHide();
      _progressTimer = Timer.periodic(const Duration(seconds: 8), (_) => _persistProgress());
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

  Future<void> _persistProgress() async {
    final ref = widget.libraryRef;
    if (ref == null || !_ready) return;
    final position = _player.state.position.inMilliseconds;
    final duration = _player.state.duration.inMilliseconds;
    if (!mounted) return;
    await AppScope.of(context).saveWatchProgress(
      ref: ref,
      positionMs: position,
      durationMs: duration,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _openWatchdog?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _armHide() {
    if (_showSettings) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && !_showSettings) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _reveal() {
    if (!_showChrome) setState(() => _showChrome = true);
    _armHide();
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
    await _player.setRate(speed);
    setState(() {});
    _reveal();
  }

  void _setFit(BoxFit fit) {
    setState(() => _fit = fit);
    _reveal();
  }

  Future<void> _setQuality(int? height) async {
    _qualityHeight = height;
    if (height == null) {
      await _video.setSize();
    } else {
      // คงอัตราส่วน 16:9 สำหรับเอาต์พุต — ลดโหลดเครื่องตอนเล่นไฟล์ใหญ่
      final width = (height * 16 / 9).round();
      await _video.setSize(width: width, height: height);
    }
    // ถ้ามีหลายแทร็กวิดีโอ ให้เลือกแทร็กที่ใกล้ความสูงที่เลือก
    if (height != null && _videoTracks.length > 1) {
      final match = _bestVideoTrackForHeight(height);
      if (match != null) await _player.setVideoTrack(match);
    } else if (height == null && _videoTracks.isNotEmpty) {
      await _player.setVideoTrack(VideoTrack.auto());
    }
    if (mounted) setState(() {});
    _reveal();
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
    await _player.setAudioTrack(track);
    setState(() => _audio = track);
    _reveal();
  }

  Future<void> _setSubtitle(SubtitleTrack track) async {
    await _player.setSubtitleTrack(track);
    setState(() => _subtitle = track);
    _reveal();
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
    await _persistProgress();
    if (mounted) Navigator.of(context).pop();
  }

  void _openSettings() {
    setState(() {
      _showSettings = true;
      _showChrome = true;
    });
    _hideTimer?.cancel();
  }

  void _closeSettings() {
    setState(() => _showSettings = false);
    _armHide();
  }

  Widget _videoSurface() {
    return Video(
      controller: _video,
      fit: _fit,
      controls: NoVideoControls,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        style: TextStyle(
          height: 1.35,
          fontSize: 42,
          letterSpacing: 0.2,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          backgroundColor: Color(0x99000000),
          shadows: [
            Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black),
          ],
        ),
        textAlign: TextAlign.center,
        padding: EdgeInsets.fromLTRB(48, 0, 48, 96),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
            if (_showSettings) {
              _closeSettings();
            } else {
              _close();
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.mediaPlayPause ||
              key == LogicalKeyboardKey.space) {
            _togglePlay();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
            _seekBy(const Duration(seconds: 10));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
            _seekBy(const Duration(seconds: -10));
            return KeyEventResult.handled;
          }
          _reveal();
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          opaque: true,
          onHover: (_) => _reveal(),
          onEnter: (_) => _reveal(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: _videoSurface()),
              if (_buffering && !_failed)
                const Center(child: CircularProgressIndicator(color: themeAccent)),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_showSettings) {
                      _closeSettings();
                      return;
                    }
                    if (_showChrome) {
                      _togglePlay();
                    } else {
                      _reveal();
                    }
                  },
                  onTapDown: (_) {
                    if (!_showChrome) _reveal();
                  },
                  child: const ColoredBox(color: Color(0x01000000)),
                ),
              ),
              if (_failed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(
                      _failMessage ?? _defaultFailMessage(),
                      textAlign: TextAlign.center,
                      style: bodyStyle(size: 22, color: themeText),
                    ),
                  ),
                ),
              if (_showChrome && _ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MouseRegion(
                    onHover: (_) => _reveal(),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(40, 40, 40, 28),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xE6000000)],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: displayStyle(size: 28)),
                            const SizedBox(height: 14),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                activeTrackColor: themeAccent,
                                inactiveTrackColor: const Color(0x33FFFFFF),
                                thumbColor: themeAccent,
                              ),
                              child: Slider(
                                value: progress,
                                onChanged: (value) {
                                  if (_duration.inMilliseconds <= 0) return;
                                  final ms = (value * _duration.inMilliseconds).round();
                                  _seekTo(Duration(milliseconds: ms));
                                },
                              ),
                            ),
                            Text(
                              '${_clock(_position)} / ${_clock(_duration)}',
                              style: bodyStyle(size: 14, color: themeMuted),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TvButton(
                                  label: '-10 วิ',
                                  filled: false,
                                  icon: Icons.replay_10,
                                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                                ),
                                TvButton(
                                  label: _playing ? 'หยุดชั่วคราว' : 'เล่น',
                                  autofocus: true,
                                  onPressed: _togglePlay,
                                  icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                ),
                                TvButton(
                                  label: '+10 วิ',
                                  filled: false,
                                  icon: Icons.forward_10,
                                  onPressed: () => _seekBy(const Duration(seconds: 10)),
                                ),
                                TvButton(
                                  label: 'ตั้งค่า',
                                  filled: false,
                                  icon: Icons.tune_rounded,
                                  iconOnly: true,
                                  onPressed: _openSettings,
                                ),
                                TvButton(
                                  label: 'ปิด',
                                  filled: false,
                                  onPressed: _close,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_showSettings) _settingsPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsPanel() {
    final audioOptions = <AudioTrack>[
      AudioTrack.auto(),
      ..._audioTracks,
      AudioTrack.no(),
    ];
    final subtitleOptions = <SubtitleTrack>[
      SubtitleTrack.auto(),
      ..._subtitleTracks,
      SubtitleTrack.no(),
    ];

    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 420,
      child: Material(
        color: const Color(0xF2121218),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('ตั้งค่าการเล่น', style: displayStyle(size: 28)),
                    const Spacer(),
                    TvButton(label: 'ปิด', filled: false, onPressed: _closeSettings),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    children: [
                      Text('กรอบภาพ', style: bodyStyle(size: 14, color: themeMuted)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _fits)
                            TvButton(
                              label: option.$1,
                              filled: _fit == option.$2,
                              onPressed: () => _setFit(option.$2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('ความละเอียด', style: bodyStyle(size: 14, color: themeMuted)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _qualities)
                            TvButton(
                              label: option.$1,
                              filled: _qualityHeight == option.$2,
                              onPressed: () => _setQuality(option.$2),
                            ),
                        ],
                      ),
                      if (_videoTracks.length > 1) ...[
                        const SizedBox(height: 22),
                        Text('แทร็กวิดีโอ', style: bodyStyle(size: 14, color: themeMuted)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in [VideoTrack.auto(), ..._videoTracks])
                              TvButton(
                                label: _videoTrackLabel(option),
                                filled: _videoTrack == option ||
                                    (_videoTrack == null && option == VideoTrack.auto()),
                                onPressed: () => _setVideoTrack(option),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      Text('ความเร็ว', style: bodyStyle(size: 14, color: themeMuted)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final speed in _speeds)
                            TvButton(
                              label: '${speed}x',
                              filled: _speed == speed,
                              onPressed: () => _setSpeed(speed),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text('ภาษาเสียง', style: bodyStyle(size: 14, color: themeMuted)),
                      const SizedBox(height: 10),
                      if (_audioTracks.isEmpty)
                        Text(
                          'ยังไม่พบแทร็กเสียงในไฟล์ (หรือเครื่องนี้ยังโหลดรายการไม่ครบ)',
                          style: bodyStyle(size: 13, color: themeFaint),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in audioOptions)
                              TvButton(
                                label: _audioLabel(option),
                                filled: _audio == option ||
                                    (_audio == null && option == AudioTrack.auto()),
                                onPressed: () => _setAudio(option),
                              ),
                          ],
                        ),
                      const SizedBox(height: 22),
                      Text('Subtitle', style: bodyStyle(size: 14, color: themeMuted)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in subtitleOptions)
                            TvButton(
                              label: _subtitleLabel(option),
                              filled: _subtitle == option ||
                                  (_subtitle == null && option == SubtitleTrack.auto()),
                              onPressed: () => _setSubtitle(option),
                            ),
                        ],
                      ),
                      if (_subtitleTracks.isEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'ไม่พบคำบรรยายในไฟล์ — ถ้าเป็นแทร็กฝังใน MKV ให้เล่นบน Android/macOS',
                          style: bodyStyle(size: 13, color: themeFaint),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'ตัวเล่นนี้ดึงแทร็กเสียง/คำบรรยายจากไฟล์จริง (รวม MKV) บน Android TV และแอป native '
                        'เบราว์เซอร์รองรับจำกัด',
                        style: bodyStyle(size: 13, color: themeFaint),
                      ),
                    ],
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

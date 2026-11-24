import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';
import '../widgets/tv_focus.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController _controller;
  var _failed = false;
  var _showChrome = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
        _armHide();
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
    _controller.addListener(() {
      if (_controller.value.hasError && mounted && !_failed) {
        setState(() => _failed = true);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _reveal() {
    setState(() => _showChrome = true);
    _armHide();
  }

  void _togglePlay() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() => _showChrome = true);
    } else {
      _controller.play();
      _armHide();
    }
  }

  Future<void> _seekBy(Duration delta) async {
    if (!_controller.value.isInitialized) return;
    final next = _controller.value.position + delta;
    final end = _controller.value.duration;
    final clamped = next < Duration.zero ? Duration.zero : (next > end ? end : next);
    await _controller.seekTo(clamped);
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

  @override
  Widget build(BuildContext context) {
    final ready = _controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
            Navigator.of(context).maybePop();
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
        child: GestureDetector(
          onTap: () {
            if (_showChrome) {
              _togglePlay();
            } else {
              _reveal();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: ready
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const CircularProgressIndicator(color: themeAccent),
              ),
              if (_failed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Text(
                      'เล่นไฟล์นี้ไม่ได้บนเครื่องนี้\nลองไฟล์อื่น หรือตรวจว่ากล่อง TV รองรับ codec ของ MKV',
                      textAlign: TextAlign.center,
                      style: bodyStyle(size: 22, color: themeText),
                    ),
                  ),
                ),
              if (_showChrome && ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(48, 48, 48, 36),
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
                        const SizedBox(height: 16),
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: themeAccent,
                            bufferedColor: Color(0x55FFFFFF),
                            backgroundColor: Color(0x33FFFFFF),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '${_clock(_controller.value.position)} / ${_clock(_controller.value.duration)}',
                              style: bodyStyle(size: 14, color: themeMuted),
                            ),
                            const Spacer(),
                            TvButton(
                              label: _controller.value.isPlaying ? 'หยุดชั่วคราว' : 'เล่น',
                              autofocus: true,
                              onPressed: _togglePlay,
                              icon: _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            ),
                            const SizedBox(width: 12),
                            TvButton(
                              label: 'ปิด',
                              filled: false,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
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
}

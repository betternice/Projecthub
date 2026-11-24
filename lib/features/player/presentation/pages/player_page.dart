import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme.dart';

class PlayerArgs {
  const PlayerArgs({required this.title, required this.url});

  final String title;
  final Uri url;
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.args});

  final PlayerArgs args;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController _video = VideoPlayerController.networkUrl(widget.args.url);
  ChewieController? _chewie;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _video.initialize();
    } on Exception {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _chewie = ChewieController(
        videoPlayerController: _video,
        autoPlay: true,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.text,
          handleColor: AppColors.text,
          bufferedColor: AppColors.muted,
          backgroundColor: AppColors.raised,
        ),
        errorBuilder: (context, _) => const _PlaybackError(),
      );
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewie;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: _failed
                  ? const _PlaybackError()
                  : chewie == null
                  ? const CircularProgressIndicator()
                  : Chewie(controller: chewie),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: () => context.pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      child: Text('ปิด', style: AppText.medium(size: 14)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.args.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.medium(),
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

class _PlaybackError extends StatelessWidget {
  const _PlaybackError();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(16)),
      child: Text(
        'เครื่องนี้เปิดไฟล์นี้ไม่ได้ ตัวเล่นของเครื่องรองรับ mp4 และ mkv ส่วนใหญ่',
        textAlign: TextAlign.center,
        style: AppText.body(size: 14, height: 1.5),
      ),
    );
  }
}

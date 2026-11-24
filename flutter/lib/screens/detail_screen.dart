import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../metadata/tmdb.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, this.match});

  final DriveItem item;
  final MediaMatch? match;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  MediaDetail? _detail;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    if (match != null) {
      _detail = MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final found = widget.match ?? await lookupMedia(widget.item.name, app.tmdbKey);
    if (!mounted || found == null) return;
    final next = await lookupDetail(found, app.tmdbKey);
    if (mounted) setState(() => _detail = next);
  }

  Future<void> _play(String title) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await AppScope.of(context).getToken();
      final url = await getPlaybackUrl(token, widget.item.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerScreen(title: title, url: url)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = presentTitle(widget.item.name);
    final detail = _detail;
    final title = detail?.title ?? parsed.title;
    final year = detail?.year ?? parsed.year;
    final runtime = formatRuntime(detail?.runtime) ?? formatClock(widget.item.durationMs);
    final facts = [
      year,
      runtime,
      if (widget.item.name.toLowerCase().endsWith('.mkv')) 'MKV',
      detail?.director,
      detail?.rating != null ? '★ ${detail!.rating!.toStringAsFixed(1)}' : null,
      ...?detail?.genres,
      formatBytes(widget.item.size),
    ].whereType<String>().where((fact) => fact.isNotEmpty).toList();
    final poster = detail?.posterUrl ?? widget.item.thumbLarge ?? widget.item.thumbMedium;
    final artwork = detail?.backdropUrl ?? poster;

    return Scaffold(
      backgroundColor: themeBg,
      body: Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.goBack): DismissIntent()},
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            }),
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (artwork != null)
                Image.network(artwork, fit: BoxFit.cover, alignment: Alignment.topCenter)
              else
                const ColoredBox(color: Color(0xFF101016)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xF2050508), Color(0xCC050508), Color(0x66050508)],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x33000000), Color(0xF2050508)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(64, 28, 64, 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TvButton(
                              label: 'กลับ',
                              filled: false,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const Spacer(),
                            Text('NICE', style: brandStyle(size: 28, color: themeAccent)),
                            const SizedBox(height: 10),
                            Text(title, style: displayStyle(size: 52)),
                            const SizedBox(height: 14),
                            Text(facts.join('  ·  '), style: bodyStyle(size: 16, color: themeMuted)),
                            if (detail?.overview != null) ...[
                              const SizedBox(height: 18),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 760),
                                child: Text(
                                  detail!.overview!,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: bodyStyle(size: 19, color: const Color(0xFFD6D6DC)),
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(_error!, style: bodyStyle(size: 16, color: themeDanger)),
                            ],
                            const SizedBox(height: 28),
                            Row(
                              children: [
                                TvButton(
                                  label: _busy ? 'กำลังเปิด…' : 'เล่นเลย',
                                  autofocus: true,
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: _busy ? () {} : () => _play(title),
                                ),
                              ],
                            ),
                            if (detail?.cast.isNotEmpty == true) ...[
                              const SizedBox(height: 28),
                              Text('นักแสดง', style: bodyStyle(size: 16, weight: FontWeight.w700, color: themeMuted)),
                              const SizedBox(height: 8),
                              Text(
                                detail!.cast.take(6).map((c) => c.name).join('   '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: bodyStyle(size: 16),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (poster != null) ...[
                        const SizedBox(width: 48),
                        Expanded(
                          flex: 3,
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(poster, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ),
                      ],
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

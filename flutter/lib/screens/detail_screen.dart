import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../library/overview.dart';
import '../metadata/tmdb.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/remote_art.dart';
import '../widgets/tv_focus.dart';
import 'match_picker_screen.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    this.match,
    this.accountId,
    this.accountLabel,
    this.libraryRef,
  });

  final DriveItem item;
  final MediaMatch? match;
  final String? accountId;
  final String? accountLabel;
  final LibraryRef? libraryRef;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  MediaDetail? _detail;
  var _busy = false;
  String? _error;
  late LibraryRef _ref;

  @override
  void initState() {
    super.initState();
    _ref = widget.libraryRef ??
        refFromItem(
          widget.item,
          accountId: widget.accountId,
          accountLabel: widget.accountLabel,
        );
    final match = widget.match;
    if (match != null) {
      _detail = MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
      _ref = _ref.copyWith(
        title: match.title,
        posterUrl: match.posterUrl ?? _ref.posterUrl,
        backdropUrl: match.backdropUrl,
        year: match.year ?? _ref.year,
        overview: match.overview,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({MediaMatch? preferred, bool bypassCache = false}) async {
    final app = AppScope.of(context);
    final found = preferred ??
        widget.match ??
        await lookupMedia(widget.item.name, app.tmdbKey, libraryKey: _ref.key);
    if (!mounted || found == null) return;
    final next = await lookupDetail(found, app.tmdbKey, bypassCache: bypassCache);
    if (!mounted) return;
    setState(() {
      _detail = next;
      _ref = _ref.copyWith(
        title: next.title,
        posterUrl: next.posterUrl ?? _ref.posterUrl,
        backdropUrl: next.backdropUrl ?? _ref.backdropUrl,
        year: next.year ?? _ref.year,
        overview: next.overview ?? _ref.overview,
      );
    });
  }

  Future<void> _editMatch() async {
    final picked = await Navigator.of(context).push<MediaMatch>(
      MaterialPageRoute(
        builder: (_) => MatchPickerScreen(
          filename: widget.item.name,
          initialTitle: _detail?.title ?? _ref.title,
          initialYear: _detail?.year ?? _ref.year,
          currentMatch: _detail?.match,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await applyManualMatch(
      libraryKey: _ref.key,
      filename: widget.item.name,
      match: picked,
    );
    await _load(preferred: picked, bypassCache: true);
  }

  Future<void> _play(String title, {bool resume = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.of(context);
    final progress = app.progressFor(_ref.key);
    final startAt = resume ? (progress?.positionMs ?? 0) : 0;
    try {
      if (widget.item.isLocal || _ref.isLocal) {
        final path = widget.item.localPath ?? _ref.localPath!;
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              title: title,
              filePath: path,
              libraryRef: _ref,
              startAtMs: startAt,
            ),
          ),
        );
      } else {
        final token = await app.getToken(accountId: _ref.accountId ?? widget.accountId);
        final url = await getPlaybackUrl(token, widget.item.id);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              title: title,
              url: url,
              libraryRef: _ref,
              startAtMs: startAt,
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFavorite() async {
    await AppScope.of(context).toggleFavorite(_ref);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final parsed = presentTitle(widget.item.name);
    final detail = _detail;
    final title = detail?.title ?? _ref.title;
    final year = detail?.year ?? _ref.year ?? parsed.year;
    final runtime = formatRuntime(detail?.runtime) ?? formatClock(widget.item.durationMs);
    final progress = app.progressFor(_ref.key);
    final liked = app.isFavorite(_ref.key);
    final facts = [
      year,
      runtime,
      if (widget.item.name.toLowerCase().endsWith('.mkv')) 'MKV',
      if (_ref.accountLabel != null) _ref.accountLabel!,
      detail?.director,
      detail?.rating != null ? '★ ${detail!.rating!.toStringAsFixed(1)}' : null,
      ...?detail?.genres,
      formatBytes(widget.item.size ?? _ref.size),
    ].whereType<String>().where((fact) => fact.isNotEmpty).toList();
    final poster = detail?.posterUrl ?? _ref.posterUrl ?? widget.item.thumbLarge ?? widget.item.thumbMedium;
    final artwork = detail?.backdropUrl ?? _ref.backdropUrl ?? poster;

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
                RemoteArt(url: artwork, fit: BoxFit.cover, alignment: Alignment.topCenter)
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
                            Text('Niceflix', style: brandStyle(size: 28, color: themeAccent)),
                            const SizedBox(height: 10),
                            Text(title, style: displayStyle(size: 52)),
                            const SizedBox(height: 14),
                            Text(facts.join('  ·  '), style: bodyStyle(size: 16, color: themeMuted)),
                            if (detail?.overview != null || _ref.overview != null) ...[
                              const SizedBox(height: 18),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 760),
                                child: Text(
                                  detail?.overview ?? _ref.overview!,
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
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                if (progress != null) ...[
                                  TvButton(
                                    label: _busy
                                        ? 'กำลังเปิด…'
                                        : 'เล่นต่อ · ${formatWatchProgress(progress.positionMs, progress.durationMs)}',
                                    autofocus: true,
                                    icon: Icons.play_arrow_rounded,
                                    onPressed: _busy ? () {} : () => _play(title, resume: true),
                                  ),
                                  TvButton(
                                    label: 'เริ่มใหม่',
                                    filled: false,
                                    onPressed: _busy ? () {} : () => _play(title),
                                  ),
                                  TvButton(
                                    label: 'เล่นจบแล้ว',
                                    filled: false,
                                    icon: Icons.check_circle_outline,
                                    onPressed: () async {
                                      await app.markFinished(_ref.key);
                                      setState(() {});
                                    },
                                  ),
                                ] else
                                  TvButton(
                                    label: _busy ? 'กำลังเปิด…' : 'เล่นเลย',
                                    autofocus: true,
                                    icon: Icons.play_arrow_rounded,
                                    onPressed: _busy ? () {} : () => _play(title),
                                  ),
                                TvButton(
                                  label: liked ? 'เลิกFavourite' : 'Favourite',
                                  filled: liked,
                                  icon: liked ? Icons.favorite : Icons.favorite_border,
                                  onPressed: _toggleFavorite,
                                ),
                                TvButton(
                                  label: app.tr('editMatch'),
                                  filled: false,
                                  icon: Icons.edit_outlined,
                                  onPressed: _editMatch,
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
                                child: RemoteArt(url: poster, fit: BoxFit.cover),
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

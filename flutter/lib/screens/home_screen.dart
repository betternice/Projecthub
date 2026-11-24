import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../metadata/tmdb.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/content_rail.dart';
import '../widgets/poster_card.dart';
import '../widgets/tv_focus.dart';
import 'connect_screen.dart';
import 'detail_screen.dart';

class LibraryMovie {
  const LibraryMovie({
    required this.item,
    required this.title,
    this.year,
    this.match,
  });

  final DriveItem item;
  final String title;
  final String? year;
  final MediaMatch? match;

  String? get art => match?.backdropUrl ?? match?.posterUrl ?? item.thumbLarge ?? item.thumbMedium;
  String? get poster => match?.posterUrl ?? item.thumbLarge ?? item.thumbMedium;
  String? get overview => match?.overview;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<FolderCrumb>? _folders;
  List<DriveItem> _foldersOnly = [];
  List<LibraryMovie> _movies = [];
  LibraryMovie? _hero;
  var _loading = true;
  String? _error;
  var _lookupToken = 0;
  final _scroll = ScrollController();

  FolderCrumb? get _current => _folders == null || _folders!.isEmpty ? null : _folders!.last;

  @override
  void initState() {
    super.initState();
    _restoreFolders();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('folders');
    List<FolderCrumb> next = const [FolderCrumb(id: 'root', name: 'OneDrive')];
    if (raw != null) {
      try {
        final parsed = (jsonDecode(raw) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(FolderCrumb.fromJson)
            .toList();
        if (parsed.isNotEmpty) next = parsed;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _folders = next);
    await _load();
  }

  Future<void> _remember(List<FolderCrumb> next) async {
    setState(() => _folders = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('folders', jsonEncode(next.map((folder) => folder.toJson()).toList()));
    await _load();
  }

  Future<void> _load() async {
    final current = _current;
    final app = AppScope.of(context);
    if (current == null) return;

    if (app.session == null) {
      setState(() {
        _loading = false;
        _error = null;
        _movies = [];
        _foldersOnly = [];
        _hero = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _movies = [];
      _foldersOnly = [];
      _hero = null;
    });

    try {
      final token = await app.getToken();
      final items = await listChildren(token, current.id);
      if (!mounted) return;

      final folders = items.where((item) => item.isFolder).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final videos = items.where(isVideoFile).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final movies = videos.map((item) {
        final parsed = presentTitle(item.name);
        return LibraryMovie(item: item, title: parsed.title, year: parsed.year);
      }).toList();

      setState(() {
        _foldersOnly = folders;
        _movies = movies;
        _hero = movies.isNotEmpty ? movies.first : null;
        _loading = false;
      });

      _enrich(movies);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _enrich(List<LibraryMovie> movies) async {
    final token = ++_lookupToken;
    final app = AppScope.of(context);
    final next = <LibraryMovie>[];
    for (final movie in movies) {
      if (!mounted || token != _lookupToken) return;
      final match = await lookupMedia(movie.item.name, app.tmdbKey);
      next.add(LibraryMovie(
        item: movie.item,
        title: match?.title ?? movie.title,
        year: match?.year ?? movie.year,
        match: match,
      ));
    }
    if (!mounted || token != _lookupToken) return;
    setState(() {
      _movies = next;
      if (next.isNotEmpty) _hero = next.first;
    });
  }

  Future<void> _openConnect() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConnectScreen()),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _openMovie(LibraryMovie movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(item: movie.item, match: movie.match),
      ),
    );
  }

  Future<void> _openFolder(DriveItem folder) async {
    final current = _folders ?? const [];
    await _remember([...current, FolderCrumb(id: folder.id, name: folder.name)]);
  }

  Future<void> _goUp() async {
    final current = _folders;
    if (current == null || current.length <= 1) return;
    await _remember(current.sublist(0, current.length - 1));
  }

  List<LibraryMovie> get _mkvMovies =>
      _movies.where((m) => m.item.name.toLowerCase().endsWith('.mkv')).toList();

  List<LibraryMovie> get _recentMovies => _movies.take(24).toList();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (!app.ready) {
          return const Scaffold(
            backgroundColor: themeBg,
            body: Center(child: CircularProgressIndicator(color: themeAccent)),
          );
        }
        if (app.session == null) return _welcome();
        return _library(app);
      },
    );
  }

  Widget _welcome() {
    return Scaffold(
      backgroundColor: themeBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A0508), Color(0xFF050508), Color(0xFF0A1018)],
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: -40,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [themeAccent.withValues(alpha: 0.28), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(72, 48, 72, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NICE', style: brandStyle(size: 64, color: themeAccent)),
                  const Spacer(),
                  Text('หนังจาก OneDrive\nบน Android TV', style: displayStyle(size: 56)),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      'เชื่อมคลังไฟล์ .mkv / .mp4 จากคลาวด์ แล้วเลือกดูด้วยรีโมทแบบ Netflix',
                      style: bodyStyle(size: 22, color: themeMuted),
                    ),
                  ),
                  const SizedBox(height: 36),
                  TvButton(
                    label: 'เชื่อม OneDrive',
                    autofocus: true,
                    icon: Icons.cloud_outlined,
                    onPressed: _openConnect,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _library(AppState app) {
    final hero = _hero;
    return Scaffold(
      backgroundColor: themeBg,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              if ((_folders?.length ?? 0) > 1) {
                _goUp();
              }
              return null;
            }),
          },
          child: Stack(
            children: [
              if (hero?.art != null)
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    child: Image.network(
                      hero!.art!,
                      key: ValueKey(hero.art),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: themeBg),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0x66000000),
                        themeBg.withValues(alpha: 0.55),
                        themeBg,
                      ],
                      stops: const [0, 0.38, 0.72],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(child: _topBar(app)),
                    SliverToBoxAdapter(child: _heroBlock(hero)),
                    if (_loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator(color: themeAccent)),
                      )
                    else if (_error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _errorState(_error!),
                      )
                    else ...[
                      if (_recentMovies.isNotEmpty)
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      if (_recentMovies.isNotEmpty)
                        SliverToBoxAdapter(
                          child: ContentRail(
                            title: 'ทั้งหมดในโฟลเดอร์นี้',
                            children: [
                              for (var i = 0; i < _recentMovies.length; i++)
                                PosterCard(
                                  title: _recentMovies[i].title,
                                  seed: _recentMovies[i].item.id,
                                  imageUrl: _recentMovies[i].poster,
                                  subtitle: _recentMovies[i].year,
                                  autofocus: i == 0 && hero == null,
                                  onPressed: () => _openMovie(_recentMovies[i]),
                                ),
                            ],
                          ),
                        ),
                      if (_mkvMovies.isNotEmpty) ...[
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: ContentRail(
                            title: 'ไฟล์ MKV',
                            children: [
                              for (final movie in _mkvMovies)
                                PosterCard(
                                  title: movie.title,
                                  seed: movie.item.id,
                                  imageUrl: movie.poster,
                                  subtitle: movie.year ?? 'MKV',
                                  onPressed: () => _openMovie(movie),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (_foldersOnly.isNotEmpty) ...[
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: ContentRail(
                            title: 'โฟลเดอร์',
                            children: [
                              for (final folder in _foldersOnly)
                                PosterCard(
                                  title: folder.name,
                                  seed: folder.id,
                                  width: 220,
                                  height: 124,
                                  subtitle: 'เปิดโฟลเดอร์',
                                  onPressed: () => _openFolder(folder),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (_movies.isEmpty && _foldersOnly.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'ยังไม่มีไฟล์วิดีโอในโฟลเดอร์นี้',
                              style: bodyStyle(size: 20, color: themeMuted),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 56)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppState app) {
    final crumbs = _folders ?? const [];
    final path = crumbs.map((c) => c.name).join('  /  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 18, 56, 8),
      child: Row(
        children: [
          Text('NICE', style: brandStyle(size: 40, color: themeAccent)),
          const SizedBox(width: 28),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle(size: 16, color: themeMuted),
            ),
          ),
          if (crumbs.length > 1) ...[
            TvButton(label: 'ย้อนกลับ', filled: false, onPressed: _goUp),
            const SizedBox(width: 12),
          ],
          TvButton(label: 'รีเฟรช', filled: false, onPressed: _load),
          const SizedBox(width: 12),
          TvButton(
            label: app.session?.displayName ?? 'OneDrive',
            filled: false,
            onPressed: () async {
              await app.signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _heroBlock(LibraryMovie? hero) {
    if (hero == null) {
      return const SizedBox(height: 48);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 24, 56, 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FEATURED', style: bodyStyle(size: 14, weight: FontWeight.w700, color: themeAccentSoft)),
            const SizedBox(height: 10),
            Text(hero.title, style: displayStyle(size: 52)),
            const SizedBox(height: 12),
            Text(
              [
                if (hero.year != null) hero.year!,
                if (hero.item.name.toLowerCase().endsWith('.mkv')) 'MKV',
                if (hero.match?.rating != null) '★ ${hero.match!.rating!.toStringAsFixed(1)}',
                formatBytes(hero.item.size),
              ].whereType<String>().join('  ·  '),
              style: bodyStyle(size: 16, color: themeMuted),
            ),
            if (hero.overview != null) ...[
              const SizedBox(height: 14),
              Text(
                hero.overview!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: bodyStyle(size: 18, color: const Color(0xFFD0D0D6)),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                TvButton(
                  label: 'เล่น',
                  autofocus: true,
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _openMovie(hero),
                ),
                const SizedBox(width: 14),
                TvButton(
                  label: 'รายละเอียด',
                  filled: false,
                  onPressed: () => _openMovie(hero),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: bodyStyle(size: 20, color: themeDanger)),
            const SizedBox(height: 24),
            TvButton(label: 'ลองใหม่', autofocus: true, onPressed: _load),
            const SizedBox(height: 12),
            TvButton(label: 'เชื่อม OneDrive ใหม่', filled: false, onPressed: _openConnect),
          ],
        ),
      ),
    );
  }
}

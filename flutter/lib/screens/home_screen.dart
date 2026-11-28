import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../library/overview.dart';
import '../local/library.dart';
import '../metadata/tmdb.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/content_gallery.dart';
import '../widgets/content_rail.dart';
import '../widgets/poster_card.dart';
import '../widgets/remote_art.dart';
import '../widgets/tv_focus.dart';
import 'detail_screen.dart';
import 'profiles_screen.dart';

class LibraryMovie {
  const LibraryMovie({
    required this.item,
    required this.title,
    this.year,
    this.match,
    this.accountId,
    this.accountLabel,
    this.libraryRef,
  });

  final DriveItem item;
  final String title;
  final String? year;
  final MediaMatch? match;
  final String? accountId;
  final String? accountLabel;
  final LibraryRef? libraryRef;

  String? get art =>
      match?.backdropUrl ??
      libraryRef?.backdropUrl ??
      match?.posterUrl ??
      libraryRef?.posterUrl ??
      item.thumbLarge ??
      item.thumbMedium;
  String? get poster => match?.posterUrl ?? libraryRef?.posterUrl ?? item.thumbLarge ?? item.thumbMedium;
  String? get overview => match?.overview ?? libraryRef?.overview;
  List<String> get genres => match?.genres ?? const [];
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
  var _loadGen = 0;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _boundAccount;

  FolderCrumb? get _current => _folders == null || _folders!.isEmpty ? null : _folders!.last;

  String get _query => _search.text.trim().toLowerCase();

  bool _matchesQuery(LibraryMovie movie) {
    final q = _query;
    if (q.isEmpty) return true;
    final haystack = [
      movie.title,
      movie.item.name,
      movie.year,
      movie.accountLabel,
      ...movie.genres,
      movie.overview,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(q);
  }

  bool _matchesRefQuery(LibraryRef ref) {
    final q = _query;
    if (q.isEmpty) return true;
    final haystack = [
      ref.title,
      ref.name,
      ref.year,
      ref.accountLabel,
      ref.overview,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(q);
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // App open → always land on "ทั้งหมด"
      await AppScope.of(context).openOverview();
      if (!mounted) return;
      await _syncSourceAndLoad(force: true, resetPath: true);
    });
  }

  Future<void> _returnToOverviewHome() async {
    if (!mounted) return;
    _search.clear();
    _searchFocus.unfocus();
    await AppScope.of(context).openOverview();
    if (!mounted) return;
    await _syncSourceAndLoad(force: true, resetPath: true);
    if (_scroll.hasClients) {
      await _scroll.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  /// Back / remote dismiss: search → folder up → overview → leave app.
  /// Only runs when Home is the top route (not detail / player / profiles).
  Future<void> _handleDismiss() async {
    if (!mounted) return;
    // Detail/player sit above Home — never treat their Back as "exit app".
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;

    if (_searchFocus.hasFocus || _query.isNotEmpty) {
      _search.clear();
      _searchFocus.unfocus();
      if (mounted) setState(() {});
      return;
    }
    if ((_folders?.length ?? 0) > 1) {
      await _goUp();
      return;
    }
    final app = AppScope.of(context);
    if (app.source != MediaSource.overview) {
      await _returnToOverviewHome();
      return;
    }
    // Already on overview root — leave the app.
    await SystemNavigator.pop();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<FolderCrumb> _rootCrumbs(AppState app) {
    if (app.source == MediaSource.overview) {
      return const [FolderCrumb(id: 'overview', name: 'ทั้งหมด')];
    }
    if (app.source == MediaSource.oneDrive) {
      return [FolderCrumb(id: 'root', name: app.oneDriveLabel)];
    }
    final path = app.localRootPath ?? '';
    final sep = kIsWeb ? '/' : Platform.pathSeparator;
    final name = path.isEmpty ? 'เครื่องนี้' : path.split(sep).where((s) => s.isNotEmpty).last;
    return [FolderCrumb(id: path.isEmpty ? 'local-root' : path, name: name.isEmpty ? 'เครื่องนี้' : name)];
  }

  String _folderKey(AppState app) {
    if (app.source == MediaSource.overview) return 'folders_overview';
    if (app.source == MediaSource.oneDrive) {
      final id = app.session?.id ?? 'default';
      return 'folders_onedrive_${Uri.encodeComponent(id)}';
    }
    return 'folders_local';
  }

  Future<void> _syncSourceAndLoad({bool force = false, bool resetPath = false}) async {
    final app = AppScope.of(context);
    if (!app.ready) return;
    final bound = '${app.source.name}:${app.session?.id ?? ''}';
    if (!force && !resetPath && _boundAccount == bound && _folders != null) {
      await _load();
      return;
    }
    if (app.source == MediaSource.overview) {
      if (!mounted) return;
      setState(() {
        _folders = _rootCrumbs(app);
        _boundAccount = bound;
      });
      await _load();
      return;
    }
    List<FolderCrumb> next = _rootCrumbs(app);
    // สลับคลัง — เริ่มที่ root เสมอ กันปน path/ไฟล์คลังอื่น
    if (!resetPath) {
      final prefs = await SharedPreferences.getInstance();
      final key = _folderKey(app);
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final parsed = (jsonDecode(raw) as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map(FolderCrumb.fromJson)
              .toList();
          if (parsed.isNotEmpty) {
            if (app.source == MediaSource.local &&
                app.localRootPath != null &&
                parsed.first.id != app.localRootPath) {
              next = _rootCrumbs(app);
            } else if (app.source == MediaSource.oneDrive && parsed.first.name != app.oneDriveLabel) {
              next = [FolderCrumb(id: 'root', name: app.oneDriveLabel), ...parsed.skip(1)];
            } else {
              next = parsed;
            }
          }
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _folders = next;
      _boundAccount = bound;
      _movies = [];
      _foldersOnly = [];
      _hero = null;
    });
    await _load();
  }

  Future<void> _remember(List<FolderCrumb> next) async {
    final app = AppScope.of(context);
    setState(() => _folders = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey(app), jsonEncode(next.map((folder) => folder.toJson()).toList()));
    await _load();
  }

  Future<void> _load() async {
    final current = _current;
    final app = AppScope.of(context);
    if (current == null) return;
    final gen = ++_loadGen;
    final boundSource = app.source;
    final boundAccountId = app.session?.id;

    bool stale() => !mounted || gen != _loadGen || AppScope.of(context).source != boundSource ||
        (boundSource == MediaSource.oneDrive && AppScope.of(context).session?.id != boundAccountId);

    if (app.source == MediaSource.local && (app.localRootPath == null || app.localRootPath!.isEmpty)) {
      setState(() {
        _loading = false;
        _error = null;
        _movies = [];
        _foldersOnly = [];
        _hero = null;
      });
      return;
    }

    if (app.source == MediaSource.oneDrive && app.session == null) {
      setState(() {
        _loading = false;
        _error = 'ยังไม่ได้เชื่อม OneDrive';
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
      if (app.source == MediaSource.overview) {
        final refs = await collectOverviewLibrary(app);
        if (stale()) return;
        final movies = refs
            .map(
              (ref) => LibraryMovie(
                item: ref.toDriveItem(),
                title: ref.title,
                year: ref.year,
                accountId: ref.accountId,
                accountLabel: ref.accountLabel,
                libraryRef: ref,
              ),
            )
            .toList();
        setState(() {
          _foldersOnly = [];
          _movies = movies;
          _hero = movies.isNotEmpty
              ? movies.first
              : (app.continueWatching.isNotEmpty
                  ? LibraryMovie(
                      item: app.continueWatching.first.ref.toDriveItem(),
                      title: app.continueWatching.first.ref.title,
                      year: app.continueWatching.first.ref.year,
                      accountId: app.continueWatching.first.ref.accountId,
                      accountLabel: app.continueWatching.first.ref.accountLabel,
                      libraryRef: app.continueWatching.first.ref,
                    )
                  : null);
          _loading = false;
        });
        _enrich(movies);
        return;
      }

      final List<DriveItem> items;
      if (app.source == MediaSource.local) {
        final path = current.id == 'local-root' ? (app.localRootPath ?? '') : current.id;
        items = await listLocalChildren(path);
      } else {
        // ล็อกโทเคนตามคลังที่กำลังเปิด — กันปนไฟล์คลังอื่น
        final token = await app.getToken(accountId: boundAccountId);
        if (stale()) return;
        items = await listChildren(token, current.id);
      }
      if (stale()) return;

      var folders = items.where((item) => item.isFolder).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      var videos = items.where(isVideoFile).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final account = boundSource == MediaSource.oneDrive
          ? app.accountById(boundAccountId)
          : null;
      // ที่ root ของ OneDrive — โชว์เฉพาะโฟลเดอร์ที่ติ๊กไว้ (ถ้าระบุแล้ว)
      // และไม่โชว์ไฟล์วิดีโอบน root นอกโฟลเดอร์ที่เลือก
      if (account != null &&
          account.hasLibraryFilter &&
          (current.id == 'root' || current.id.isEmpty)) {
        final allowed = account.libraryFolderIds;
        folders = folders.where((f) => allowed.contains(f.id)).toList();
        videos = const [];
      }
      final movies = videos.map((item) {
        final parsed = presentTitle(item.name);
        final ref = refFromItem(item, accountId: account?.id, accountLabel: account?.title ?? 'เครื่องนี้');
        return LibraryMovie(
          item: item,
          title: parsed.title,
          year: parsed.year,
          accountId: account?.id,
          accountLabel: account?.title ?? 'เครื่องนี้',
          libraryRef: ref,
        );
      }).toList();

      if (stale()) return;
      setState(() {
        _foldersOnly = folders;
        _movies = movies;
        _hero = movies.isNotEmpty ? movies.first : null;
        _loading = false;
      });

      _enrich(movies);
    } catch (error) {
      if (stale()) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _enrich(List<LibraryMovie> movies) async {
    final token = ++_lookupToken;
    final loadAtStart = _loadGen;
    final app = AppScope.of(context);
    final next = <LibraryMovie>[];
    for (final movie in movies) {
      if (!mounted || token != _lookupToken || loadAtStart != _loadGen) return;
      final match = await lookupMedia(
        movie.item.name,
        app.tmdbKey,
        libraryKey: movie.libraryRef?.key,
      );
      next.add(LibraryMovie(
        item: movie.item,
        title: match?.title ?? movie.title,
        year: match?.year ?? movie.year,
        match: match,
        accountId: movie.accountId,
        accountLabel: movie.accountLabel,
        libraryRef: movie.libraryRef?.copyWith(
          title: match?.title ?? movie.libraryRef?.title,
          posterUrl: match?.posterUrl ?? movie.libraryRef?.posterUrl,
          backdropUrl: match?.backdropUrl ?? movie.libraryRef?.backdropUrl,
          year: match?.year ?? movie.libraryRef?.year,
          overview: match?.overview ?? movie.libraryRef?.overview,
        ),
      ));
    }
    if (!mounted || token != _lookupToken || loadAtStart != _loadGen) return;
    setState(() {
      _movies = next;
      if (next.isNotEmpty) _hero = next.first;
    });
  }

  Future<void> _openProfiles() async {
    final openedLibrary = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
    );
    if (!mounted) return;
    if (openedLibrary == true) {
      // Explicitly opened a library from profiles — stay on that source.
      await _syncSourceAndLoad(force: true, resetPath: true);
    } else {
      await _returnToOverviewHome();
    }
  }

  Future<void> _pickLocalFolder() async {
    final path = await pickLocalLibraryFolder();
    if (path == null || !mounted) return;
    await AppScope.of(context).setLocalRoot(path);
    await _syncSourceAndLoad(force: true);
  }

  Future<void> _useOverview() async {
    await AppScope.of(context).openOverview();
    await _syncSourceAndLoad(force: true);
  }

  Future<void> _useLocal() async {
    final app = AppScope.of(context);
    if (app.localRootPath == null) {
      await _pickLocalFolder();
      return;
    }
    await app.setSource(MediaSource.local);
    await _syncSourceAndLoad(force: true);
  }

  Future<void> _useOneDriveAccount(Session account) async {
    final app = AppScope.of(context);
    await app.selectAccount(account.id);
    await _syncSourceAndLoad(force: true, resetPath: true);
  }

  Future<void> _openMovie(LibraryMovie movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          item: movie.item,
          match: movie.match,
          accountId: movie.accountId,
          accountLabel: movie.accountLabel,
          libraryRef: movie.libraryRef,
        ),
      ),
    );
    // Stay on the page we came from (same as Detail "กลับ") — do not jump to overview.
    if (mounted) setState(() {});
  }

  Future<void> _openRef(LibraryRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          item: ref.toDriveItem(),
          accountId: ref.accountId,
          accountLabel: ref.accountLabel,
          libraryRef: ref,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openFolder(DriveItem folder) async {
    final current = _folders ?? const [];
    final id = folder.localPath ?? folder.id;
    await _remember([...current, FolderCrumb(id: id, name: folder.name)]);
  }

  Future<void> _goUp() async {
    final app = AppScope.of(context);
    if (app.source == MediaSource.overview) return;
    final current = _folders;
    if (current == null || current.length <= 1) return;
    await _remember(current.sublist(0, current.length - 1));
  }

  List<LibraryMovie> get _visibleMovies => _movies.where(_matchesQuery).toList();

  List<DriveItem> get _visibleFolders {
    final q = _query;
    if (q.isEmpty) return _foldersOnly;
    return _foldersOnly.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  List<WatchProgress> _visibleContinue(AppState app) =>
      app.continueWatching.where((w) => _matchesRefQuery(w.ref)).toList();

  List<LibraryRef> _visibleFavorites(AppState app) =>
      app.favorites.where(_matchesRefQuery).toList();

  static const _genrePriority = [
    'แอ็กชัน',
    'ผจญภัย',
    'แอนิเมชัน',
    'ตลก',
    'อาชญากรรม',
    'สารคดี',
    'ดราม่า',
    'ครอบครัว',
    'แฟนตาซี',
    'ประวัติศาสตร์',
    'สยองขวัญ',
    'ดนตรี',
    'ลึกลับ',
    'โรแมนติก',
    'ไซไฟ',
    'ระทึกขวัญ',
    'สงคราม',
    'ตะวันตก',
  ];

  List<MapEntry<String, List<LibraryMovie>>> get _moviesByGenre {
    final buckets = <String, List<LibraryMovie>>{};
    for (final movie in _visibleMovies) {
      final labels = movie.genres.isNotEmpty ? movie.genres : const ['อื่นๆ'];
      // Put each movie in its primary genre rail only (first genre).
      final genre = labels.first;
      buckets.putIfAbsent(genre, () => []).add(movie);
    }
    final ordered = <MapEntry<String, List<LibraryMovie>>>[];
    for (final name in _genrePriority) {
      final list = buckets.remove(name);
      if (list != null && list.isNotEmpty) ordered.add(MapEntry(name, list));
    }
    final rest = buckets.entries.toList()
      ..sort((a, b) {
        if (a.key == 'อื่นๆ') return 1;
        if (b.key == 'อื่นๆ') return -1;
        return a.key.compareTo(b.key);
      });
    ordered.addAll(rest);
    return ordered;
  }

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
        final bootMessage = app.bootMessage;
        if (bootMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted || app.bootMessage != bootMessage) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(bootMessage), duration: const Duration(seconds: 6)),
            );
            app.clearBootMessage();
          });
        }
        final needsSetup = app.source != MediaSource.overview &&
            app.source == MediaSource.local &&
            (app.localRootPath == null || app.localRootPath!.isEmpty) &&
            !_loading &&
            _movies.isEmpty &&
            _foldersOnly.isEmpty &&
            app.accounts.isEmpty &&
            app.continueWatching.isEmpty &&
            app.favorites.isEmpty;
        if (needsSetup && _error == null) return _welcome(app);
        return _library(app);
      },
    );
  }

  Widget _welcome(AppState app) {
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
                  Text('Niceflix', style: brandStyle(size: 64, color: themeAccent)),
                  const Spacer(),
                  Text(app.tr('welcomeTitle'), style: displayStyle(size: 52)),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Text(
                      app.tr('welcomeBody'),
                      style: bodyStyle(size: 22, color: themeMuted),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      TvButton(
                        label: app.tr('pickLocalFolder'),
                        autofocus: true,
                        icon: Icons.folder_open_rounded,
                        onPressed: _pickLocalFolder,
                      ),
                      const SizedBox(width: 16),
                      TvButton(
                        label: app.tr('profiles'),
                        filled: false,
                        icon: Icons.person_outline_rounded,
                        onPressed: _openProfiles,
                      ),
                    ],
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
    // Featured เฉพาะหน้าแรก (Overview) — ในคลัง/โฟลเดอร์ไม่โชว์
    final hero = app.source == MediaSource.overview && _hero != null && _matchesQuery(_hero!)
        ? _hero
        : null;
    final continueItems = _visibleContinue(app);
    final favoriteItems = _visibleFavorites(app);
    return Scaffold(
      backgroundColor: themeBg,
      // Always canPop:false — otherwise a Back from Detail can also pop Home/exit.
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          // Let pushed routes (detail/player) finish popping first.
          await Future<void>.delayed(Duration.zero);
          if (!mounted) return;
          await _handleDismiss();
        },
        child: ColoredBox(
            color: themeBg,
            child: SafeArea(
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: _topBar(app)),
                  SliverToBoxAdapter(child: _sourceBar(app)),
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
                      if (app.source == MediaSource.overview && continueItems.isNotEmpty) ...[
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        SliverToBoxAdapter(
                          child: ContentRail(
                            title: app.tr('continueWatching'),
                            children: [
                              for (var i = 0; i < continueItems.length; i++)
                                PosterCard(
                                  title: continueItems[i].ref.title,
                                  seed: continueItems[i].ref.key,
                                  imageUrl: continueItems[i].ref.posterUrl,
                                  subtitle: formatWatchProgress(
                                    continueItems[i].positionMs,
                                    continueItems[i].durationMs,
                                  ),
                                  autofocus: i == 0 && hero == null,
                                  onPressed: () => _openRef(continueItems[i].ref),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (app.source == MediaSource.overview && favoriteItems.isNotEmpty) ...[
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: ContentRail(
                            title: app.tr('favourite'),
                            children: [
                              for (final fav in favoriteItems)
                                PosterCard(
                                  title: fav.title,
                                  seed: fav.key,
                                  imageUrl: fav.posterUrl,
                                  subtitle: fav.accountLabel ?? fav.year,
                                  onPressed: () => _openRef(fav),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (app.source == MediaSource.overview) ...[
                        for (final entry in _moviesByGenre) ...[
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          SliverToBoxAdapter(
                            child: ContentRail(
                              title: entry.key,
                              children: [
                                for (var i = 0; i < entry.value.length; i++)
                                  PosterCard(
                                    title: entry.value[i].title,
                                    seed: entry.value[i].item.id,
                                    imageUrl: entry.value[i].poster,
                                    subtitle: entry.value[i].accountLabel ?? entry.value[i].year,
                                    autofocus: i == 0 &&
                                        hero == null &&
                                        entry.key == _moviesByGenre.first.key &&
                                        continueItems.isEmpty &&
                                        favoriteItems.isEmpty,
                                    onPressed: () => _openMovie(entry.value[i]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ] else ...[
                        // คลัง / ในโฟลเดอร์ — แกลเลอรีตาราง ไม่ใช้สไลด์ข้าง
                        if (_visibleFolders.isNotEmpty)
                          SliverToBoxAdapter(
                            child: ContentGallery(
                              title: app.tr('folders'),
                              itemCount: _visibleFolders.length,
                              maxCrossAxisExtent: 200,
                              childAspectRatio: 1.15,
                              itemBuilder: (context, i) {
                                final folder = _visibleFolders[i];
                                return PosterCard(
                                  title: folder.name,
                                  seed: folder.id,
                                  expand: true,
                                  imageAspectRatio: 16 / 9,
                                  subtitle: app.tr('openFolder'),
                                  autofocus: i == 0 && hero == null && _visibleMovies.isEmpty,
                                  onPressed: () => _openFolder(folder),
                                );
                              },
                            ),
                          ),
                        if (_visibleMovies.isNotEmpty)
                          SliverToBoxAdapter(
                            child: ContentGallery(
                              title: app.tr('allInFolder'),
                              itemCount: _visibleMovies.length,
                              itemBuilder: (context, i) {
                                final movie = _visibleMovies[i];
                                return PosterCard(
                                  title: movie.title,
                                  seed: movie.item.id,
                                  imageUrl: movie.poster,
                                  subtitle: movie.accountLabel ?? movie.year,
                                  expand: true,
                                  autofocus: i == 0 &&
                                      hero == null &&
                                      _visibleFolders.isEmpty,
                                  onPressed: () => _openMovie(movie),
                                );
                              },
                            ),
                          ),
                      ],
                      if (_visibleMovies.isEmpty &&
                          _visibleFolders.isEmpty &&
                          !(app.source == MediaSource.overview &&
                              (continueItems.isNotEmpty || favoriteItems.isNotEmpty)))
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _query.isNotEmpty
                                      ? app.tr('noSearchResults', {'query': _search.text.trim()})
                                      : app.source == MediaSource.overview
                                          ? app.tr('noOverview')
                                          : app.tr('noVideosInFolder'),
                                  style: bodyStyle(size: 20, color: themeMuted),
                                ),
                                if (_query.isEmpty) ...[
                                  const SizedBox(height: 20),
                                  if (app.source == MediaSource.local)
                                    TvButton(
                                      label: app.tr('chooseOtherFolder'),
                                      autofocus: true,
                                      onPressed: _pickLocalFolder,
                                    ),
                                  if (app.source == MediaSource.overview)
                                    TvButton(
                                      label: app.tr('profiles'),
                                      autofocus: true,
                                      onPressed: _openProfiles,
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 56)),
                    ],
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _sourceBar(AppState app) {
    final overviewOn = app.source == MediaSource.overview;
    final localOn = app.source == MediaSource.local;
    final activeId = app.session?.id;
    final canGoUp = (_folders?.length ?? 0) > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 2, 40, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TvButton(
                  label: app.tr('all'),
                  filled: overviewOn,
                  icon: Icons.apps_rounded,
                  onPressed: _useOverview,
                ),
                const SizedBox(width: 12),
                TvButton(
                  label: app.tr('thisDevice'),
                  filled: localOn,
                  icon: Icons.phone_android_rounded,
                  onPressed: _useLocal,
                ),
                for (final account in app.accounts) ...[
                  const SizedBox(width: 12),
                  TvButton(
                    label: account.title,
                    filled: app.source == MediaSource.oneDrive && account.id == activeId,
                    icon: Icons.cloud_outlined,
                    onPressed: () => _useOneDriveAccount(account),
                  ),
                ],
                if (localOn) ...[
                  const SizedBox(width: 12),
                  TvButton(label: app.tr('changeFolder'), filled: false, onPressed: _pickLocalFolder),
                ],
              ],
            ),
          ),
          if (canGoUp) ...[
            const SizedBox(height: 12),
            TvFocus(
              onPressed: _goUp,
              borderRadius: 8,
              scale: 1.04,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back_rounded, size: 22, color: themeText),
                    const SizedBox(width: 10),
                    Text(
                      app.tr('goBack'),
                      style: bodyStyle(size: 18, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBar(AppState app) {
    final crumbs = _folders ?? const [];
    final path = crumbs.map((c) => c.name).join('  /  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 6),
      child: Row(
        children: [
          Text('Niceflix', style: brandStyle(size: 30, color: themeAccent)),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle(size: 16, color: themeMuted),
            ),
          ),
          SizedBox(
            width: 220,
            height: 50,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  if (_searchFocus.hasFocus || _query.isNotEmpty) {
                    _search.clear();
                    _searchFocus.unfocus();
                    setState(() {});
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: bodyStyle(size: 15),
              cursorColor: themeAccent,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: app.tr('searchHint'),
                hintStyle: bodyStyle(size: 15, color: themeFaint),
                prefixIcon: const Icon(Icons.search_rounded, size: 22, color: themeMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 50),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: app.tr('clearSearch'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 50),
                        onPressed: () {
                          _search.clear();
                          _searchFocus.requestFocus();
                        },
                        icon: const Icon(Icons.close_rounded, size: 20, color: themeMuted),
                      ),
                filled: true,
                fillColor: themePanel,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: themeFocus, width: 2),
                ),
              ),
            ),
            ),
          ),
          const SizedBox(width: 12),
          TvButton(
            label: app.tr('refresh'),
            filled: false,
            icon: Icons.refresh_rounded,
            iconOnly: true,
            onPressed: _load,
          ),
          const SizedBox(width: 12),
          TvButton(
            label: app.tr('profiles'),
            filled: true,
            icon: Icons.person_outline_rounded,
            onPressed: _openProfiles,
          ),
        ],
      ),
    );
  }

  Widget _heroBlock(LibraryMovie? hero) {
    if (hero == null) {
      return const SizedBox(height: 24);
    }
    final art = hero.art;
    // Keep hero under half the screen so rails/gallery stay visible on TV.
    final height = MediaQuery.sizeOf(context).height * 0.42;
    return SizedBox(
      width: double.infinity,
      height: height.clamp(280.0, 480.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: RemoteArt(
                key: ValueKey(art),
                url: art,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
              ),
            )
          else
            const ColoredBox(color: themeRaised),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xF2050508),
                  Color(0x99050508),
                  Color(0x22050508),
                  Color(0x00050508),
                ],
                stops: [0, 0.28, 0.62, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66050508),
                  Color(0x00050508),
                  Color(0xE6050508),
                  themeBg,
                ],
                stops: [0, 0.35, 0.82, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 24, 48, 28),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('FEATURED', style: bodyStyle(size: 12, weight: FontWeight.w700, color: themeAccentSoft)),
                    const SizedBox(height: 8),
                    Text(hero.title, style: displayStyle(size: 40)),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (hero.year != null) hero.year!,
                        if (hero.item.name.toLowerCase().endsWith('.mkv')) 'MKV',
                        if (hero.item.isLocal) 'Local',
                        if (hero.match?.rating != null) '★ ${hero.match!.rating!.toStringAsFixed(1)}',
                        formatBytes(hero.item.size),
                      ].whereType<String>().join('  ·  '),
                      style: bodyStyle(size: 14, color: themeMuted),
                    ),
                    if (hero.overview != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        hero.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(size: 15, color: const Color(0xFFD0D0D6)),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TvButton(
                          label: () {
                            final progress = AppScope.of(context).progressFor(hero.libraryRef?.key ?? '');
                            if (progress == null) return 'เล่น';
                            return 'เล่นต่อ · ${formatWatchProgress(progress.positionMs, progress.durationMs)}';
                          }(),
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
            ),
          ),
        ],
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
            TvButton(
              label: AppScope.of(context).tr('tryAgain'),
              autofocus: true,
              onPressed: _load,
            ),
            const SizedBox(height: 12),
            TvButton(
              label: AppScope.of(context).tr('pickLocalFolder'),
              filled: false,
              onPressed: _pickLocalFolder,
            ),
            const SizedBox(height: 12),
            TvButton(
              label: AppScope.of(context).tr('profiles'),
              filled: false,
              icon: Icons.person_outline_rounded,
              onPressed: _openProfiles,
            ),
          ],
        ),
      ),
    );
  }
}

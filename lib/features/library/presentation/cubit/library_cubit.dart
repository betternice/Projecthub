import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../metadata/domain/entities/media.dart';
import '../../../metadata/domain/usecases/metadata_usecases.dart';
import '../../../settings/domain/usecases/settings_usecases.dart';
import '../../domain/entities/drive_item.dart';
import '../../domain/usecases/library_usecases.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({
    required ListFolder listFolder,
    required LoadFolderTrail loadFolderTrail,
    required SaveFolderTrail saveFolderTrail,
    required LookupMedia lookupMedia,
    required GetTmdbApiKey getTmdbApiKey,
    required SaveTmdbApiKey saveTmdbApiKey,
  }) : _listFolder = listFolder,
       _loadFolderTrail = loadFolderTrail,
       _saveFolderTrail = saveFolderTrail,
       _lookupMedia = lookupMedia,
       _getTmdbApiKey = getTmdbApiKey,
       _saveTmdbApiKey = saveTmdbApiKey,
       super(const LibraryState());

  final ListFolder _listFolder;
  final LoadFolderTrail _loadFolderTrail;
  final SaveFolderTrail _saveFolderTrail;
  final LookupMedia _lookupMedia;
  final GetTmdbApiKey _getTmdbApiKey;
  final SaveTmdbApiKey _saveTmdbApiKey;

  static const _metadataWorkers = 3;

  /// เพิ่มทุกครั้งที่เปลี่ยนโฟลเดอร์ ผลของ request เก่าที่กลับมาช้าจะถูกทิ้ง
  int _folderRun = 0;

  /// เพิ่มทุกครั้งที่เริ่มค้น metadata ใหม่ เช่นเปลี่ยน TMDB key
  int _metadataRun = 0;

  Future<void> start() async {
    final (trail, tmdbApiKey) = await (_loadFolderTrail(), _getTmdbApiKey()).wait;
    if (isClosed) return;
    emit(state.copyWith(trail: trail, tmdbApiKey: () => tmdbApiKey));
    await _load(clearItems: true);
  }

  Future<void> openFolder(DriveItem folder) => _goTo([...state.trail, FolderCrumb(id: folder.id, name: folder.name)]);

  Future<void> goUp() async {
    if (state.parent == null) return;
    await _goTo(state.trail.sublist(0, state.trail.length - 1));
  }

  Future<void> refresh() => _load(clearItems: false);

  Future<void> updateTmdbApiKey(String value) async {
    final saved = await _saveTmdbApiKey(value);
    if (isClosed || saved == state.tmdbApiKey) return;
    emit(state.copyWith(tmdbApiKey: () => saved, matches: const {}));
    await _resolveMetadata(state.videos);
  }

  Future<void> _goTo(List<FolderCrumb> trail) async {
    emit(state.copyWith(trail: trail));
    await _saveFolderTrail(trail);
    await _load(clearItems: true);
  }

  Future<void> _load({required bool clearItems}) async {
    final folder = state.current;
    if (folder == null) return;
    final run = ++_folderRun;
    if (clearItems) _metadataRun++;
    emit(
      state.copyWith(
        loading: true,
        errorMessage: () => null,
        folders: clearItems ? const [] : null,
        videos: clearItems ? const [] : null,
        matches: clearItems ? const {} : null,
      ),
    );

    final List<DriveItem> items;
    try {
      items = await _listFolder(folder.id);
    } on Failure catch (failure) {
      if (!isClosed && run == _folderRun) emit(state.copyWith(loading: false, errorMessage: () => failure.message));
      return;
    }
    if (isClosed || run != _folderRun) return;

    int byName(DriveItem a, DriveItem b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final videos = items.where((item) => item.isVideo).toList();
    final ids = {for (final video in videos) video.id};
    emit(
      state.copyWith(
        loading: false,
        folders: items.where((item) => item.isFolder).toList()..sort(byName),
        videos: videos,
        // ตอนดึงรีเฟรชเก็บผลเดิมของไฟล์ที่ยังอยู่ ไม่ต้องค้นซ้ำ
        matches: {
          for (final entry in state.matches.entries)
            if (ids.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
    await _resolveMetadata(videos.where((video) => !state.matches.containsKey(video.id)).toList());
  }

  Future<void> _resolveMetadata(List<DriveItem> queue) async {
    if (queue.isEmpty) return;
    final run = ++_metadataRun;
    final tmdbApiKey = state.tmdbApiKey;
    var next = 0;

    Future<void> worker() async {
      while (next < queue.length) {
        final item = queue[next++];
        MediaMatch? match;
        try {
          match = await _lookupMedia(item.name, tmdbApiKey: tmdbApiKey);
        } on Failure {
          // ปกและเรื่องย่อเป็นของเสริม ถ้าหาไม่ได้ให้แสดงปกสำรองจากชื่อไฟล์แทน
          match = null;
        }
        if (isClosed || run != _metadataRun) return;
        emit(state.copyWith(matches: {...state.matches, item.id: match}));
      }
    }

    await Future.wait(List.generate(_metadataWorkers, (_) => worker()));
  }
}

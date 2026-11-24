import 'package:equatable/equatable.dart';

import '../../../../core/utils/media_title.dart';
import '../../../metadata/domain/entities/media.dart';
import '../../domain/entities/drive_item.dart';

class LibraryMovie extends Equatable {
  const LibraryMovie({required this.item, required this.match, required this.parsed});

  final DriveItem item;
  final MediaMatch? match;
  final ParsedTitle parsed;

  String get title => match?.title.isNotEmpty == true ? match!.title : parsed.title;

  String? get year => match?.year ?? parsed.year;

  String? get posterUrl => match?.posterUrl ?? item.thumbnailUrl;

  @override
  List<Object?> get props => [item, match, parsed];
}

class LibraryState extends Equatable {
  const LibraryState({
    this.trail = const [],
    this.folders = const [],
    this.videos = const [],
    this.matches = const {},
    this.loading = true,
    this.errorMessage,
    this.tmdbApiKey,
  });

  final List<FolderCrumb> trail;
  final List<DriveItem> folders;
  final List<DriveItem> videos;

  /// มี key เมื่อค้น metadata ของไฟล์นั้นเสร็จแล้ว ค่า null คือหาไม่เจอ
  final Map<String, MediaMatch?> matches;
  final bool loading;
  final String? errorMessage;
  final String? tmdbApiKey;

  FolderCrumb? get current => trail.isEmpty ? null : trail.last;

  FolderCrumb? get parent => trail.length > 1 ? trail[trail.length - 2] : null;

  String get screenTitle {
    final folder = current;
    return folder == null || folder.isRoot ? 'Movies' : folder.name;
  }

  /// เรียงตามชื่อที่แยกจากไฟล์ ไม่ใช่ชื่อจาก metadata เพื่อไม่ให้ grid สลับตำแหน่งระหว่างโหลด
  List<LibraryMovie> get movies {
    final list = [
      for (final item in videos) LibraryMovie(item: item, match: matches[item.id], parsed: parseMediaTitle(item.name)),
    ];
    list.sort((a, b) => a.parsed.title.toLowerCase().compareTo(b.parsed.title.toLowerCase()));
    return list;
  }

  List<LibraryMovie> get featured => movies.where((movie) => movie.match?.backdropUrl != null).take(8).toList();

  LibraryState copyWith({
    List<FolderCrumb>? trail,
    List<DriveItem>? folders,
    List<DriveItem>? videos,
    Map<String, MediaMatch?>? matches,
    bool? loading,
    String? Function()? errorMessage,
    String? Function()? tmdbApiKey,
  }) {
    return LibraryState(
      trail: trail ?? this.trail,
      folders: folders ?? this.folders,
      videos: videos ?? this.videos,
      matches: matches ?? this.matches,
      loading: loading ?? this.loading,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      tmdbApiKey: tmdbApiKey != null ? tmdbApiKey() : this.tmdbApiKey,
    );
  }

  @override
  List<Object?> get props => [trail, folders, videos, matches, loading, errorMessage, tmdbApiKey];
}

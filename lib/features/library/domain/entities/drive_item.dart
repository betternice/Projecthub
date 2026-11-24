import 'package:equatable/equatable.dart';

class DriveItem extends Equatable {
  const DriveItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.size,
    this.mimeType,
    this.durationMs,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final bool isFolder;
  final int? size;
  final String? mimeType;
  final int? durationMs;
  final String? thumbnailUrl;

  static final _videoExtension = RegExp(r'\.(mp4|m4v|mov|mkv|avi|webm|wmv|mpg|mpeg)$', caseSensitive: false);

  bool get isVideo {
    if (isFolder) return false;
    if (mimeType?.startsWith('video/') ?? false) return true;
    return _videoExtension.hasMatch(name);
  }

  @override
  List<Object?> get props => [id, name, isFolder, size, mimeType, durationMs, thumbnailUrl];
}

class FolderCrumb extends Equatable {
  const FolderCrumb({required this.id, required this.name});

  static const root = FolderCrumb(id: 'root', name: 'OneDrive');

  final String id;
  final String name;

  bool get isRoot => id == root.id;

  @override
  List<Object?> get props => [id, name];
}

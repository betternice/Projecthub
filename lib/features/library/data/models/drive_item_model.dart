import '../../domain/entities/drive_item.dart';

/// map `driveItem` ของ Microsoft Graph ที่ขอมาพร้อม `$expand=thumbnails`
abstract final class DriveItemModel {
  static DriveItem? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;

    final file = json['file'];
    final video = json['video'];
    return DriveItem(
      id: id,
      name: name,
      isFolder: json['folder'] is Map,
      size: (json['size'] as num?)?.toInt(),
      mimeType: file is Map ? file['mimeType'] as String? : null,
      durationMs: video is Map ? (video['duration'] as num?)?.toInt() : null,
      thumbnailUrl: _thumbnail(json['thumbnails']),
    );
  }

  static String? _thumbnail(Object? thumbnails) {
    if (thumbnails is! List || thumbnails.isEmpty) return null;
    final first = thumbnails.first;
    if (first is! Map) return null;
    for (final size in const ['large', 'medium']) {
      final entry = first[size];
      if (entry is Map && entry['url'] is String) return entry['url'] as String;
    }
    return null;
  }
}

abstract final class FolderCrumbModel {
  static FolderCrumb? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return FolderCrumb(id: id, name: name);
  }

  static Map<String, String> toJson(FolderCrumb crumb) => {'id': crumb.id, 'name': crumb.name};
}

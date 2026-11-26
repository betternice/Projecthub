import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';

const _videoExt = {
  '.mp4',
  '.m4v',
  '.mov',
  '.mkv',
  '.avi',
  '.webm',
  '.wmv',
  '.mpg',
  '.mpeg',
};

Future<bool> ensureLocalLibraryAccess() async {
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  final videos = await Permission.videos.request();
  if (videos.isGranted) return true;
  final storage = await Permission.storage.request();
  return storage.isGranted || storage.isLimited;
}

Future<String?> pickLocalLibraryFolder() async {
  if (kIsWeb) return null;
  await ensureLocalLibraryAccess();
  return FilePicker.getDirectoryPath(dialogTitle: 'เลือกโฟลเดอร์หนัง');
}

Future<List<String>> candidateLocalRoots() async {
  if (kIsWeb) return const [];
  final roots = <String>[];
  try {
    final external = await getExternalStorageDirectory();
    var cursor = external;
    for (var i = 0; i < 6 && cursor != null; i++) {
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }
    final base = cursor?.path;
    if (base != null) {
      for (final name in ['Movies', 'Download', 'Downloads', 'Video', 'Videos']) {
        roots.add('$base/$name');
      }
    }
  } catch (_) {}
  roots.addAll(const [
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/sdcard/Movies',
    '/sdcard/Download',
  ]);
  return roots.toSet().toList();
}

Future<String?> detectDefaultLocalRoot() async {
  if (kIsWeb) return null;
  await ensureLocalLibraryAccess();
  for (final path in await candidateLocalRoots()) {
    final dir = Directory(path);
    if (await dir.exists()) return path;
  }
  return null;
}

bool _isVideoName(String name) {
  final lower = name.toLowerCase();
  return _videoExt.any(lower.endsWith);
}

DriveItem _fileItem(FileSystemEntity entity) {
  final file = File(entity.path);
  int? size;
  try {
    size = file.lengthSync();
  } catch (_) {}
  final name = entity.uri.pathSegments.isEmpty
      ? entity.path
      : entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
  return DriveItem(
    id: 'local:${entity.path}',
    name: name,
    size: size,
    isFolder: entity is Directory,
    localPath: entity.path,
  );
}

Future<List<DriveItem>> listLocalChildren(String folderPath) async {
  if (kIsWeb) {
    throw Exception('พรีวิวบนเว็บยังอ่านไฟล์ในเครื่องไม่ได้ — ใช้บน Android TV');
  }
  final dir = Directory(folderPath);
  if (!await dir.exists()) {
    throw Exception('ไม่พบโฟลเดอร์นี้บนเครื่อง');
  }

  final items = <DriveItem>[];
  await for (final entity in dir.list(followLinks: false)) {
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path
        : entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.startsWith('.')) continue;
    if (entity is Directory) {
      items.add(_fileItem(entity));
    } else if (entity is File && _isVideoName(name)) {
      items.add(_fileItem(entity));
    }
  }

  items.sort((a, b) {
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return items;
}

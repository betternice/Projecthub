import '../format.dart';
import '../local/library.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';

LibraryRef refFromItem(
  DriveItem item, {
  String? accountId,
  String? accountLabel,
}) {
  final parsed = presentTitle(item.name);
  return LibraryRef(
    key: libraryKey(accountId: accountId, itemId: item.id, localPath: item.localPath),
    itemId: item.id,
    name: item.name,
    title: parsed.title,
    accountId: accountId,
    accountLabel: accountLabel,
    localPath: item.localPath,
    size: item.size,
    posterUrl: item.thumbLarge ?? item.thumbMedium,
    year: parsed.year,
  );
}

Future<List<LibraryRef>> collectOverviewLibrary(AppState app) async {
  final collected = <LibraryRef>[];
  final seen = <String>{};

  void addAll(Iterable<LibraryRef> refs) {
    for (final ref in refs) {
      if (seen.add(ref.key)) collected.add(ref);
    }
  }

  if (app.localRootPath != null && app.localRootPath!.isNotEmpty) {
    try {
      addAll(await _collectLocal(app.localRootPath!));
    } catch (_) {}
  }

  for (final account in app.accounts) {
    try {
      final token = await app.getToken(accountId: account.id);
      addAll(await _collectOneDrive(token, account));
    } catch (_) {}
  }

  collected.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return collected;
}

Future<List<LibraryRef>> _collectLocal(String root) async {
  final out = <LibraryRef>[];
  final top = await listLocalChildren(root);
  for (final item in top) {
    if (isVideoFile(item)) {
      out.add(refFromItem(item, accountLabel: 'เครื่องนี้'));
    } else if (item.isFolder && item.localPath != null) {
      try {
        final children = await listLocalChildren(item.localPath!);
        for (final child in children.where(isVideoFile)) {
          out.add(refFromItem(child, accountLabel: 'เครื่องนี้'));
        }
      } catch (_) {}
    }
  }
  return out;
}

Future<List<LibraryRef>> _collectOneDrive(String token, Session account) async {
  final out = <LibraryRef>[];
  final allowed = account.hasLibraryFilter ? account.libraryFolderIds : null;
  final top = await listChildren(token, 'root');
  for (final item in top) {
    if (isVideoFile(item)) {
      // ถ้ามีตัวกรองโฟลเดอร์ — ไม่นับวิดีโอบน root (อยู่นอกโฟลเดอร์ที่เลือก)
      if (allowed != null) continue;
      out.add(refFromItem(item, accountId: account.id, accountLabel: account.title));
    } else if (item.isFolder) {
      if (allowed != null && !allowed.contains(item.id)) continue;
      try {
        final children = await listChildren(token, item.id);
        for (final child in children.where(isVideoFile)) {
          out.add(refFromItem(child, accountId: account.id, accountLabel: account.title));
        }
      } catch (_) {}
    }
  }
  return out;
}

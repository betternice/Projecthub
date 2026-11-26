import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Result of a disk lookup: [cached] true means we already resolved this title.
class CachedLookup {
  const CachedLookup(this.match);
  final MediaMatch? match;
}

/// Disk cache for TMDB/Wiki metadata — survives app/device restart (Android TV).
class MetadataDiskCache {
  MetadataDiskCache._();
  static final MetadataDiskCache instance = MetadataDiskCache._();

  static const _fileName = 'metadata_cache_v1.json';
  static const _positiveTtl = Duration(days: 90);
  static const _negativeTtl = Duration(days: 7);
  static const _maxLookups = 2000;
  static const _maxDetails = 800;

  final Map<String, _LookupEntry> _lookups = {};
  final Map<String, _DetailEntry> _details = {};
  /// Manual picks keyed by library item key (survives restart).
  final Map<String, _LookupEntry> _overrides = {};
  Future<void>? _loading;
  bool _ready = false;
  Timer? _saveTimer;
  bool _dirty = false;
  static const _maxOverrides = 500;

  Future<void> ensureLoaded() {
    if (_ready || kIsWeb) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) {
        _ready = true;
        return;
      }
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final lookups = json['lookups'];
      if (lookups is Map<String, dynamic>) {
        for (final entry in lookups.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;
          if (!value.containsKey('match')) continue;
          final matchRaw = value['match'];
          MediaMatch? match;
          if (matchRaw is Map<String, dynamic>) {
            match = MediaMatch.fromJson(matchRaw);
          } else if (matchRaw != null) {
            continue;
          }
          _lookups[entry.key] = _LookupEntry(
            savedAt: value['savedAt'] as int? ?? 0,
            match: match,
          );
        }
      }
      final details = json['details'];
      if (details is Map<String, dynamic>) {
        for (final entry in details.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;
          final detailRaw = value['detail'];
          if (detailRaw is! Map<String, dynamic>) continue;
          _details[entry.key] = _DetailEntry(
            savedAt: value['savedAt'] as int? ?? 0,
            detail: MediaDetail.fromJson(detailRaw),
          );
        }
      }
      final overrides = json['overrides'];
      if (overrides is Map<String, dynamic>) {
        for (final entry in overrides.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;
          final matchRaw = value['match'];
          if (matchRaw is! Map<String, dynamic>) continue;
          _overrides[entry.key] = _LookupEntry(
            savedAt: value['savedAt'] as int? ?? 0,
            match: MediaMatch.fromJson(matchRaw),
          );
        }
      }
    } catch (_) {
      _lookups.clear();
      _details.clear();
      _overrides.clear();
    } finally {
      _ready = true;
    }
  }

  Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  String lookupKey(String title, String? year) =>
      '${title.trim().toLowerCase()}|${year ?? ''}';

  String detailKey(MediaMatch match) {
    if (match.tmdbId != null) return 'tmdb:${match.kind}:${match.tmdbId}';
    if (match.wikibaseId != null) return 'wiki:${match.wikibaseId}';
    return 'title:${lookupKey(match.title, match.year)}';
  }

  Future<CachedLookup?> readLookup(String title, String? year) async {
    await ensureLoaded();
    final key = lookupKey(title, year);
    final entry = _lookups[key];
    if (entry == null) return null;
    final ttl = entry.match == null ? _negativeTtl : _positiveTtl;
    if (_expired(entry.savedAt, ttl)) {
      _lookups.remove(key);
      _scheduleSave();
      return null;
    }
    return CachedLookup(entry.match);
  }

  Future<void> writeLookup(String title, String? year, MediaMatch? match) async {
    await ensureLoaded();
    _lookups[lookupKey(title, year)] = _LookupEntry(
      savedAt: DateTime.now().millisecondsSinceEpoch,
      match: match,
    );
    _trimLookups();
    _scheduleSave();
  }

  Future<MediaDetail?> readDetail(MediaMatch match) async {
    await ensureLoaded();
    final key = detailKey(match);
    final entry = _details[key];
    if (entry == null) return null;
    if (_expired(entry.savedAt, _positiveTtl)) {
      _details.remove(key);
      _scheduleSave();
      return null;
    }
    return entry.detail;
  }

  Future<void> writeDetail(MediaDetail detail) async {
    await ensureLoaded();
    _details[detailKey(detail.match)] = _DetailEntry(
      savedAt: DateTime.now().millisecondsSinceEpoch,
      detail: detail,
    );
    _trimDetails();
    _scheduleSave();
  }

  Future<MediaMatch?> readOverride(String libraryKey) async {
    await ensureLoaded();
    final entry = _overrides[libraryKey];
    if (entry == null) return null;
    if (_expired(entry.savedAt, _positiveTtl)) {
      _overrides.remove(libraryKey);
      _scheduleSave();
      return null;
    }
    return entry.match;
  }

  Future<void> writeOverride(String libraryKey, MediaMatch match) async {
    await ensureLoaded();
    _overrides[libraryKey] = _LookupEntry(
      savedAt: DateTime.now().millisecondsSinceEpoch,
      match: match,
    );
    if (_overrides.length > _maxOverrides) {
      final sorted = _overrides.entries.toList()
        ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
      for (final e in sorted.take(_overrides.length - _maxOverrides)) {
        _overrides.remove(e.key);
      }
    }
    _scheduleSave();
  }

  /// Clears metadata from memory and disk.
  Future<void> clear() async {
    _saveTimer?.cancel();
    _lookups.clear();
    _details.clear();
    _overrides.clear();
    _dirty = false;
    _ready = true;
    _loading = null;
    if (kIsWeb) return;
    try {
      final file = await _file();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  bool _expired(int savedAt, Duration ttl) {
    return DateTime.now().millisecondsSinceEpoch - savedAt > ttl.inMilliseconds;
  }

  void _trimLookups() {
    if (_lookups.length <= _maxLookups) return;
    final sorted = _lookups.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    for (final e in sorted.take(_lookups.length - _maxLookups)) {
      _lookups.remove(e.key);
    }
  }

  void _trimDetails() {
    if (_details.length <= _maxDetails) return;
    final sorted = _details.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    for (final e in sorted.take(_details.length - _maxDetails)) {
      _details.remove(e.key);
    }
  }

  void _scheduleSave() {
    if (kIsWeb) return;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (!_dirty || kIsWeb) return;
    _dirty = false;
    try {
      final file = await _file();
      if (file == null) return;
      final lookups = <String, dynamic>{};
      for (final e in _lookups.entries) {
        lookups[e.key] = {
          'savedAt': e.value.savedAt,
          'match': e.value.match?.toJson(),
        };
      }
      final details = <String, dynamic>{};
      for (final e in _details.entries) {
        details[e.key] = {
          'savedAt': e.value.savedAt,
          'detail': e.value.detail.toJson(),
        };
      }
      final overrides = <String, dynamic>{};
      for (final e in _overrides.entries) {
        final match = e.value.match;
        if (match == null) continue;
        overrides[e.key] = {
          'savedAt': e.value.savedAt,
          'match': match.toJson(),
        };
      }
      await file.writeAsString(jsonEncode({
        'lookups': lookups,
        'details': details,
        'overrides': overrides,
      }));
    } catch (_) {}
  }
}

class _LookupEntry {
  _LookupEntry({required this.savedAt, required this.match});
  final int savedAt;
  final MediaMatch? match;
}

class _DetailEntry {
  _DetailEntry({required this.savedAt, required this.detail});
  final int savedAt;
  final MediaDetail detail;
}

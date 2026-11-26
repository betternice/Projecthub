import 'dart:convert';

import 'package:http/http.dart' as http;

import '../format.dart';
import '../models.dart';
import 'cache.dart';
import 'wiki.dart';

final _disk = MetadataDiskCache.instance;

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
}

final _cache = <String, MediaMatch?>{};
final _lookupCache = <String, MediaMatch?>{};

void clearMetadataMemoryCache() {
  _cache.clear();
  _lookupCache.clear();
}

String? _image(String? path, String size) => path == null || path.isEmpty ? null : 'https://image.tmdb.org/t/p/$size$path';

/// TMDB genre ids → Thai labels for overview rails.
const _genreNamesTh = <int, String>{
  28: 'แอ็กชัน',
  12: 'ผจญภัย',
  16: 'แอนิเมชัน',
  35: 'ตลก',
  80: 'อาชญากรรม',
  99: 'สารคดี',
  18: 'ดราม่า',
  10751: 'ครอบครัว',
  14: 'แฟนตาซี',
  36: 'ประวัติศาสตร์',
  27: 'สยองขวัญ',
  10402: 'ดนตรี',
  9648: 'ลึกลับ',
  10749: 'โรแมนติก',
  878: 'ไซไฟ',
  10770: 'ทีวีมูวี',
  53: 'ระทึกขวัญ',
  10752: 'สงคราม',
  37: 'ตะวันตก',
  10759: 'แอ็กชันและผจญภัย',
  10762: 'เด็ก',
  10763: 'ข่าว',
  10764: 'เรียลลิตี้',
  10765: 'ไซไฟและแฟนตาซี',
  10766: 'ซบオペラ',
  10767: 'ทอล์ค',
  10768: 'สงครามและการเมือง',
};

List<String> _genresFromIds(List<dynamic>? ids) {
  if (ids == null || ids.isEmpty) return const [];
  final names = <String>[];
  for (final id in ids) {
    final key = id is int ? id : int.tryParse('$id');
    final name = key == null ? null : _genreNamesTh[key];
    if (name != null && !names.contains(name)) names.add(name);
  }
  return names;
}

MediaMatch _toMatch(String kind, Map<String, dynamic> result) {
  final date = kind == 'movie' ? result['release_date'] as String? : result['first_air_date'] as String?;
  final vote = result['vote_average'];
  return MediaMatch(
    tmdbId: result['id'] as int?,
    wikibaseId: null,
    kind: kind,
    title: result['title'] as String? ?? result['name'] as String? ?? '',
    overview: (result['overview'] as String?)?.trim().isEmpty == true ? null : (result['overview'] as String?)?.trim(),
    year: date != null && date.length >= 4 ? date.substring(0, 4) : null,
    posterUrl: _image(result['poster_path'] as String?, 'w500'),
    backdropUrl: _image(result['backdrop_path'] as String?, 'w780'),
    rating: vote is num && vote != 0 ? (vote * 10).round() / 10 : null,
    genres: _genresFromIds(result['genre_ids'] as List<dynamic>?),
  );
}

Future<List<MediaMatch>> _searchKindList(
  String apiKey,
  String kind,
  String title,
  String? year,
  String language,
) async {
  final params = <String, String>{
    'api_key': apiKey,
    'query': title,
    'language': language,
    'include_adult': 'false',
  };
  if (year != null && year.isNotEmpty) {
    params[kind == 'movie' ? 'year' : 'first_air_date_year'] = year;
  }
  final response = await http.get(Uri.https('api.themoviedb.org', '/3/search/$kind', params));
  if (response.statusCode == 401) throw TmdbException('ใช้ TMDB API key นี้ไม่ได้');
  if (response.statusCode != 200) return const [];
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final results = (body['results'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
  results.sort((a, b) => ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));
  return results.map((r) => _toMatch(kind, r)).toList();
}

Future<MediaMatch?> _searchKind(String apiKey, String kind, String title, String? year, String language) async {
  final list = await _searchKindList(apiKey, kind, title, year, language);
  return list.isEmpty ? null : list.first;
}

/// Search TMDB for a picker UI — supports optional year filter.
Future<List<MediaMatch>> searchMediaCandidates(
  String apiKey, {
  required String query,
  String? year,
  int limit = 24,
}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];
  final yearFilter = year?.trim();
  final yearOrNull = yearFilter == null || yearFilter.isEmpty ? null : yearFilter;

  final seen = <String>{};
  final out = <MediaMatch>[];

  void addAll(Iterable<MediaMatch> items) {
    for (final match in items) {
      final key = '${match.kind}:${match.tmdbId ?? match.title}|${match.year ?? ''}';
      if (!seen.add(key)) continue;
      out.add(match);
      if (out.length >= limit) return;
    }
  }

  addAll(await _searchKindList(apiKey, 'movie', trimmed, yearOrNull, 'th-TH'));
  if (out.length < limit) addAll(await _searchKindList(apiKey, 'tv', trimmed, yearOrNull, 'th-TH'));
  if (out.length < 6) {
    addAll(await _searchKindList(apiKey, 'movie', trimmed, yearOrNull, 'en-US'));
    addAll(await _searchKindList(apiKey, 'tv', trimmed, yearOrNull, 'en-US'));
  }
  // ถ้าใส่ปีแล้วผลน้อย — ค้นเพิ่มโดยไม่ล็อกปี
  if (yearOrNull != null && out.length < 4) {
    addAll(await _searchKindList(apiKey, 'movie', trimmed, null, 'th-TH'));
    addAll(await _searchKindList(apiKey, 'tv', trimmed, null, 'th-TH'));
  }
  return out;
}

/// Persist a user-picked match for this library item and title cache.
Future<void> applyManualMatch({
  required String libraryKey,
  required String filename,
  required MediaMatch match,
}) async {
  final parsed = presentTitle(filename);
  await _disk.writeOverride(libraryKey, match);
  await _disk.writeLookup(parsed.title, parsed.year, match);
  final cacheKey = '${parsed.title}|${parsed.year ?? ''}';
  _cache[cacheKey] = match;
  // Drop mem entries so next lookup picks override / new lookup
  _lookupCache.removeWhere((k, _) => k.endsWith(cacheKey) || k.contains('|${parsed.title}|'));
}

Future<MediaMatch?> matchTitle(String apiKey, String filename) async {
  final parsed = presentTitle(filename);
  if (parsed.title.isEmpty) return null;
  final cacheKey = '${parsed.title}|${parsed.year ?? ''}';
  if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

  final match = await _searchKind(apiKey, 'movie', parsed.title, parsed.year, 'th-TH') ??
      await _searchKind(apiKey, 'movie', parsed.title, null, 'th-TH') ??
      await _searchKind(apiKey, 'tv', parsed.title, parsed.year, 'th-TH') ??
      await _searchKind(apiKey, 'movie', parsed.title, parsed.year, 'en-US') ??
      await _searchKind(apiKey, 'tv', parsed.title, parsed.year, 'en-US');
  _cache[cacheKey] = match;
  return match;
}

Future<MediaDetail> fetchMediaDetail(String apiKey, MediaMatch match) async {
  if (match.tmdbId == null) {
    return MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
  }
  final path = match.kind == 'movie' ? 'movie' : 'tv';
  final response = await http.get(Uri.https('api.themoviedb.org', '/3/$path/${match.tmdbId}', {
    'api_key': apiKey,
    'language': 'th-TH',
    'append_to_response': 'credits',
  }));
  if (response.statusCode != 200) {
    return MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final credits = body['credits'] as Map<String, dynamic>?;
  final cast = ((credits?['cast'] as List<dynamic>?) ?? [])
      .whereType<Map<String, dynamic>>()
      .take(12)
      .map((person) => CastMember(
            name: person['name'] as String? ?? '',
            character: person['character'] as String?,
            profileUrl: _image(person['profile_path'] as String?, 'w185'),
          ))
      .where((person) => person.name.isNotEmpty)
      .toList();
  String? director;
  for (final person in (credits?['crew'] as List<dynamic>?) ?? const []) {
    if (person is Map && person['job'] == 'Director') {
      director = person['name'] as String?;
      break;
    }
  }
  final genres = ((body['genres'] as List<dynamic>?) ?? [])
      .whereType<Map<String, dynamic>>()
      .map((genre) => genre['name'] as String?)
      .whereType<String>()
      .take(2)
      .toList();
  final overview = (body['overview'] as String?)?.trim();
  final episodeTimes = body['episode_run_time'] as List<dynamic>?;
  final runtime = match.kind == 'movie'
      ? body['runtime'] as int?
      : (episodeTimes != null && episodeTimes.isNotEmpty ? episodeTimes.first as int? : null);
  return MediaDetail(
    match: MediaMatch(
      tmdbId: match.tmdbId,
      wikibaseId: match.wikibaseId,
      kind: match.kind,
      title: match.title,
      overview: overview == null || overview.isEmpty ? match.overview : overview,
      year: match.year,
      posterUrl: match.posterUrl,
      backdropUrl: match.backdropUrl,
      rating: match.rating,
      genres: genres.isNotEmpty ? genres : match.genres,
    ),
    runtime: runtime,
    cast: cast,
    genres: genres.isNotEmpty ? genres : match.genres,
    director: director,
  );
}

Future<MediaMatch?> lookupMedia(
  String filename,
  String? apiKey, {
  String? libraryKey,
}) async {
  final parsed = presentTitle(filename);
  final memKey = '${libraryKey ?? ''}|${apiKey ?? ''}|${parsed.title}|${parsed.year ?? ''}';
  if (_lookupCache.containsKey(memKey)) return _lookupCache[memKey];

  if (libraryKey != null && libraryKey.isNotEmpty) {
    final override = await _disk.readOverride(libraryKey);
    if (override != null) {
      _lookupCache[memKey] = override;
      return override;
    }
  }

  final diskHit = await _disk.readLookup(parsed.title, parsed.year);
  if (diskHit != null) {
    _lookupCache[memKey] = diskHit.match;
    _cache['${parsed.title}|${parsed.year ?? ''}'] = diskHit.match;
    return diskHit.match;
  }

  MediaMatch? match;
  if (apiKey != null && apiKey.isNotEmpty) {
    try {
      match = await matchTitle(apiKey, filename);
    } on TmdbException {
      match = null;
    }
  }
  match ??= await findWikiMovie(filename);
  _lookupCache[memKey] = match;
  await _disk.writeLookup(parsed.title, parsed.year, match);
  return match;
}

Future<MediaDetail> lookupDetail(MediaMatch match, String? apiKey, {bool bypassCache = false}) async {
  if (!bypassCache) {
    final cached = await _disk.readDetail(match);
    if (cached != null) return cached;
  }

  MediaDetail detail;
  if (match.tmdbId != null && apiKey != null && apiKey.isNotEmpty) {
    try {
      detail = await fetchMediaDetail(apiKey, match);
      await _disk.writeDetail(detail);
      return detail;
    } on TmdbException {
      // Fall through to Wikipedia when the key is rejected.
    }
  }
  if (match.wikibaseId != null) {
    detail = await wikiMediaDetail(match);
    await _disk.writeDetail(detail);
    return detail;
  }
  return MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
}

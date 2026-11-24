import 'dart:convert';

import 'package:http/http.dart' as http;

import '../format.dart';
import '../models.dart';
import 'wiki.dart';

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
}

final _cache = <String, MediaMatch?>{};
final _lookupCache = <String, MediaMatch?>{};

String? _image(String? path, String size) => path == null || path.isEmpty ? null : 'https://image.tmdb.org/t/p/$size$path';

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
  );
}

Future<MediaMatch?> _searchKind(String apiKey, String kind, String title, String? year, String language) async {
  final params = <String, String>{
    'api_key': apiKey,
    'query': title,
    'language': language,
    'include_adult': 'false',
  };
  if (year != null) params[kind == 'movie' ? 'year' : 'first_air_date_year'] = year;
  final response = await http.get(Uri.https('api.themoviedb.org', '/3/search/$kind', params));
  if (response.statusCode == 401) throw TmdbException('ใช้ TMDB API key นี้ไม่ได้');
  if (response.statusCode != 200) return null;
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final results = (body['results'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
  if (results.isEmpty) return null;
  results.sort((a, b) => ((b['popularity'] as num?) ?? 0).compareTo((a['popularity'] as num?) ?? 0));
  return _toMatch(kind, results.first);
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
    ),
    runtime: runtime,
    cast: cast,
    genres: genres,
    director: director,
  );
}

Future<MediaMatch?> lookupMedia(String filename, String? apiKey) async {
  final parsed = presentTitle(filename);
  final cacheKey = '${apiKey ?? ''}|${parsed.title}|${parsed.year ?? ''}';
  if (_lookupCache.containsKey(cacheKey)) return _lookupCache[cacheKey];

  MediaMatch? match;
  if (apiKey != null && apiKey.isNotEmpty) {
    try {
      match = await matchTitle(apiKey, filename);
    } on TmdbException {
      match = null;
    }
  }
  match ??= await findWikiMovie(filename);
  _lookupCache[cacheKey] = match;
  return match;
}

Future<MediaDetail> lookupDetail(MediaMatch match, String? apiKey) async {
  if (match.tmdbId != null && apiKey != null && apiKey.isNotEmpty) {
    try {
      return await fetchMediaDetail(apiKey, match);
    } on TmdbException {
      // Fall through to Wikipedia when the key is rejected.
    }
  }
  if (match.wikibaseId != null) return wikiMediaDetail(match);
  return MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
}

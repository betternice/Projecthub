import 'package:dio/dio.dart';

import '../../domain/entities/media.dart';

class InvalidTmdbKeyException implements Exception {
  const InvalidTmdbKeyException();
}

class TmdbRemoteDataSource {
  TmdbRemoteDataSource(this._dio);

  final Dio _dio;

  static const _api = 'https://api.themoviedb.org/3';
  static final _options = Options(validateStatus: (_) => true);

  Future<MediaMatch?> search({
    required String apiKey,
    required MediaKind kind,
    required String title,
    required String? year,
    required String language,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_api/search/${kind.name}',
      queryParameters: {
        'api_key': apiKey,
        'query': title,
        'language': language,
        'include_adult': 'false',
        (kind == MediaKind.movie ? 'year' : 'first_air_date_year'): ?year,
      },
      options: _options,
    );
    _throwIfUnauthorized(response);
    if (!_ok(response)) return null;

    final results = (response.data?['results'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    if (results.isEmpty) return null;
    results.sort((a, b) => _popularity(b).compareTo(_popularity(a)));
    return _toMatch(kind, results.first);
  }

  /// คืน null เมื่อ TMDB ตอบไม่สำเร็จ ให้ชั้นบนใช้ข้อมูลจากผลค้นหาแทน
  Future<MediaDetail?> detail({required String apiKey, required MediaMatch match}) async {
    final id = match.tmdbId;
    if (id == null) return null;
    final response = await _dio.get<Map<String, dynamic>>(
      '$_api/${match.kind.name}/$id',
      queryParameters: {'api_key': apiKey, 'language': 'th-TH', 'append_to_response': 'credits'},
      options: _options,
    );
    _throwIfUnauthorized(response);
    final body = response.data;
    if (!_ok(response) || body == null) return null;

    final credits = body['credits'] as Map<String, dynamic>? ?? const {};
    final cast = (credits['cast'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(12)
        .map(
          (person) => CastMember(
            name: person['name'] as String? ?? '',
            character: _nonEmpty(person['character'] as String?),
            profileUrl: _image(person['profile_path'] as String?, 'w185'),
          ),
        )
        .where((person) => person.name.isNotEmpty)
        .toList();
    final director = (credits['crew'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((person) => person['job'] == 'Director')
        .map((person) => person['name'] as String?)
        .firstWhere((name) => name != null && name.isNotEmpty, orElse: () => null);
    final genres = (body['genres'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((genre) => genre['name'] as String?)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .take(2)
        .toList();
    final runtime = match.kind == MediaKind.movie
        ? (body['runtime'] as num?)?.toInt()
        : ((body['episode_run_time'] as List?)?.whereType<num>().firstOrNull)?.toInt();

    return MediaDetail(
      match: match.copyWith(overview: _nonEmpty((body['overview'] as String?)?.trim())),
      runtimeMinutes: runtime,
      cast: cast,
      genres: genres,
      director: director,
    );
  }

  MediaMatch _toMatch(MediaKind kind, Map<String, dynamic> result) {
    final date = (kind == MediaKind.movie ? result['release_date'] : result['first_air_date']) as String?;
    final vote = (result['vote_average'] as num?)?.toDouble();
    return MediaMatch(
      tmdbId: (result['id'] as num?)?.toInt(),
      kind: kind,
      title: (result['title'] ?? result['name']) as String? ?? '',
      overview: _nonEmpty((result['overview'] as String?)?.trim()),
      year: date != null && date.length >= 4 ? date.substring(0, 4) : null,
      posterUrl: _image(result['poster_path'] as String?, 'w500'),
      backdropUrl: _image(result['backdrop_path'] as String?, 'w780'),
      rating: vote == null || vote == 0 ? null : (vote * 10).round() / 10,
    );
  }

  void _throwIfUnauthorized(Response<dynamic> response) {
    if (response.statusCode == 401) throw const InvalidTmdbKeyException();
  }

  bool _ok(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    return status >= 200 && status < 300;
  }

  double _popularity(Map<String, dynamic> result) => (result['popularity'] as num?)?.toDouble() ?? 0;

  String? _image(String? path, String size) =>
      path == null || path.isEmpty ? null : 'https://image.tmdb.org/t/p/$size$path';

  String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;
}

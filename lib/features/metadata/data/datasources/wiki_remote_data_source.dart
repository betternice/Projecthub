import 'package:dio/dio.dart';

import '../../domain/entities/media.dart';

enum WikiLang { en, th }

/// ดึงปกและเรื่องย่อจาก Wikipedia และรายละเอียดนักแสดง/ผู้กำกับจาก Wikidata โดยไม่ต้องใช้ key
class WikiRemoteDataSource {
  WikiRemoteDataSource(this._dio);

  final Dio _dio;

  static final _options = Options(
    validateStatus: (_) => true,
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'MovieCollection/1.0 (personal OneDrive movie library)',
      'Api-User-Agent': 'MovieCollection/1.0 (personal OneDrive movie library)',
    },
  );

  static final _thaiScript = RegExp(r'[\u0E00-\u0E7F]');
  static final _yearInText = RegExp(r'\b(19|20)\d{2}\b');

  Future<MediaMatch?> findMovie({required String title, required String? year}) async {
    if (title.isEmpty) return null;
    final lang = _thaiScript.hasMatch(title) ? WikiLang.th : WikiLang.en;
    final query = lang == WikiLang.th ? '$title ภาพยนตร์' : [title, year, 'film'].whereType<String>().join(' ');
    final hit = _choose(await _search(lang, query), title, year);
    final pageKey = hit?.key ?? hit?.title;
    if (pageKey == null) return null;

    final summary = await _summary(lang, pageKey);
    if (summary == null || (summary.title == null && summary.extract == null && summary.image == null)) return null;

    final cleaned = _cleanTitle(summary.title ?? hit?.title ?? title, year);
    final describedYear = _yearInText.firstMatch(summary.description ?? '')?.group(0);
    final overview = _firstParagraph(summary.extract);
    final kindText = '${summary.description ?? ''} ${summary.title ?? ''}';

    return MediaMatch(
      wikibaseId: summary.wikibaseItem,
      kind: RegExp('series|television|ละคร', caseSensitive: false).hasMatch(kindText) ? MediaKind.tv : MediaKind.movie,
      title: cleaned.title,
      overview: overview,
      year: cleaned.year ?? describedYear ?? year,
      posterUrl: summary.image,
      backdropUrl: summary.image,
    );
  }

  Future<MediaDetail?> detail(MediaMatch match) async {
    final id = match.wikibaseId;
    if (id == null) return null;

    final entity = await _entity(id);
    final claims = entity?.claims ?? const <String, List<Object?>>{};
    var next = match;
    final thaiTitle = entity?.thaiTitle;
    if (thaiTitle != null) {
      final thai = await _summary(WikiLang.th, thaiTitle);
      final poster = next.posterUrl ?? thai?.image;
      next = next.copyWith(
        title: thai?.title != null ? _cleanTitle(thai!.title!, next.year).title : null,
        overview: _firstParagraph(thai?.extract),
        posterUrl: poster,
        backdropUrl: next.backdropUrl ?? poster,
      );
    }
    final releaseYear = _claimYear(claims);
    if (next.year == null && releaseYear != null) next = next.copyWith(year: releaseYear);

    final genreIds = _claimIds(claims, 'P136', 2);
    final directorIds = _claimIds(claims, 'P57', 1);
    final castIds = _claimIds(claims, 'P161', 10);
    final names = await _labels([...genreIds, ...directorIds, ...castIds]);

    return MediaDetail(
      match: next,
      runtimeMinutes: _claimMinutes(claims),
      genres: genreIds.map((id) => names[id]).whereType<String>().where((name) => name.isNotEmpty).toList(),
      director: directorIds.map((id) => names[id]).whereType<String>().where((name) => name.isNotEmpty).firstOrNull,
      cast: castIds
          .map((id) => names[id])
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .map((name) => CastMember(name: name))
          .toList(),
    );
  }

  Future<List<_SearchHit>> _search(WikiLang lang, String query) async {
    final body = await _json('https://${lang.name}.wikipedia.org/w/rest.php/v1/search/page', {'q': query, 'limit': 5});
    final pages = body?['pages'];
    if (pages is! List) return const [];
    return pages.whereType<Map<String, dynamic>>().map(_SearchHit.fromJson).toList();
  }

  _SearchHit? _choose(List<_SearchHit> hits, String title, String? year) {
    final wanted = title.toLowerCase();
    _SearchHit? best;
    var bestScore = -1 << 30;
    for (final hit in hits) {
      final name = (hit.title ?? '').toLowerCase();
      final description = (hit.description ?? '').toLowerCase();
      var score = 0;
      if (RegExp('film|movie|ภาพยนตร์|ละคร|television series|tv series').hasMatch(description)) score += 6;
      if (RegExp(r'\(film\)|ภาพยนตร์').hasMatch(name)) score += 2;
      if (year != null && (name.contains(year) || description.contains(year))) score += 4;
      if (name == wanted || name.startsWith(wanted)) {
        score += 4;
      } else if (name.contains(wanted)) {
        score += 2;
      }
      if (RegExp('album|soundtrack|song|novel|book|episode').hasMatch(description)) score -= 6;
      if (score > bestScore) {
        best = hit;
        bestScore = score;
      }
    }
    return bestScore >= 6 ? best : null;
  }

  Future<_Summary?> _summary(WikiLang lang, String titleOrKey) async {
    final body = await _json(
      'https://${lang.name}.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(titleOrKey)}',
    );
    return body == null ? null : _Summary.fromJson(body);
  }

  Future<_Entity?> _entity(String id) async {
    final body = await _json('https://www.wikidata.org/w/api.php', {
      'action': 'wbgetentities',
      'ids': id,
      'props': 'sitelinks|claims',
      'sitefilter': 'thwiki',
      'format': 'json',
    });
    final entity = (body?['entities'] as Map<String, dynamic>?)?[id];
    return entity is Map<String, dynamic> ? _Entity.fromJson(entity) : null;
  }

  Future<Map<String, String>> _labels(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final body = await _json('https://www.wikidata.org/w/api.php', {
      'action': 'wbgetentities',
      'ids': ids.join('|'),
      'props': 'labels',
      'languages': 'th|en',
      'format': 'json',
    });
    final entities = body?['entities'];
    if (entities is! Map<String, dynamic>) return const {};
    final labels = <String, String>{};
    for (final MapEntry(:key, :value) in entities.entries) {
      final byLang = value is Map ? value['labels'] : null;
      if (byLang is! Map) continue;
      final label = (byLang['th'] as Map?)?['value'] ?? (byLang['en'] as Map?)?['value'];
      if (label is String) labels[key] = label;
    }
    return labels;
  }

  Future<Map<String, dynamic>?> _json(String url, [Map<String, dynamic>? query]) async {
    final response = await _dio.get<dynamic>(url, queryParameters: query, options: _options);
    final status = response.statusCode ?? 0;
    final data = response.data;
    return status >= 200 && status < 300 && data is Map<String, dynamic> ? data : null;
  }

  static ({String title, String? year}) _cleanTitle(String title, String? fallbackYear) {
    final year = RegExp(r'\(((?:19|20)\d{2})').firstMatch(title)?.group(1) ?? fallbackYear;
    final cleaned = title.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    return (title: cleaned.isEmpty ? title : cleaned, year: year);
  }

  static String? _firstParagraph(String? text) {
    if (text == null) return null;
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static List<Map<String, dynamic>> _values(Map<String, List<Object?>> claims, String prop) {
    return (claims[prop] ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((claim) => (claim['mainsnak'] as Map?)?['datavalue'])
        .whereType<Map<String, dynamic>>()
        .map((datavalue) => datavalue['value'])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static List<String> _claimIds(Map<String, List<Object?>> claims, String prop, int limit) {
    return _values(claims, prop).map((value) => value['id']).whereType<String>().take(limit).toList();
  }

  static String? _claimYear(Map<String, List<Object?>> claims) {
    final time = _values(claims, 'P577').firstOrNull?['time'];
    return time is String ? RegExp(r'(19|20)\d{2}').firstMatch(time)?.group(0) : null;
  }

  /// P2047 คือความยาว ใช้ได้เฉพาะหน่วยนาที (Q7727)
  static int? _claimMinutes(Map<String, List<Object?>> claims) {
    final value = _values(claims, 'P2047').firstOrNull;
    final amount = value?['amount'];
    final unit = value?['unit'];
    if (amount is! String || unit is! String || !unit.endsWith('Q7727')) return null;
    final minutes = double.tryParse(amount)?.abs().truncate();
    return minutes != null && minutes > 0 && minutes < 1000 ? minutes : null;
  }
}

class _SearchHit {
  const _SearchHit({this.key, this.title, this.description});

  factory _SearchHit.fromJson(Map<String, dynamic> json) => _SearchHit(
    key: json['key'] as String?,
    title: json['title'] as String?,
    description: json['description'] as String?,
  );

  final String? key;
  final String? title;
  final String? description;
}

class _Summary {
  const _Summary({this.title, this.description, this.extract, this.image, this.wikibaseItem});

  factory _Summary.fromJson(Map<String, dynamic> json) => _Summary(
    title: json['title'] as String?,
    description: json['description'] as String?,
    extract: json['extract'] as String?,
    image: (json['originalimage'] as Map?)?['source'] as String? ?? (json['thumbnail'] as Map?)?['source'] as String?,
    wikibaseItem: json['wikibase_item'] as String?,
  );

  final String? title;
  final String? description;
  final String? extract;
  final String? image;
  final String? wikibaseItem;
}

class _Entity {
  const _Entity({this.thaiTitle, this.claims = const {}});

  factory _Entity.fromJson(Map<String, dynamic> json) {
    final claims = <String, List<Object?>>{};
    final raw = json['claims'];
    if (raw is Map<String, dynamic>) {
      for (final MapEntry(:key, :value) in raw.entries) {
        if (value is List) claims[key] = value;
      }
    }
    return _Entity(
      thaiTitle: ((json['sitelinks'] as Map?)?['thwiki'] as Map?)?['title'] as String?,
      claims: claims,
    );
  }

  final String? thaiTitle;
  final Map<String, List<Object?>> claims;
}

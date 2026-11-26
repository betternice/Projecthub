import 'dart:convert';

import 'package:http/http.dart' as http;

import '../format.dart';
import '../models.dart';

const _headers = {
  'Accept': 'application/json',
  'User-Agent': 'MovieCollection/1.0 (personal OneDrive movie library)',
  'Api-User-Agent': 'MovieCollection/1.0 (personal OneDrive movie library)',
};

String _firstParagraph(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

({String title, String? year}) _cleanWikiTitle(String title, String? fallbackYear) {
  final year = RegExp(r'\(((?:19|20)\d{2})').firstMatch(title)?.group(1) ?? fallbackYear;
  final cleaned = title.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  return (title: cleaned.isEmpty ? title : cleaned, year: year);
}

Future<T?> _readJson<T>(Uri url) async {
  final response = await http.get(url, headers: _headers);
  if (response.statusCode != 200) return null;
  return jsonDecode(response.body) as T;
}

Future<List<Map<String, dynamic>>> _search(String lang, String query) async {
  final body = await _readJson<Map<String, dynamic>>(
    Uri.parse('https://$lang.wikipedia.org/w/rest.php/v1/search/page?q=${Uri.encodeQueryComponent(query)}&limit=5'),
  );
  return (body?['pages'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
}

Map<String, dynamic>? _choose(List<Map<String, dynamic>> hits, String title, String? year) {
  final wanted = title.toLowerCase();
  Map<String, dynamic>? best;
  var bestScore = -999;
  for (final hit in hits) {
    final name = (hit['title'] as String? ?? '').toLowerCase();
    final description = (hit['description'] as String? ?? '').toLowerCase();
    var score = 0;
    if (RegExp(r'film|movie|ภาพยนตร์|ละคร|television series|tv series').hasMatch(description)) score += 6;
    if (RegExp(r'\(film\)|ภาพยนตร์').hasMatch(name)) score += 2;
    if (year != null && (name.contains(year) || description.contains(year))) score += 4;
    if (name == wanted || name.startsWith(wanted)) {
      score += 4;
    } else if (name.contains(wanted)) {
      score += 2;
    }
    if (RegExp(r'album|soundtrack|song|novel|book|episode').hasMatch(description)) score -= 6;
    if (score > bestScore) {
      best = hit;
      bestScore = score;
    }
  }
  return bestScore >= 6 ? best : null;
}

Future<Map<String, dynamic>?> _pageSummary(String lang, String titleOrKey) {
  return _readJson<Map<String, dynamic>>(
    Uri.parse('https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(titleOrKey)}'),
  );
}

Future<MediaMatch?> findWikiMovie(String filename) async {
  final parsed = presentTitle(filename);
  if (parsed.title.isEmpty) return null;
  final thai = RegExp(r'[\u0E00-\u0E7F]').hasMatch(parsed.title);
  final query = thai ? '${parsed.title} ภาพยนตร์' : [parsed.title, parsed.year, 'film'].whereType<String>().join(' ');
  final hit = _choose(await _search(thai ? 'th' : 'en', query), parsed.title, parsed.year);
  if (hit == null || (hit['title'] == null && hit['key'] == null)) return null;

  final summary = await _pageSummary(thai ? 'th' : 'en', (hit['key'] as String?) ?? (hit['title'] as String?) ?? parsed.title);
  if (summary == null) return null;
  final original = (summary['originalimage'] as Map?)?['source'] as String?;
  if (summary['title'] == null && summary['extract'] == null && original == null) return null;

  final cleaned = _cleanWikiTitle(summary['title'] as String? ?? hit['title'] as String? ?? parsed.title, parsed.year);
  final describedYear = RegExp(r'\b(19|20)\d{2}\b').firstMatch(summary['description'] as String? ?? '')?.group(0);
  final poster = original ?? (summary['thumbnail'] as Map?)?['source'] as String?;
  final overview = _firstParagraph(summary['extract'] as String? ?? '');
  final described = '${summary['description'] ?? ''} ${summary['title'] ?? ''}';

  return MediaMatch(
    tmdbId: null,
    wikibaseId: summary['wikibase_item'] as String?,
    kind: RegExp(r'series|television|ละคร', caseSensitive: false).hasMatch(described) ? 'tv' : 'movie',
    title: cleaned.title,
    overview: overview.isEmpty ? null : overview,
    year: cleaned.year ?? describedYear ?? parsed.year,
    posterUrl: poster,
    backdropUrl: poster,
    rating: null,
    genres: const [],
  );
}

List<String> _claimIds(Map<String, dynamic>? claims, String prop, int limit) {
  final list = claims?[prop] as List<dynamic>? ?? [];
  return list
      .whereType<Map<String, dynamic>>()
      .map((claim) => (((claim['mainsnak'] as Map?)?['datavalue'] as Map?)?['value'] as Map?)?['id'] as String?)
      .whereType<String>()
      .take(limit)
      .toList();
}

String? _claimYear(Map<String, dynamic>? claims) {
  final time = (((claims?['P577'] as List?)?.cast<Map?>().firstOrNull)?['mainsnak'] as Map?)?['datavalue'] as Map?;
  final value = (time?['value'] as Map?)?['time'] as String?;
  return RegExp(r'(19|20)\d{2}').firstMatch(value ?? '')?.group(0);
}

int? _claimMinutes(Map<String, dynamic>? claims) {
  final raw = (((claims?['P2047'] as List?)?.cast<Map?>().firstOrNull)?['mainsnak'] as Map?)?['datavalue'] as Map?;
  final value = raw?['value'] as Map?;
  final amount = value?['amount']?.toString();
  final unit = value?['unit']?.toString() ?? '';
  if (amount == null || !unit.endsWith('Q7727')) return null;
  final minutes = int.tryParse(amount.replaceAll('+', ''))?.abs();
  if (minutes == null || minutes <= 0 || minutes >= 1000) return null;
  return minutes;
}

Future<Map<String, dynamic>?> _entity(String id) async {
  final body = await _readJson<Map<String, dynamic>>(
    Uri.parse(
      'https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${Uri.encodeQueryComponent(id)}&props=sitelinks|claims&sitefilter=thwiki&format=json',
    ),
  );
  final entities = body?['entities'] as Map<String, dynamic>?;
  return entities?[id] as Map<String, dynamic>?;
}

Future<Map<String, String>> _labels(List<String> ids) async {
  if (ids.isEmpty) return {};
  final body = await _readJson<Map<String, dynamic>>(
    Uri.parse(
      'https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${ids.join('|')}&props=labels&languages=th|en&format=json',
    ),
  );
  final entities = body?['entities'] as Map<String, dynamic>? ?? {};
  final map = <String, String>{};
  for (final entry in entities.entries) {
    final labels = entry.value['labels'] as Map?;
    map[entry.key] = (labels?['th'] as Map?)?['value'] as String? ?? (labels?['en'] as Map?)?['value'] as String? ?? '';
  }
  return map;
}

Future<MediaDetail> wikiMediaDetail(MediaMatch match) async {
  if (match.wikibaseId == null) {
    return MediaDetail(match: match, runtime: null, cast: const [], genres: const [], director: null);
  }
  final record = await _entity(match.wikibaseId!);
  final claims = record?['claims'] as Map<String, dynamic>?;
  final thaiTitle = ((record?['sitelinks'] as Map?)?['thwiki'] as Map?)?['title'] as String?;
  var next = match;
  if (thaiTitle != null) {
    final thai = await _pageSummary('th', thaiTitle);
    final overview = _firstParagraph(thai?['extract'] as String? ?? '');
    final poster = next.posterUrl ??
        (thai?['originalimage'] as Map?)?['source'] as String? ??
        (thai?['thumbnail'] as Map?)?['source'] as String?;
    next = MediaMatch(
      tmdbId: next.tmdbId,
      wikibaseId: next.wikibaseId,
      kind: next.kind,
      title: thai?['title'] != null ? _cleanWikiTitle(thai!['title'] as String, next.year).title : next.title,
      overview: overview.isEmpty ? next.overview : overview,
      year: next.year ?? _claimYear(claims),
      posterUrl: poster,
      backdropUrl: next.backdropUrl ?? poster,
      rating: next.rating,
      genres: next.genres,
    );
  }

  final genreIds = _claimIds(claims, 'P136', 2);
  final directorIds = _claimIds(claims, 'P57', 1);
  final castIds = _claimIds(claims, 'P161', 10);
  final names = await _labels([...genreIds, ...directorIds, ...castIds]);
  final cast = castIds
      .map((id) => CastMember(name: names[id] ?? ''))
      .where((person) => person.name.isNotEmpty)
      .toList();
  final genres = genreIds.map((id) => names[id] ?? '').where((name) => name.isNotEmpty).toList();

  return MediaDetail(
    match: MediaMatch(
      tmdbId: next.tmdbId,
      wikibaseId: next.wikibaseId,
      kind: next.kind,
      title: next.title,
      overview: next.overview,
      year: next.year ?? _claimYear(claims),
      posterUrl: next.posterUrl,
      backdropUrl: next.backdropUrl,
      rating: next.rating,
      genres: genres.isNotEmpty ? genres : next.genres,
    ),
    runtime: _claimMinutes(claims),
    genres: genres.isNotEmpty ? genres : next.genres,
    director: directorIds.map((id) => names[id] ?? '').where((name) => name.isNotEmpty).firstOrNull,
    cast: cast,
  );
}

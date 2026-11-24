import 'package:dio/dio.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/network/dio_failure.dart';
import '../../../../core/utils/media_title.dart';
import '../../domain/entities/media.dart';
import '../../domain/repositories/metadata_repository.dart';
import '../datasources/tmdb_remote_data_source.dart';
import '../datasources/wiki_remote_data_source.dart';

class MetadataRepositoryImpl implements MetadataRepository {
  MetadataRepositoryImpl({required TmdbRemoteDataSource tmdb, required WikiRemoteDataSource wiki})
    : _tmdb = tmdb,
      _wiki = wiki;

  final TmdbRemoteDataSource _tmdb;
  final WikiRemoteDataSource _wiki;

  /// เก็บเฉพาะผลที่ได้คำตอบจริง (เจอหรือไม่เจอ) ถ้าเครือข่ายล้มจะไม่ cache เพื่อให้ลองใหม่ได้
  final _lookups = <String, MediaMatch?>{};

  @override
  Future<MediaMatch?> lookup(String filename, {String? tmdbApiKey}) async {
    final parsed = parseMediaTitle(filename);
    final cacheKey = '${tmdbApiKey ?? ''}|${parsed.title}|${parsed.year ?? ''}';
    if (_lookups.containsKey(cacheKey)) return _lookups[cacheKey];

    try {
      MediaMatch? match;
      if (tmdbApiKey != null) match = await _searchTmdb(tmdbApiKey, parsed);
      match ??= await _wiki.findMovie(title: parsed.title, year: parsed.year);
      _lookups[cacheKey] = match;
      return match;
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<MediaDetail> detail(MediaMatch match, {String? tmdbApiKey}) async {
    try {
      if (match.tmdbId != null && tmdbApiKey != null) {
        try {
          final detail = await _tmdb.detail(apiKey: tmdbApiKey, match: match);
          if (detail != null) return detail;
        } on InvalidTmdbKeyException {
          // key ใช้ไม่ได้ ให้ใช้ข้อมูลจากผลค้นหาที่มีอยู่แล้ว
        }
      }
      if (match.wikibaseId != null) {
        final detail = await _wiki.detail(match);
        if (detail != null) return detail;
      }
      return MediaDetail(match: match);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  Future<MediaMatch?> _searchTmdb(String apiKey, ParsedTitle parsed) async {
    if (parsed.title.isEmpty) return null;
    final attempts = <(MediaKind, String?, String)>[
      (MediaKind.movie, parsed.year, 'th-TH'),
      (MediaKind.movie, null, 'th-TH'),
      (MediaKind.tv, parsed.year, 'th-TH'),
      (MediaKind.movie, parsed.year, 'en-US'),
      (MediaKind.tv, parsed.year, 'en-US'),
    ];
    try {
      for (final (kind, year, language) in attempts) {
        final match = await _tmdb.search(
          apiKey: apiKey,
          kind: kind,
          title: parsed.title,
          year: year,
          language: language,
        );
        if (match != null) return match;
      }
      return null;
    } on InvalidTmdbKeyException {
      return null;
    }
  }

  Failure _failure(DioException error) {
    if (isConnectionError(error)) return const NetworkFailure();
    return const ServerFailure('โหลดข้อมูลหนังไม่สำเร็จ');
  }
}

import '../entities/media.dart';

abstract interface class MetadataRepository {
  /// หา metadata จากชื่อไฟล์ ใช้ TMDB ก่อนถ้ามี key แล้วค่อยถอยไป Wikipedia
  /// คืน null เมื่อหาไม่เจอ และโยน Failure เมื่อเครือข่ายมีปัญหา
  Future<MediaMatch?> lookup(String filename, {String? tmdbApiKey});

  Future<MediaDetail> detail(MediaMatch match, {String? tmdbApiKey});
}

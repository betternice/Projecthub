import '../entities/media.dart';
import '../repositories/metadata_repository.dart';

class LookupMedia {
  const LookupMedia(this._repository);

  final MetadataRepository _repository;

  Future<MediaMatch?> call(String filename, {String? tmdbApiKey}) =>
      _repository.lookup(filename, tmdbApiKey: tmdbApiKey);
}

class LookupMediaDetail {
  const LookupMediaDetail(this._repository);

  final MetadataRepository _repository;

  Future<MediaDetail> call(MediaMatch match, {String? tmdbApiKey}) =>
      _repository.detail(match, tmdbApiKey: tmdbApiKey);
}

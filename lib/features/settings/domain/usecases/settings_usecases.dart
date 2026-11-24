import '../repositories/settings_repository.dart';

class GetTmdbApiKey {
  const GetTmdbApiKey(this._repository);

  final SettingsRepository _repository;

  Future<String?> call() => _repository.tmdbApiKey();
}

class SaveTmdbApiKey {
  const SaveTmdbApiKey(this._repository);

  final SettingsRepository _repository;

  Future<String?> call(String value) => _repository.saveTmdbApiKey(value);
}

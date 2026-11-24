import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsLocalDataSource {
  SettingsLocalDataSource(this._storage);

  final FlutterSecureStorage _storage;

  static const _tmdbKey = 'tmdb_api_key';

  Future<String?> readTmdbApiKey() => _storage.read(key: _tmdbKey);

  Future<void> writeTmdbApiKey(String value) => _storage.write(key: _tmdbKey, value: value);

  Future<void> deleteTmdbApiKey() => _storage.delete(key: _tmdbKey);
}

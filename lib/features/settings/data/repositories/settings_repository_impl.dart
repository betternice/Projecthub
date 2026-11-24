import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;

  @override
  Future<String?> tmdbApiKey() async {
    final value = (await _local.readTmdbApiKey())?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<String?> saveTmdbApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _local.deleteTmdbApiKey();
      return null;
    }
    await _local.writeTmdbApiKey(trimmed);
    return trimmed;
  }
}

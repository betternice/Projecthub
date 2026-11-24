abstract interface class SettingsRepository {
  Future<String?> tmdbApiKey();

  /// ค่าว่างหมายถึงลบ key ออก
  Future<String?> saveTmdbApiKey(String value);
}

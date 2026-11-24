import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/drive_item.dart';
import '../models/drive_item_model.dart';

class FolderTrailLocalDataSource {
  FolderTrailLocalDataSource(this._prefs);

  final SharedPreferencesAsync _prefs;

  static const _key = 'folder_trail';

  Future<List<FolderCrumb>> read() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(FolderCrumbModel.fromJson).whereType<FolderCrumb>().toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> write(List<FolderCrumb> trail) {
    return _prefs.setString(_key, jsonEncode(trail.map(FolderCrumbModel.toJson).toList()));
  }
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/session.dart';
import '../models/auth_models.dart';

class AuthLocalDataSource {
  AuthLocalDataSource(this._storage);

  final FlutterSecureStorage _storage;

  static const _sessionKey = 'session';
  static const _clientIdKey = 'client_id';

  Future<Session?> readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? SessionModel.tryParse(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeSession(Session session) {
    return _storage.write(key: _sessionKey, value: jsonEncode(SessionModel(session).toJson()));
  }

  Future<void> deleteSession() => _storage.delete(key: _sessionKey);

  Future<String> readClientId() async => await _storage.read(key: _clientIdKey) ?? '';

  Future<void> writeClientId(String clientId) => _storage.write(key: _clientIdKey, value: clientId);
}

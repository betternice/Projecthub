import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/microsoft.dart';
import '../models.dart';

class AppState extends ChangeNotifier {
  AppState();

  final _secure = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  SharedPreferences? _prefs;

  bool ready = false;
  Session? session;
  String savedClientId = '';
  String? tmdbKey;

  Future<String>? _refreshing;

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    savedClientId = _prefs?.getString('clientId') ?? '';
    tmdbKey = _prefs?.getString('tmdbKey');
    final raw = await _secure.read(key: 'session');
    if (raw != null) {
      try {
        final parsed = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final current = parsed.expiresAt - 60000 > DateTime.now().millisecondsSinceEpoch
            ? parsed
            : await _renewed(parsed);
        await _secure.write(key: 'session', value: jsonEncode(current.toJson()));
        session = current;
      } catch (_) {
        await _secure.delete(key: 'session');
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> saveSession(Session next) async {
    await _secure.write(key: 'session', value: jsonEncode(next.toJson()));
    session = next;
    notifyListeners();
  }

  Future<void> saveClientId(String clientId) async {
    savedClientId = clientId;
    await _prefs?.setString('clientId', clientId);
    notifyListeners();
  }

  Future<void> setTmdbKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      tmdbKey = null;
      await _prefs?.remove('tmdbKey');
    } else {
      tmdbKey = trimmed;
      await _prefs?.setString('tmdbKey', trimmed);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _secure.delete(key: 'session');
    session = null;
    notifyListeners();
  }

  Future<String> getToken() async {
    final current = session;
    if (current == null) throw Exception('เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง');
    if (current.expiresAt - 60000 > DateTime.now().millisecondsSinceEpoch) return current.accessToken;

    _refreshing ??= _refresh(current);
    return _refreshing!;
  }

  Future<String> _refresh(Session current) async {
    try {
      final next = await _renewed(current);
      await _secure.write(key: 'session', value: jsonEncode(next.toJson()));
      session = next;
      notifyListeners();
      return next.accessToken;
    } catch (_) {
      await _secure.delete(key: 'session');
      session = null;
      notifyListeners();
      throw Exception('เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง');
    } finally {
      _refreshing = null;
    }
  }

  Future<Session> _renewed(Session current) async {
    final tokens = await refreshTokens(current.clientId, current.refreshToken);
    return current.copyWith(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
    );
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required AppState state, required super.child, super.key}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.notifier!;
  }
}

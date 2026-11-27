import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/azure_config.dart';
import '../auth/microsoft.dart';
import '../l10n/app_localizations.dart';
import '../local/library.dart';
import '../metadata/cache.dart';
import '../models.dart';
import '../onedrive/graph.dart';

class AppState extends ChangeNotifier {
  AppState();

  final _secure = const FlutterSecureStorage(aOptions: AndroidOptions());
  SharedPreferences? _prefs;

  bool ready = false;
  List<Session> accounts = [];
  String? activeAccountId;
  String savedClientId = '';
  String? tmdbKey;
  String? bootMessage;
  MediaSource source = MediaSource.overview;
  String? localRootPath;
  List<LibraryRef> favorites = [];
  List<WatchProgress> continueWatching = [];
  AppLang lang = AppLang.th;

  List<UserProfile> profiles = [];
  String? activeProfileId;
  var syncingProfiles = false;
  String? lastSyncError;

  AppLocalizations get l10n => AppLocalizations(lang);

  String tr(String key, [Map<String, String>? params]) => l10n.t(key, params);

  final Map<String, Future<String>> _refreshingById = {};
  Timer? _syncDebounce;

  static const _profileColors = [
    0xFFE50914,
    0xFF2D6CDF,
    0xFF2BB673,
    0xFFF5A524,
    0xFF9B59B6,
    0xFF00BCD4,
  ];

  Session? get session {
    if (accounts.isEmpty) return null;
    final id = activeAccountId;
    if (id != null) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
    }
    return accounts.first;
  }

  bool get hasOneDrive => accounts.isNotEmpty;

  String get oneDriveLabel => session?.title ?? 'My OneDrive';

  UserProfile? get activeProfile {
    final id = activeProfileId;
    if (id == null) return profiles.isEmpty ? null : profiles.first;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  String get activeProfileName => activeProfile?.name ?? 'Profile';

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    savedClientId = _prefs?.getString('clientId') ?? '';
    if (savedClientId.isEmpty) {
      savedClientId = kAzureClientId;
      await _prefs?.setString('clientId', savedClientId);
    }
    tmdbKey = _prefs?.getString('tmdbKey');
    source = mediaSourceFromKey(_prefs?.getString('mediaSource'));
    localRootPath = _prefs?.getString('localRootPath');
    activeAccountId = _prefs?.getString('activeAccountId');
    lang = AppLang.fromCode(_prefs?.getString('appLang'));
    await MetadataDiskCache.instance.ensureLoaded();

    if (!kIsWeb) {
      if (localRootPath != null && !Directory(localRootPath!).existsSync()) {
        localRootPath = null;
        await _prefs?.remove('localRootPath');
      }
      if (localRootPath == null) {
        try {
          localRootPath = await detectDefaultLocalRoot();
          if (localRootPath != null) {
            await _prefs?.setString('localRootPath', localRootPath!);
          }
        } catch (_) {
          localRootPath = null;
        }
      }
    }

    accounts = await _readAccounts();
    if (accounts.isNotEmpty) {
      if (activeAccountId == null || session == null) {
        activeAccountId = accounts.first.id;
        await _prefs?.setString('activeAccountId', activeAccountId!);
      }
      await _refreshActiveIfNeeded();
    }

    if (kIsWeb) {
      await _completeWebOAuthIfNeeded();
    }

    if (source == MediaSource.oneDrive && accounts.isEmpty) {
      source = MediaSource.overview;
      await _prefs?.setString('mediaSource', mediaSourceKey(source));
    }

    await _bootProfiles();

    ready = true;
    notifyListeners();

    // ดึงซิงก์จาก OneDrive เงียบๆ หลังพร้อม
    unawaited(pullProfileSync());
  }

  Future<void> _completeWebOAuthIfNeeded() async {
    try {
      final result = await completeWebMicrosoftLoginIfNeeded(
        savedClientId.isNotEmpty ? savedClientId : kAzureClientId,
      );
      if (result == null) return;
      final profile = await fetchProfile(result.tokens.accessToken);
      await saveClientId(savedClientId.isNotEmpty ? savedClientId : kAzureClientId);
      await addOrUpdateAccount(Session(
        id: profile.userPrincipalName,
        accessToken: result.tokens.accessToken,
        refreshToken: result.tokens.refreshToken,
        expiresAt: result.tokens.expiresAt,
        displayName: profile.displayName,
        clientId: savedClientId.isNotEmpty ? savedClientId : kAzureClientId,
        label: result.label.trim().isEmpty ? profile.displayName : result.label.trim(),
        accountHint: profile.userPrincipalName,
      ));
      source = MediaSource.oneDrive;
      await _prefs?.setString('mediaSource', mediaSourceKey(source));
      bootMessage = 'เชื่อม OneDrive แล้ว: ${profile.displayName}';
    } catch (error) {
      bootMessage = friendlyHttpError(error);
    }
  }

  Future<void> _bootProfiles() async {
    profiles = _readList('profiles', UserProfile.fromJson).where((p) => p.id.isNotEmpty).toList();
    activeProfileId = _prefs?.getString('activeProfileId');

    if (profiles.isEmpty) {
      final legacyFav = _readList('favorites', LibraryRef.fromJson);
      final legacyCont = _readList('continueWatching', WatchProgress.fromJson);
      final created = _newProfile(name: tr('defaultProfile'));
      profiles = [created];
      activeProfileId = created.id;
      await _writeProfiles();
      await _prefs?.setString('activeProfileId', created.id);
      favorites = legacyFav;
      continueWatching = legacyCont..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _persistActiveProfileData();
      await _prefs?.remove('favorites');
      await _prefs?.remove('continueWatching');
    } else {
      if (activeProfileId == null || activeProfile == null) {
        activeProfileId = profiles.first.id;
        await _prefs?.setString('activeProfileId', activeProfileId!);
      }
      // ย้ายชื่อเก่า “ของฉัน/Mine” → “โปรไฟล์/Profile”
      var renamed = false;
      final nextProfiles = <UserProfile>[];
      for (final profile in profiles) {
        if (profile.name == 'ของฉัน' || profile.name == 'Mine') {
          nextProfiles.add(profile.copyWith(
            name: tr('defaultProfile'),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
          renamed = true;
        } else {
          nextProfiles.add(profile);
        }
      }
      if (renamed) {
        profiles = nextProfiles;
        await _writeProfiles();
        _scheduleProfileSync();
      }
      await _loadActiveProfileData();
    }
  }

  UserProfile _newProfile({required String name}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final color = _profileColors[profiles.length % _profileColors.length];
    return UserProfile(
      id: 'p_${now}_${Random().nextInt(1 << 20)}',
      name: name.trim().isEmpty ? 'Profile' : name.trim(),
      color: color,
      updatedAt: now,
    );
  }

  String _favKey([String? profileId]) => 'favorites_${profileId ?? activeProfileId ?? 'default'}';

  String _contKey([String? profileId]) => 'continueWatching_${profileId ?? activeProfileId ?? 'default'}';

  Future<void> _loadActiveProfileData() async {
    favorites = _readList(_favKey(), LibraryRef.fromJson);
    continueWatching = _readList(_contKey(), WatchProgress.fromJson)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _persistActiveProfileData() async {
    await _writeList(_favKey(), favorites);
    await _writeList(_contKey(), continueWatching);
    await _touchActiveProfile();
    _scheduleProfileSync();
  }

  Future<void> _touchActiveProfile() async {
    final id = activeProfileId;
    if (id == null) return;
    final index = profiles.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final next = [...profiles];
    next[index] = profiles[index].copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    profiles = next;
    await _writeProfiles();
  }

  Future<void> _writeProfiles() async {
    await _writeList('profiles', profiles);
  }

  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeList(String key, List<dynamic> values) async {
    await _prefs?.setString(key, jsonEncode(values.map((v) => (v as dynamic).toJson()).toList()));
  }

  Future<void> selectProfile(String profileId) async {
    if (activeProfileId == profileId) return;
    final exists = profiles.any((p) => p.id == profileId);
    if (!exists) return;
    activeProfileId = profileId;
    await _prefs?.setString('activeProfileId', profileId);
    await _loadActiveProfileData();
    notifyListeners();
  }

  Future<UserProfile> createProfile(String name) async {
    final profile = _newProfile(name: name);
    profiles = [...profiles, profile];
    await _writeProfiles();
    activeProfileId = profile.id;
    await _prefs?.setString('activeProfileId', profile.id);
    favorites = [];
    continueWatching = [];
    await _persistActiveProfileData();
    notifyListeners();
    return profile;
  }

  Future<void> renameProfile(String profileId, String name) async {
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index < 0) return;
    final nextName = name.trim().isEmpty ? profiles[index].name : name.trim();
    final next = [...profiles];
    next[index] = profiles[index].copyWith(
      name: nextName,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    profiles = next;
    await _writeProfiles();
    _scheduleProfileSync();
    notifyListeners();
  }

  Future<void> deleteProfile(String profileId) async {
    if (profiles.length <= 1) return;
    profiles = profiles.where((p) => p.id != profileId).toList();
    await _prefs?.remove(_favKey(profileId));
    await _prefs?.remove(_contKey(profileId));
    await _writeProfiles();
    if (activeProfileId == profileId) {
      activeProfileId = profiles.first.id;
      await _prefs?.setString('activeProfileId', activeProfileId!);
      await _loadActiveProfileData();
    }
    _scheduleProfileSync();
    notifyListeners();
  }

  void _scheduleProfileSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(pushProfileSync());
    });
  }

  Map<String, dynamic> _buildSyncPayload() {
    final data = <String, dynamic>{};
    for (final profile in profiles) {
      data[profile.id] = {
        'favorites': _readList(_favKey(profile.id), LibraryRef.fromJson).map((e) => e.toJson()).toList(),
        'continueWatching':
            _readList(_contKey(profile.id), WatchProgress.fromJson).map((e) => e.toJson()).toList(),
      };
    }
    return {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'activeProfileId': activeProfileId,
      'profiles': profiles.map((p) => p.toJson()).toList(),
      'data': data,
    };
  }

  Future<void> pullProfileSync() async {
    if (!hasOneDrive) return;
    try {
      syncingProfiles = true;
      lastSyncError = null;
      notifyListeners();
      final token = await getToken();
      var raw = await downloadDriveText(token, kNiceSyncPath);
      // รองรับไฟล์ซิงก์ชื่อเก่า /NICE/
      raw ??= await downloadDriveText(token, kNiceSyncPathLegacy);
      if (raw == null || raw.isEmpty) {
        await pushProfileSync();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      await _mergeRemoteSync(decoded);
      lastSyncError = null;
    } catch (error) {
      lastSyncError = error.toString().replaceFirst('Exception: ', '');
    } finally {
      syncingProfiles = false;
      notifyListeners();
    }
  }

  Future<void> pushProfileSync() async {
    if (!hasOneDrive) return;
    try {
      syncingProfiles = true;
      lastSyncError = null;
      notifyListeners();
      final token = await getToken();
      final payload = _buildSyncPayload();
      await uploadDriveText(token, kNiceSyncPath, jsonEncode(payload));
      lastSyncError = null;
    } catch (error) {
      lastSyncError = error.toString().replaceFirst('Exception: ', '');
    } finally {
      syncingProfiles = false;
      notifyListeners();
    }
  }

  Future<void> _mergeRemoteSync(Map<String, dynamic> remote) async {
    final remoteProfiles = <UserProfile>[];
    final list = remote['profiles'];
    if (list is List) {
      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          final profile = UserProfile.fromJson(entry);
          if (profile.id.isNotEmpty) remoteProfiles.add(profile);
        }
      }
    }
    if (remoteProfiles.isEmpty) return;

    final byId = <String, UserProfile>{for (final p in profiles) p.id: p};
    for (final remoteProfile in remoteProfiles) {
      final local = byId[remoteProfile.id];
      if (local == null || remoteProfile.updatedAt >= local.updatedAt) {
        byId[remoteProfile.id] = remoteProfile;
      }
    }
    profiles = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _writeProfiles();

    final data = remote['data'];
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final profileId = entry.key;
        final localProfile = byId[profileId];
        UserProfile? remoteProfile;
        for (final p in remoteProfiles) {
          if (p.id == profileId) {
            remoteProfile = p;
            break;
          }
        }
        if (localProfile == null || remoteProfile == null) continue;
        // ใช้ข้อมูล remote เมื่อโปรไฟล์ฝั่ง remote ใหม่กว่าหรือเท่ากัน
        final localUpdated = localProfile.updatedAt;
        if (remoteProfile.updatedAt < localUpdated) continue;
        final bag = entry.value;
        if (bag is! Map<String, dynamic>) continue;
        final favs = <LibraryRef>[];
        final cont = <WatchProgress>[];
        final favRaw = bag['favorites'];
        final contRaw = bag['continueWatching'];
        if (favRaw is List) {
          for (final item in favRaw) {
            if (item is Map<String, dynamic>) favs.add(LibraryRef.fromJson(item));
          }
        }
        if (contRaw is List) {
          for (final item in contRaw) {
            if (item is Map<String, dynamic>) cont.add(WatchProgress.fromJson(item));
          }
        }
        await _writeList(_favKey(profileId), favs);
        await _writeList(_contKey(profileId), cont);
      }
    }

    if (activeProfileId == null || activeProfile == null) {
      activeProfileId = profiles.first.id;
      await _prefs?.setString('activeProfileId', activeProfileId!);
    }
    await _loadActiveProfileData();
  }

  Future<void> _refreshActiveIfNeeded() async {
    final current = session;
    if (current == null) return;
    if (current.expiresAt - 60000 > DateTime.now().millisecondsSinceEpoch) return;
    try {
      final renewed = await _renewed(current);
      await _upsertAccount(renewed, select: true);
    } catch (_) {
      // Keep account; refresh again when a token is requested.
    }
  }

  Future<List<Session>> _readAccounts() async {
    String? raw;
    try {
      raw = await _secure.read(key: 'accounts');
    } catch (_) {}
    raw ??= _prefs?.getString('accounts');

    // Migrate legacy single-session storage.
    if (raw == null || raw.isEmpty) {
      String? legacy;
      try {
        legacy = await _secure.read(key: 'session');
      } catch (_) {}
      legacy ??= _prefs?.getString('session');
      if (legacy == null || legacy.isEmpty) return [];
      try {
        final one = Session.fromJson(jsonDecode(legacy) as Map<String, dynamic>);
        await _writeAccounts([one]);
        await _prefs?.remove('session');
        try {
          await _secure.delete(key: 'session');
        } catch (_) {}
        return [one];
      } catch (_) {
        return [];
      }
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().map(Session.fromJson).toList();
      }
      if (decoded is Map<String, dynamic>) {
        return [Session.fromJson(decoded)];
      }
    } catch (_) {
      await _clearAccountsStorage();
    }
    return [];
  }

  Future<void> _writeAccounts(List<Session> next) async {
    final encoded = jsonEncode(next.map((a) => a.toJson()).toList());
    await _prefs?.setString('accounts', encoded);
    try {
      await _secure.write(key: 'accounts', value: encoded);
    } catch (_) {}
  }

  Future<void> _clearAccountsStorage() async {
    await _prefs?.remove('accounts');
    await _prefs?.remove('session');
    await _prefs?.remove('activeAccountId');
    try {
      await _secure.delete(key: 'accounts');
      await _secure.delete(key: 'session');
    } catch (_) {}
  }

  Future<void> _upsertAccount(Session account, {required bool select}) async {
    final next = [...accounts];
    final index = next.indexWhere((a) => a.id.toLowerCase() == account.id.toLowerCase());
    var merged = account;
    if (index >= 0) {
      final existing = next[index];
      // ต่ออายุโทเคน / reconnect แล้วไม่ให้ทับโฟลเดอร์ที่ผู้ใช้ติ๊กไว้
      if (account.libraryFolders.isEmpty && existing.libraryFolders.isNotEmpty) {
        merged = account.copyWith(libraryFolders: existing.libraryFolders);
      }
      next[index] = merged;
    } else {
      next.add(merged);
    }
    accounts = next;
    if (select) {
      activeAccountId = merged.id;
      await _prefs?.setString('activeAccountId', merged.id);
      source = MediaSource.oneDrive;
      await _prefs?.setString('mediaSource', 'oneDrive');
    }
    await _writeAccounts(accounts);
    notifyListeners();
    unawaited(pullProfileSync());
  }

  Future<void> setAccountLibraryFolders(
    String accountId,
    List<SelectedLibraryFolder> folders,
  ) async {
    final index = accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return;
    final cleaned = <SelectedLibraryFolder>[];
    final seen = <String>{};
    for (final folder in folders) {
      final id = folder.id.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      cleaned.add(SelectedLibraryFolder(
        id: id,
        name: folder.name.trim().isEmpty ? id : folder.name.trim(),
      ));
    }
    final next = [...accounts];
    next[index] = accounts[index].copyWith(libraryFolders: cleaned);
    accounts = next;
    await _writeAccounts(accounts);
    notifyListeners();
  }

  Future<void> setLang(AppLang next) async {
    if (lang == next) return;
    lang = next;
    await _prefs?.setString('appLang', next.code);
    notifyListeners();
  }

  Future<void> setSource(MediaSource next) async {
    if (next == MediaSource.oneDrive && accounts.isEmpty) {
      throw Exception('ยังไม่ได้เชื่อม OneDrive');
    }
    source = next;
    await _prefs?.setString('mediaSource', mediaSourceKey(next));
    notifyListeners();
  }

  Future<void> openOverview() => setSource(MediaSource.overview);

  bool isFavorite(String key) => favorites.any((f) => f.key == key);

  Future<void> toggleFavorite(LibraryRef ref) async {
    final exists = favorites.any((f) => f.key == ref.key);
    if (exists) {
      favorites = favorites.where((f) => f.key != ref.key).toList();
    } else {
      favorites = [ref, ...favorites];
    }
    await _persistActiveProfileData();
    notifyListeners();
  }

  Future<void> saveWatchProgress({
    required LibraryRef ref,
    required int positionMs,
    required int durationMs,
  }) async {
    if (durationMs <= 0) return;
    // Ignore very start / near end
    if (positionMs < 15000) {
      continueWatching = continueWatching.where((w) => w.ref.key != ref.key).toList();
      await _persistActiveProfileData();
      notifyListeners();
      return;
    }
    if (positionMs / durationMs >= 0.92) {
      continueWatching = continueWatching.where((w) => w.ref.key != ref.key).toList();
      await _persistActiveProfileData();
      notifyListeners();
      return;
    }
    final entry = WatchProgress(
      ref: ref,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    continueWatching = [entry, ...continueWatching.where((w) => w.ref.key != ref.key)].take(40).toList();
    await _persistActiveProfileData();
    notifyListeners();
  }

  WatchProgress? progressFor(String key) {
    for (final item in continueWatching) {
      if (item.ref.key == key) return item;
    }
    return null;
  }

  Future<void> markFinished(String key) async {
    continueWatching = continueWatching.where((w) => w.ref.key != key).toList();
    await _persistActiveProfileData();
    notifyListeners();
  }

  Future<void> selectAccount(String accountId) async {
    final exists = accounts.any((a) => a.id == accountId);
    if (!exists) throw Exception('ไม่พบบัญชีนี้');
    activeAccountId = accountId;
    await _prefs?.setString('activeAccountId', accountId);
    source = MediaSource.oneDrive;
    await _prefs?.setString('mediaSource', 'oneDrive');
    notifyListeners();
  }

  Future<void> setLocalRoot(String path, {String? label}) async {
    localRootPath = path;
    await _prefs?.setString('localRootPath', path);
    if (label != null && label.isNotEmpty) {
      await _prefs?.setString('localRootLabel', label);
    }
    source = MediaSource.local;
    await _prefs?.setString('mediaSource', 'local');
    notifyListeners();
  }

  Future<void> saveOneDriveLabel(String label) async {
    final current = session;
    if (current == null) return;
    await renameAccount(current.id, label);
  }

  Future<void> renameAccount(String accountId, String label) async {
    final index = accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return;
    final nextLabel = label.trim().isEmpty ? 'My OneDrive' : label.trim();
    final updated = accounts[index].copyWith(label: nextLabel);
    final next = [...accounts];
    next[index] = updated;
    accounts = next;
    await _writeAccounts(accounts);
    notifyListeners();
  }

  Future<void> addOrUpdateAccount(Session account) async {
    await _upsertAccount(account, select: true);
  }

  Future<void> saveClientId(String clientId) async {
    savedClientId = clientId;
    await _prefs?.setString('clientId', clientId);
    notifyListeners();
  }

  void clearBootMessage() {
    if (bootMessage == null) return;
    bootMessage = null;
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

  Future<void> removeAccount(String accountId) async {
    accounts = accounts.where((a) => a.id != accountId).toList();
    await _writeAccounts(accounts);
    if (accounts.isEmpty) {
      activeAccountId = null;
      await _prefs?.remove('activeAccountId');
      if (source == MediaSource.oneDrive) {
        source = MediaSource.overview;
        await _prefs?.setString('mediaSource', mediaSourceKey(source));
      }
    } else if (activeAccountId == accountId) {
      activeAccountId = accounts.first.id;
      await _prefs?.setString('activeAccountId', activeAccountId!);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final current = session;
    if (current != null) {
      await removeAccount(current.id);
      return;
    }
    accounts = [];
    activeAccountId = null;
    await _clearAccountsStorage();
    if (source == MediaSource.oneDrive) {
      source = MediaSource.overview;
      await _prefs?.setString('mediaSource', mediaSourceKey(source));
    }
    notifyListeners();
  }

  Session? accountById(String? accountId) {
    if (accountId == null) return session;
    for (final account in accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  Future<String> getToken({String? accountId}) async {
    final current = accountById(accountId) ?? session;
    if (current == null) throw Exception('ยังไม่ได้เชื่อม OneDrive');
    if (current.expiresAt - 60000 > DateTime.now().millisecondsSinceEpoch) return current.accessToken;

    return _refreshingById.putIfAbsent(current.id, () => _refresh(current));
  }

  Future<String> _refresh(Session current) async {
    try {
      final next = await _renewed(current);
      await _upsertAccount(next, select: activeAccountId == current.id);
      return next.accessToken;
    } catch (error) {
      final message = error.toString();
      final fatal = message.contains('invalid_grant') ||
          message.contains('AADSTS') ||
          message.contains('Client ID');
      if (fatal) {
        await removeAccount(current.id);
        throw Exception('เซสชันหมดอายุ เชื่อม OneDrive ใหม่');
      }
      throw Exception('ต่ออายุการเข้าสู่ระบบไม่สำเร็จ ลองรีเฟรชอีกครั้ง');
    } finally {
      _refreshingById.remove(current.id);
    }
  }

  Future<Session> _renewed(Session current) async {
    final clientId = current.clientId.isNotEmpty ? current.clientId : kAzureClientId;
    final tokens = await refreshTokens(clientId, current.refreshToken);
    return current.copyWith(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
    );
  }

  String suggestedOneDriveLabel() {
    final n = accounts.length + 1;
    return n <= 1 ? 'My OneDrive' : 'My OneDrive $n';
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    super.dispose();
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

import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/network/dio_failure.dart';
import '../../domain/entities/device_login.dart';
import '../../domain/entities/session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/microsoft_auth_remote_data_source.dart';
import '../models/auth_models.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required MicrosoftAuthRemoteDataSource remote,
    required AuthLocalDataSource local,
    DateTime Function()? now,
  }) : _remote = remote,
       _local = local,
       _now = now ?? DateTime.now;

  final MicrosoftAuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
  final DateTime Function() _now;
  final _sessions = StreamController<Session?>.broadcast();

  Session? _session;
  Future<String>? _refreshing;

  /// error ที่แปลว่า refresh token หรือแอปใน Azure ใช้ต่อไม่ได้แล้ว ต้องเข้าสู่ระบบใหม่เท่านั้น
  static const _deadSessionErrors = {'invalid_grant', 'interaction_required', 'invalid_client', 'unauthorized_client'};

  @override
  Stream<Session?> get sessionChanges => _sessions.stream;

  @override
  Session? get currentSession => _session;

  @override
  Future<Session?> restoreSession() async {
    _session = await _local.readSession();
    if (_session == null) await _local.deleteSession();
    return _session;
  }

  @override
  Future<String> savedClientId() => _local.readClientId();

  @override
  Future<DeviceLogin> startDeviceLogin(String clientId) async {
    await _local.writeClientId(clientId);
    final DeviceCodeModel body;
    try {
      body = await _remote.requestDeviceCode(clientId);
    } on DioException catch (error) {
      throw _transportFailure(error);
    }
    final userCode = body.userCode;
    final deviceCode = body.deviceCode;
    final verificationUri = Uri.tryParse(body.verificationUri ?? '');
    if (userCode == null || deviceCode == null || verificationUri == null || !verificationUri.hasScheme) {
      throw AuthFailure(friendlyAuthError(body.error, body.errorDescription));
    }
    return DeviceLogin(
      clientId: clientId,
      userCode: userCode,
      deviceCode: deviceCode,
      verificationUri: verificationUri,
      interval: Duration(seconds: body.interval ?? 5),
    );
  }

  @override
  Future<DevicePollResult> pollDeviceLogin(DeviceLogin login) async {
    final TokenResponseModel body;
    try {
      body = await _remote.pollDeviceToken(clientId: login.clientId, deviceCode: login.deviceCode);
    } on DioException catch (error) {
      throw _transportFailure(error);
    }

    final tokens = body.toTokenSet(now: _now());
    if (tokens != null) {
      final session = Session(
        tokens: tokens,
        displayName: await _profileName(tokens.accessToken),
        clientId: login.clientId,
      );
      await _save(session);
      return DevicePollSuccess(session);
    }

    return switch (body.error) {
      'authorization_pending' => const DevicePollPending(),
      'slow_down' => const DevicePollSlowDown(),
      'expired_token' => const DevicePollExpired(),
      'authorization_declined' || 'access_denied' => const DevicePollDenied(),
      _ => throw AuthFailure(friendlyAuthError(body.error, body.errorDescription)),
    };
  }

  @override
  Future<String> validAccessToken({bool forceRefresh = false}) {
    final session = _session;
    if (session == null) return Future.error(const SessionExpiredFailure());
    if (!forceRefresh && !session.isExpiredAt(_now())) return Future.value(session.tokens.accessToken);
    return _refreshing ??= _refresh(session).whenComplete(() => _refreshing = null);
  }

  @override
  Future<void> signOut() async {
    await _local.deleteSession();
    _setSession(null);
  }

  Future<String> _refresh(Session session) async {
    final TokenResponseModel body;
    try {
      body = await _remote.refresh(clientId: session.clientId, refreshToken: session.tokens.refreshToken);
    } on DioException catch (error) {
      throw _transportFailure(error);
    }

    final tokens = body.toTokenSet(now: _now(), previousRefreshToken: session.tokens.refreshToken);
    if (tokens == null) {
      if (_deadSessionErrors.contains(body.error)) {
        await signOut();
        throw const SessionExpiredFailure();
      }
      throw AuthFailure(friendlyAuthError(body.error, body.errorDescription));
    }

    final next = session.withTokens(tokens);
    await _save(next);
    return tokens.accessToken;
  }

  Future<String> _profileName(String accessToken) async {
    try {
      return await _remote.fetchProfileName(accessToken) ?? 'OneDrive';
    } on DioException {
      // ชื่อบัญชีใช้แสดงผลอย่างเดียว ไม่ควรทำให้การเข้าสู่ระบบที่สำเร็จแล้วล้ม
      return 'OneDrive';
    }
  }

  Future<void> _save(Session session) async {
    await _local.writeSession(session);
    _setSession(session);
  }

  void _setSession(Session? session) {
    _session = session;
    _sessions.add(session);
  }

  Failure _transportFailure(DioException error) {
    if (isConnectionError(error)) return const NetworkFailure();
    return const ServerFailure('เซิร์ฟเวอร์ Microsoft ไม่ตอบ ลองใหม่อีกครั้ง');
  }
}

String friendlyAuthError(String? error, String? description) {
  final text = description ?? '';
  if (text.contains('7000218')) return 'ใน Azure ยังไม่ได้เปิด Allow public client flows';
  if (text.contains('700016')) return 'ไม่พบแอปนี้ ตรวจ Application (client) ID';
  if (text.contains('65001')) return 'บัญชียังไม่ได้อนุญาตให้แอปอ่านไฟล์';
  if (error == 'invalid_client') return 'Client ID ไม่ถูกต้อง หรือยังไม่ได้เปิด public client flows';
  final code = RegExp(r'AADSTS\d+').firstMatch(text)?.group(0);
  return code != null ? 'เข้าสู่ระบบไม่สำเร็จ ($code)' : 'เข้าสู่ระบบไม่สำเร็จ ตรวจการตั้งค่าแอปใน Azure';
}

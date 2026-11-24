import '../entities/device_login.dart';
import '../entities/session.dart';

abstract interface class AuthRepository {
  Stream<Session?> get sessionChanges;

  Session? get currentSession;

  /// อ่านเซสชันที่บันทึกไว้โดยไม่ refresh token เพื่อให้เปิดแอปตอนออฟไลน์แล้วไม่หลุดออกจากระบบ
  Future<Session?> restoreSession();

  Future<String> savedClientId();

  Future<DeviceLogin> startDeviceLogin(String clientId);

  Future<DevicePollResult> pollDeviceLogin(DeviceLogin login);

  /// คืน access token ที่ยังใช้ได้ และ refresh ให้ถ้าหมดอายุ
  /// จะลบเซสชันเฉพาะตอนที่ Microsoft ปฏิเสธ refresh token เท่านั้น
  Future<String> validAccessToken({bool forceRefresh = false});

  Future<void> signOut();
}

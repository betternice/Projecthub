/// ข้อผิดพลาดระดับ domain ที่ชั้น presentation แสดงข้อความให้ผู้ใช้ได้ตรงๆ
sealed class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'เชื่อมต่อไม่ได้ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง']);
}

/// เซสชันใช้ต่อไม่ได้แล้ว ผู้ใช้ต้องเข้าสู่ระบบใหม่
class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure([super.message = 'เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง']);
}

/// Microsoft ปฏิเสธการเข้าสู่ระบบ มักมาจากการตั้งค่าแอปใน Azure
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'บัญชีนี้ยังไม่ได้รับสิทธิ์อ่านไฟล์ใน OneDrive']);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

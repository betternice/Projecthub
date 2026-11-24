import '../../domain/entities/session.dart';

/// คำตอบจาก endpoint `/token` ของ Microsoft identity platform ทั้งกรณีสำเร็จและ error
class TokenResponseModel {
  const TokenResponseModel({
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.error,
    this.errorDescription,
  });

  factory TokenResponseModel.fromJson(Map<String, dynamic> json) => TokenResponseModel(
    accessToken: json['access_token'] as String?,
    refreshToken: json['refresh_token'] as String?,
    expiresIn: (json['expires_in'] as num?)?.toInt(),
    error: json['error'] as String?,
    errorDescription: json['error_description'] as String?,
  );

  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? error;
  final String? errorDescription;

  TokenSet? toTokenSet({required DateTime now, String previousRefreshToken = ''}) {
    final access = accessToken;
    if (access == null || access.isEmpty) return null;
    final refresh = refreshToken;
    return TokenSet(
      accessToken: access,
      refreshToken: refresh == null || refresh.isEmpty ? previousRefreshToken : refresh,
      expiresAt: now.add(Duration(seconds: expiresIn ?? 3600)),
    );
  }
}

class DeviceCodeModel {
  const DeviceCodeModel({
    this.userCode,
    this.deviceCode,
    this.verificationUri,
    this.interval,
    this.error,
    this.errorDescription,
  });

  factory DeviceCodeModel.fromJson(Map<String, dynamic> json) => DeviceCodeModel(
    userCode: json['user_code'] as String?,
    deviceCode: json['device_code'] as String?,
    verificationUri: json['verification_uri'] as String?,
    interval: (json['interval'] as num?)?.toInt(),
    error: json['error'] as String?,
    errorDescription: json['error_description'] as String?,
  );

  final String? userCode;
  final String? deviceCode;
  final String? verificationUri;
  final int? interval;
  final String? error;
  final String? errorDescription;
}

/// รูปแบบที่ใช้เก็บเซสชันลง secure storage
class SessionModel {
  const SessionModel(this.session);

  final Session session;

  static Session? tryParse(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expiresAt = json['expiresAt'];
    final clientId = json['clientId'];
    if (access is! String || refresh is! String || expiresAt is! num || clientId is! String) return null;
    return Session(
      tokens: TokenSet(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt()),
      ),
      displayName: json['displayName'] as String? ?? 'OneDrive',
      clientId: clientId,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': session.tokens.accessToken,
    'refreshToken': session.tokens.refreshToken,
    'expiresAt': session.tokens.expiresAt.millisecondsSinceEpoch,
    'displayName': session.displayName,
    'clientId': session.clientId,
  };
}

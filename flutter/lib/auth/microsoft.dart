import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

const _tenant = 'common';
const _scope = 'offline_access User.Read Files.Read';
final _deviceUrl = Uri.parse('https://login.microsoftonline.com/$_tenant/oauth2/v2.0/devicecode');
final _tokenUrl = Uri.parse('https://login.microsoftonline.com/$_tenant/oauth2/v2.0/token');

class DeviceLogin {
  const DeviceLogin({
    required this.userCode,
    required this.deviceCode,
    required this.verificationUri,
    required this.interval,
  });

  final String userCode;
  final String deviceCode;
  final String verificationUri;
  final int interval;
}

class DevicePoll {
  const DevicePoll({required this.status, this.tokens});

  final String status;
  final TokenSet? tokens;
}

String friendlyAuthError(Map<String, dynamic> body) {
  final description = body['error_description'] as String? ?? '';
  final code = RegExp(r'AADSTS\d+').firstMatch(description)?.group(0);
  if (description.contains('7000218')) return 'ใน Azure ยังไม่ได้เปิด Allow public client flows';
  if (description.contains('700016')) return 'ไม่พบแอปนี้ ตรวจ Application (client) ID';
  if (description.contains('65001')) return 'บัญชียังไม่ได้อนุญาตให้แอปอ่านไฟล์';
  if (body['error'] == 'invalid_client') return 'Client ID ไม่ถูกต้อง หรือยังไม่ได้เปิด public client flows';
  return code != null ? 'เข้าสู่ระบบไม่สำเร็จ ($code)' : 'เข้าสู่ระบบไม่สำเร็จ ตรวจการตั้งค่าแอปใน Azure';
}

TokenSet _toTokenSet(Map<String, dynamic> body, [String previousRefresh = '']) {
  final access = body['access_token'] as String?;
  if (access == null || access.isEmpty) throw Exception(friendlyAuthError(body));
  final expiresIn = body['expires_in'] as int? ?? 3600;
  return TokenSet(
    accessToken: access,
    refreshToken: body['refresh_token'] as String? ?? previousRefresh,
    expiresAt: DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
  );
}

Future<Map<String, dynamic>> _postForm(Uri url, Map<String, String> fields) async {
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: fields,
  );
  final decoded = jsonDecode(response.body);
  final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  body['_status'] = response.statusCode;
  return body;
}

Future<DeviceLogin> requestDeviceCode(String clientId) async {
  final body = await _postForm(_deviceUrl, {'client_id': clientId, 'scope': _scope});
  final ok = body['_status'] == 200;
  final userCode = body['user_code'] as String?;
  final deviceCode = body['device_code'] as String?;
  final verification = body['verification_uri'] as String?;
  if (!ok || userCode == null || deviceCode == null || verification == null) {
    throw Exception(friendlyAuthError(body));
  }
  return DeviceLogin(
    userCode: userCode,
    deviceCode: deviceCode,
    verificationUri: verification,
    interval: body['interval'] as int? ?? 5,
  );
}

Future<DevicePoll> pollDeviceToken(String clientId, String deviceCode) async {
  final body = await _postForm(_tokenUrl, {
    'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    'client_id': clientId,
    'device_code': deviceCode,
  });
  if (body['_status'] == 200 && body['access_token'] != null) {
    return DevicePoll(status: 'success', tokens: _toTokenSet(body));
  }
  switch (body['error']) {
    case 'authorization_pending':
      return const DevicePoll(status: 'pending');
    case 'slow_down':
      return const DevicePoll(status: 'slow_down');
    case 'expired_token':
      return const DevicePoll(status: 'expired');
    case 'authorization_declined':
    case 'access_denied':
      return const DevicePoll(status: 'denied');
    default:
      throw Exception(friendlyAuthError(body));
  }
}

Future<TokenSet> refreshTokens(String clientId, String refreshToken) async {
  final body = await _postForm(_tokenUrl, {
    'client_id': clientId,
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'scope': _scope,
  });
  if (body['_status'] != 200) throw Exception(friendlyAuthError(body));
  return _toTokenSet(body, refreshToken);
}

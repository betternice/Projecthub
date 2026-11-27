import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'azure_config.dart';
import 'web_nav.dart';

const _tenant = 'common';
const _scope = 'offline_access User.Read Files.Read';
final _deviceUrl = Uri.parse('https://login.microsoftonline.com/$_tenant/oauth2/v2.0/devicecode');
final _tokenUrl = Uri.parse('https://login.microsoftonline.com/$_tenant/oauth2/v2.0/token');
final _authorizeUrl = Uri.parse('https://login.microsoftonline.com/$_tenant/oauth2/v2.0/authorize');

const _kVerifier = 'ms_oauth_code_verifier';
const _kLabel = 'ms_oauth_account_label';
const _kPending = 'ms_oauth_pending';

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
  if (description.contains('50011') || description.contains('redirect_uri')) {
    return 'ยังไม่ได้เพิ่ม Redirect URI แบบ SPA ใน Azure: $kAzureSpaRedirectHint';
  }
  if (body['error'] == 'invalid_client') return 'Client ID ไม่ถูกต้อง หรือยังไม่ได้เปิด public client flows';
  return code != null ? 'เข้าสู่ระบบไม่สำเร็จ ($code)' : 'เข้าสู่ระบบไม่สำเร็จ ตรวจการตั้งค่าแอปใน Azure';
}

String friendlyHttpError(Object error) {
  final text = error.toString();
  if (text.contains('Failed to fetch') || text.contains('ClientException') || text.contains('XMLHttpRequest')) {
    return 'เบราว์เซอร์บล็อกการล็อกอินแบบ TV — ใช้ปุ่ม Add อีกครั้งหลังอัปเดต (เว็บใช้ Microsoft login แบบ redirect)';
  }
  return text.replaceFirst('Exception: ', '');
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

String _randomVerifier() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _s256Challenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// Auth Code + PKCE for Flutter web (device code is blocked by browser CORS).
Future<void> startWebMicrosoftLogin({
  required String clientId,
  required String accountLabel,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final verifier = _randomVerifier();
  final challenge = _s256Challenge(verifier);
  final redirectUri = webRedirectUri();

  await prefs.setString(_kVerifier, verifier);
  await prefs.setString(_kLabel, accountLabel);
  await prefs.setBool(_kPending, true);

  final authUri = _authorizeUrl.replace(queryParameters: {
    'client_id': clientId,
    'response_type': 'code',
    'redirect_uri': redirectUri,
    'response_mode': 'query',
    'scope': _scope,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    'prompt': 'select_account',
  });

  navigateToExternal(authUri.toString());
}

class WebOAuthResult {
  const WebOAuthResult({required this.tokens, required this.label});

  final TokenSet tokens;
  final String label;
}

/// Completes web OAuth after Microsoft redirects back with ?code=...
Future<WebOAuthResult?> completeWebMicrosoftLoginIfNeeded(String clientId) async {
  final uri = Uri.base;
  final error = uri.queryParameters['error'];
  final errorDesc = uri.queryParameters['error_description'];
  final code = uri.queryParameters['code'];

  if (error == null && code == null) return null;

  final prefs = await SharedPreferences.getInstance();
  final clean = webRedirectUri();

  if (error != null) {
    await prefs.remove(_kPending);
    await prefs.remove(_kVerifier);
    replaceBrowserUrl(clean);
    throw Exception(
      errorDesc?.isNotEmpty == true
          ? friendlyAuthError({'error': error, 'error_description': errorDesc})
          : 'ยกเลิกหรือเข้าสู่ระบบไม่สำเร็จ',
    );
  }

  final verifier = prefs.getString(_kVerifier);
  final label = prefs.getString(_kLabel) ?? 'My OneDrive';
  if (verifier == null || verifier.isEmpty) {
    replaceBrowserUrl(clean);
    throw Exception('เซสชันล็อกอินเว็บหาย ลอง Add OneDrive อีกครั้ง');
  }

  try {
    final body = await _postForm(_tokenUrl, {
      'client_id': clientId,
      'grant_type': 'authorization_code',
      'code': code!,
      'redirect_uri': clean,
      'code_verifier': verifier,
      'scope': _scope,
    });
    if (body['_status'] != 200) throw Exception(friendlyAuthError(body));
    final tokens = _toTokenSet(body);
    return WebOAuthResult(tokens: tokens, label: label);
  } finally {
    await prefs.remove(_kPending);
    await prefs.remove(_kVerifier);
    await prefs.remove(_kLabel);
    replaceBrowserUrl(clean);
  }
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

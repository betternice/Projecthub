import 'package:dio/dio.dart';

import '../models/auth_models.dart';

class MicrosoftAuthRemoteDataSource {
  MicrosoftAuthRemoteDataSource(this._dio);

  final Dio _dio;

  static const _base = 'https://login.microsoftonline.com/common/oauth2/v2.0';
  static const _scope = 'offline_access User.Read Files.Read';

  /// Microsoft ตอบ error ของ OAuth เป็น HTTP 400 พร้อม JSON จึงต้องอ่าน body ทุก status
  static final _formOptions = Options(
    contentType: Headers.formUrlEncodedContentType,
    responseType: ResponseType.json,
    validateStatus: (status) => status != null && status < 500,
  );

  Future<DeviceCodeModel> requestDeviceCode(String clientId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/devicecode',
      data: {'client_id': clientId, 'scope': _scope},
      options: _formOptions,
    );
    return DeviceCodeModel.fromJson(response.data ?? const {});
  }

  Future<TokenResponseModel> pollDeviceToken({required String clientId, required String deviceCode}) {
    return _token({
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      'client_id': clientId,
      'device_code': deviceCode,
    });
  }

  Future<TokenResponseModel> refresh({required String clientId, required String refreshToken}) {
    return _token({
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': refreshToken,
      'scope': _scope,
    });
  }

  Future<String?> fetchProfileName(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://graph.microsoft.com/v1.0/me',
      queryParameters: {r'$select': 'displayName,userPrincipalName'},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final body = response.data ?? const {};
    final displayName = body['displayName'] as String?;
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return body['userPrincipalName'] as String?;
  }

  Future<TokenResponseModel> _token(Map<String, String> form) async {
    final response = await _dio.post<Map<String, dynamic>>('$_base/token', data: form, options: _formOptions);
    return TokenResponseModel.fromJson(response.data ?? const {});
  }
}

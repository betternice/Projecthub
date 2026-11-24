import 'package:dio/dio.dart';

import '../error/failures.dart';

typedef AccessTokenProvider = Future<String> Function({bool forceRefresh});

/// ใส่ Bearer token ให้ทุก request ของ Microsoft Graph และลองใหม่ 1 ครั้งด้วย token ใหม่เมื่อเจอ 401
class GraphAuthInterceptor extends Interceptor {
  GraphAuthInterceptor({required Dio dio, required AccessTokenProvider accessToken})
    : _dio = dio,
      _accessToken = accessToken;

  final Dio _dio;
  final AccessTokenProvider _accessToken;

  static const _retriedKey = 'graph_auth_retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final forceRefresh = options.extra[_retriedKey] == true;
      options.headers['Authorization'] = 'Bearer ${await _accessToken(forceRefresh: forceRefresh)}';
      handler.next(options);
    } on Failure catch (failure) {
      handler.reject(DioException(requestOptions: options, error: failure));
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }
    try {
      options.extra[_retriedKey] = true;
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}

import 'package:dio/dio.dart';

import '../error/failures.dart';

bool isConnectionError(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => true,
    _ => false,
  };
}

/// แปลง [DioException] จาก Graph เป็น [Failure] โดยเก็บ [Failure] ที่ interceptor โยนมาไว้ตามเดิม
Failure graphFailure(DioException error, {required String fallback}) {
  final cause = error.error;
  if (cause is Failure) return cause;
  if (isConnectionError(error)) return const NetworkFailure();
  return switch (error.response?.statusCode) {
    401 => const SessionExpiredFailure(),
    403 => const PermissionFailure(),
    _ => ServerFailure(fallback),
  };
}

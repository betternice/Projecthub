import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:movie_collection/core/error/failures.dart';
import 'package:movie_collection/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:movie_collection/features/auth/data/datasources/microsoft_auth_remote_data_source.dart';
import 'package:movie_collection/features/auth/data/models/auth_models.dart';
import 'package:movie_collection/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:movie_collection/features/auth/domain/entities/session.dart';

class _Remote extends Mock implements MicrosoftAuthRemoteDataSource {}

class _Local extends Mock implements AuthLocalDataSource {}

void main() {
  final now = DateTime(2026, 11, 24, 12);
  final expired = Session(
    tokens: TokenSet(accessToken: 'old', refreshToken: 'refresh', expiresAt: now.subtract(const Duration(minutes: 5))),
    displayName: 'Skyline',
    clientId: 'client',
  );

  late _Remote remote;
  late _Local local;
  late AuthRepositoryImpl repository;

  setUpAll(() => registerFallbackValue(expired));

  setUp(() async {
    remote = _Remote();
    local = _Local();
    when(() => local.readSession()).thenAnswer((_) async => expired);
    when(() => local.writeSession(any())).thenAnswer((_) async {});
    when(() => local.deleteSession()).thenAnswer((_) async {});
    repository = AuthRepositoryImpl(remote: remote, local: local, now: () => now);
    await repository.restoreSession();
  });

  test('เปิดแอปแล้วไม่ refresh ทันที เซสชันที่หมดอายุยังอยู่จนกว่าจะเรียก API', () {
    expect(repository.currentSession, expired);
    verifyNever(() => remote.refresh(clientId: any(named: 'clientId'), refreshToken: any(named: 'refreshToken')));
  });

  test('เน็ตหลุดตอน refresh ไม่ลบเซสชัน', () async {
    when(
      () => remote.refresh(clientId: 'client', refreshToken: 'refresh'),
    ).thenThrow(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError));

    await expectLater(repository.validAccessToken(), throwsA(isA<NetworkFailure>()));
    expect(repository.currentSession, expired);
    verifyNever(() => local.deleteSession());
  });

  test('Microsoft ตอบ invalid_grant ให้ลบเซสชันและแจ้งให้เข้าสู่ระบบใหม่', () async {
    when(
      () => remote.refresh(clientId: 'client', refreshToken: 'refresh'),
    ).thenAnswer((_) async => const TokenResponseModel(error: 'invalid_grant'));

    final emitted = expectLater(repository.sessionChanges, emits(isNull));
    await expectLater(repository.validAccessToken(), throwsA(isA<SessionExpiredFailure>()));
    await emitted;
    expect(repository.currentSession, isNull);
    verify(() => local.deleteSession()).called(1);
  });

  test('เรียกพร้อมกันหลายที่ refresh แค่ครั้งเดียว และเก็บ refresh token เดิมถ้าไม่ได้ตัวใหม่', () async {
    when(
      () => remote.refresh(clientId: 'client', refreshToken: 'refresh'),
    ).thenAnswer((_) async => const TokenResponseModel(accessToken: 'new', expiresIn: 3600));

    final tokens = await Future.wait([repository.validAccessToken(), repository.validAccessToken()]);

    expect(tokens, ['new', 'new']);
    expect(repository.currentSession?.tokens.refreshToken, 'refresh');
    verify(() => remote.refresh(clientId: 'client', refreshToken: 'refresh')).called(1);
  });
}

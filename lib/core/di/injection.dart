import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/microsoft_auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/auth_usecases.dart';
import '../../features/auth/presentation/cubit/session_cubit.dart';
import '../../features/auth/presentation/cubit/sign_in_cubit.dart';
import '../../features/library/data/datasources/folder_trail_local_data_source.dart';
import '../../features/library/data/datasources/onedrive_remote_data_source.dart';
import '../../features/library/data/repositories/drive_repository_impl.dart';
import '../../features/library/domain/repositories/drive_repository.dart';
import '../../features/library/domain/usecases/library_usecases.dart';
import '../../features/library/presentation/cubit/library_cubit.dart';
import '../../features/metadata/data/datasources/tmdb_remote_data_source.dart';
import '../../features/metadata/data/datasources/wiki_remote_data_source.dart';
import '../../features/metadata/data/repositories/metadata_repository_impl.dart';
import '../../features/metadata/domain/repositories/metadata_repository.dart';
import '../../features/metadata/domain/usecases/metadata_usecases.dart';
import '../../features/movie_detail/presentation/cubit/movie_detail_cubit.dart';
import '../../features/movie_detail/presentation/pages/movie_detail_page.dart';
import '../../features/settings/data/datasources/settings_local_data_source.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settings/domain/usecases/settings_usecases.dart';
import '../network/graph_auth_interceptor.dart';

final sl = GetIt.instance;

const _graphDio = 'graph';
const _plainDio = 'plain';

void configureDependencies() {
  _core();
  _auth();
  _settings();
  _library();
  _metadata();
  _presentation();
}

void _core() {
  const timeouts = (connect: Duration(seconds: 15), receive: Duration(seconds: 30));
  sl
    ..registerLazySingleton(() => const FlutterSecureStorage())
    ..registerLazySingleton(SharedPreferencesAsync.new)
    ..registerLazySingleton(
      () => Dio(BaseOptions(connectTimeout: timeouts.connect, receiveTimeout: timeouts.receive)),
      instanceName: _plainDio,
    )
    ..registerLazySingleton(instanceName: _graphDio, () {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://graph.microsoft.com/v1.0',
          connectTimeout: timeouts.connect,
          receiveTimeout: timeouts.receive,
        ),
      );
      final auth = sl<AuthRepository>();
      dio.interceptors.add(GraphAuthInterceptor(dio: dio, accessToken: auth.validAccessToken));
      return dio;
    });
}

void _auth() {
  sl
    ..registerLazySingleton(() => MicrosoftAuthRemoteDataSource(sl(instanceName: _plainDio)))
    ..registerLazySingleton(() => AuthLocalDataSource(sl()))
    ..registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(remote: sl(), local: sl()))
    ..registerLazySingleton(() => RestoreSession(sl()))
    ..registerLazySingleton(() => WatchSession(sl()))
    ..registerLazySingleton(() => GetSavedClientId(sl()))
    ..registerLazySingleton(() => StartDeviceLogin(sl()))
    ..registerLazySingleton(() => PollDeviceLogin(sl()))
    ..registerLazySingleton(() => SignOut(sl()));
}

void _settings() {
  sl
    ..registerLazySingleton(() => SettingsLocalDataSource(sl()))
    ..registerLazySingleton<SettingsRepository>(() => SettingsRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetTmdbApiKey(sl()))
    ..registerLazySingleton(() => SaveTmdbApiKey(sl()));
}

void _library() {
  sl
    ..registerLazySingleton(() => OneDriveRemoteDataSource(sl(instanceName: _graphDio)))
    ..registerLazySingleton(() => FolderTrailLocalDataSource(sl()))
    ..registerLazySingleton<DriveRepository>(() => DriveRepositoryImpl(remote: sl(), local: sl()))
    ..registerLazySingleton(() => ListFolder(sl()))
    ..registerLazySingleton(() => GetPlaybackUrl(sl()))
    ..registerLazySingleton(() => LoadFolderTrail(sl()))
    ..registerLazySingleton(() => SaveFolderTrail(sl()));
}

void _metadata() {
  sl
    ..registerLazySingleton(() => TmdbRemoteDataSource(sl(instanceName: _plainDio)))
    ..registerLazySingleton(() => WikiRemoteDataSource(sl(instanceName: _plainDio)))
    ..registerLazySingleton<MetadataRepository>(() => MetadataRepositoryImpl(tmdb: sl(), wiki: sl()))
    ..registerLazySingleton(() => LookupMedia(sl()))
    ..registerLazySingleton(() => LookupMediaDetail(sl()));
}

/// cubit ที่ผูกกับหน้าจอเป็น factory เพื่อให้เข้าสู่ระบบใหม่แล้วไม่เห็น state ของบัญชีเก่า
void _presentation() {
  sl
    ..registerLazySingleton(() => SessionCubit(restoreSession: sl(), watchSession: sl(), signOut: sl()))
    ..registerFactory(
      () => SignInCubit(
        getSavedClientId: sl(),
        startDeviceLogin: sl(),
        pollDeviceLogin: sl(),
        getTmdbApiKey: sl(),
        saveTmdbApiKey: sl(),
      ),
    )
    ..registerFactory(
      () => LibraryCubit(
        listFolder: sl(),
        loadFolderTrail: sl(),
        saveFolderTrail: sl(),
        lookupMedia: sl(),
        getTmdbApiKey: sl(),
        saveTmdbApiKey: sl(),
      ),
    )
    ..registerFactoryParam<MovieDetailCubit, MovieDetailArgs, void>(
      (args, _) => MovieDetailCubit(
        item: args.item,
        match: args.match,
        lookupMedia: sl(),
        lookupMediaDetail: sl(),
        getTmdbApiKey: sl(),
        getPlaybackUrl: sl(),
      ),
    );
}

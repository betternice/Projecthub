import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:movie_collection/core/error/failures.dart';
import 'package:movie_collection/features/library/domain/entities/drive_item.dart';
import 'package:movie_collection/features/library/domain/repositories/drive_repository.dart';
import 'package:movie_collection/features/library/domain/usecases/library_usecases.dart';
import 'package:movie_collection/features/library/presentation/cubit/library_cubit.dart';
import 'package:movie_collection/features/metadata/domain/entities/media.dart';
import 'package:movie_collection/features/metadata/domain/repositories/metadata_repository.dart';
import 'package:movie_collection/features/metadata/domain/usecases/metadata_usecases.dart';
import 'package:movie_collection/features/settings/domain/repositories/settings_repository.dart';
import 'package:movie_collection/features/settings/domain/usecases/settings_usecases.dart';

class _Drive extends Mock implements DriveRepository {}

class _Metadata extends Mock implements MetadataRepository {}

class _Settings extends Mock implements SettingsRepository {}

void main() {
  const movies = FolderCrumb(id: 'movies', name: 'Movies');
  const series = FolderCrumb(id: 'series', name: 'Series');
  const inception = DriveItem(id: 'a', name: 'Inception.2010.mkv', isFolder: false);
  const seriesFolder = DriveItem(id: 'series', name: 'Series', isFolder: true);
  const lost = DriveItem(id: 'b', name: 'Lost.S01E01.mp4', isFolder: false);

  late _Drive drive;
  late _Metadata metadata;
  late _Settings settings;

  LibraryCubit build() => LibraryCubit(
    listFolder: ListFolder(drive),
    loadFolderTrail: LoadFolderTrail(drive),
    saveFolderTrail: SaveFolderTrail(drive),
    lookupMedia: LookupMedia(metadata),
    getTmdbApiKey: GetTmdbApiKey(settings),
    saveTmdbApiKey: SaveTmdbApiKey(settings),
  );

  setUp(() {
    drive = _Drive();
    metadata = _Metadata();
    settings = _Settings();
    when(() => settings.tmdbApiKey()).thenAnswer((_) async => null);
    when(() => drive.loadFolderTrail()).thenAnswer((_) async => const [FolderCrumb.root, movies]);
    when(() => drive.saveFolderTrail(any())).thenAnswer((_) async {});
  });

  test('แยกโฟลเดอร์กับวิดีโอ และแสดง error จริงเมื่อโหลดไม่ได้', () async {
    when(() => drive.listFolder('movies')).thenThrow(const PermissionFailure());
    final cubit = build();

    await cubit.start();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.errorMessage, const PermissionFailure().message);
    expect(cubit.state.parent, FolderCrumb.root);
    await cubit.close();
  });

  test('metadata ของโฟลเดอร์เก่าที่กลับมาช้าไม่ทับโฟลเดอร์ใหม่', () async {
    final slowLookup = Completer<MediaMatch?>();
    when(() => drive.listFolder('movies')).thenAnswer((_) async => const [inception, seriesFolder]);
    when(() => drive.listFolder('series')).thenAnswer((_) async => const [lost]);
    when(() => metadata.lookup(inception.name)).thenAnswer((_) => slowLookup.future);
    when(() => metadata.lookup(lost.name)).thenAnswer((_) async => null);
    final cubit = build();

    unawaited(cubit.start());
    await pumpEventQueue();
    expect(cubit.state.folders, [seriesFolder]);

    await cubit.openFolder(seriesFolder);
    slowLookup.complete(const MediaMatch(kind: MediaKind.movie, title: 'Inception'));
    await pumpEventQueue();

    expect(cubit.state.trail.last, series);
    expect(cubit.state.videos, [lost]);
    expect(cubit.state.matches.keys, ['b']);
    await cubit.close();
  });

  test('ย้อนกลับขึ้นโฟลเดอร์แม่และบันทึก path', () async {
    when(() => drive.listFolder(any())).thenAnswer((_) async => const []);
    final cubit = build();
    await cubit.start();

    await cubit.goUp();

    expect(cubit.state.trail, const [FolderCrumb.root]);
    expect(cubit.state.parent, isNull);
    verify(() => drive.saveFolderTrail(const [FolderCrumb.root])).called(1);
    await cubit.close();
  });
}

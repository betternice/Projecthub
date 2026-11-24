import 'package:dio/dio.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/network/dio_failure.dart';
import '../../domain/entities/drive_item.dart';
import '../../domain/repositories/drive_repository.dart';
import '../datasources/folder_trail_local_data_source.dart';
import '../datasources/onedrive_remote_data_source.dart';

class DriveRepositoryImpl implements DriveRepository {
  DriveRepositoryImpl({required OneDriveRemoteDataSource remote, required FolderTrailLocalDataSource local})
    : _remote = remote,
      _local = local;

  final OneDriveRemoteDataSource _remote;
  final FolderTrailLocalDataSource _local;

  @override
  Future<List<DriveItem>> listFolder(String folderId) async {
    try {
      return await _remote.listChildren(folderId);
    } on DioException catch (error) {
      throw graphFailure(error, fallback: 'โหลดไฟล์จาก OneDrive ไม่สำเร็จ');
    }
  }

  @override
  Future<Uri> playbackUrl(String itemId) async {
    final String? url;
    try {
      url = await _remote.downloadUrl(itemId);
    } on DioException catch (error) {
      throw graphFailure(error, fallback: 'ขอลิงก์เล่นไฟล์จาก OneDrive ไม่สำเร็จ');
    }
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) throw const ServerFailure('OneDrive ไม่ได้ให้ลิงก์เล่นไฟล์นี้');
    return uri;
  }

  @override
  Future<List<FolderCrumb>> loadFolderTrail() async {
    final trail = await _local.read();
    if (trail.isEmpty || !trail.first.isRoot) return const [FolderCrumb.root];
    return trail;
  }

  @override
  Future<void> saveFolderTrail(List<FolderCrumb> trail) => _local.write(trail);
}

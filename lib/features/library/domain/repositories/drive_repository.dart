import '../entities/drive_item.dart';

abstract interface class DriveRepository {
  Future<List<DriveItem>> listFolder(String folderId);

  /// ลิงก์ไฟล์ต้นฉบับที่ OneDrive เซ็นไว้ให้ชั่วคราว ต้องขอใหม่ทุกครั้งที่จะเล่น
  Future<Uri> playbackUrl(String itemId);

  Future<List<FolderCrumb>> loadFolderTrail();

  Future<void> saveFolderTrail(List<FolderCrumb> trail);
}

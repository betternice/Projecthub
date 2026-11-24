import '../entities/drive_item.dart';
import '../repositories/drive_repository.dart';

class ListFolder {
  const ListFolder(this._repository);

  final DriveRepository _repository;

  Future<List<DriveItem>> call(String folderId) => _repository.listFolder(folderId);
}

class GetPlaybackUrl {
  const GetPlaybackUrl(this._repository);

  final DriveRepository _repository;

  Future<Uri> call(String itemId) => _repository.playbackUrl(itemId);
}

class LoadFolderTrail {
  const LoadFolderTrail(this._repository);

  final DriveRepository _repository;

  Future<List<FolderCrumb>> call() => _repository.loadFolderTrail();
}

class SaveFolderTrail {
  const SaveFolderTrail(this._repository);

  final DriveRepository _repository;

  Future<void> call(List<FolderCrumb> trail) => _repository.saveFolderTrail(trail);
}

import '../entities/device_login.dart';
import '../entities/session.dart';
import '../repositories/auth_repository.dart';

class RestoreSession {
  const RestoreSession(this._repository);

  final AuthRepository _repository;

  Future<Session?> call() => _repository.restoreSession();
}

class WatchSession {
  const WatchSession(this._repository);

  final AuthRepository _repository;

  Stream<Session?> call() => _repository.sessionChanges;
}

class GetSavedClientId {
  const GetSavedClientId(this._repository);

  final AuthRepository _repository;

  Future<String> call() => _repository.savedClientId();
}

class StartDeviceLogin {
  const StartDeviceLogin(this._repository);

  final AuthRepository _repository;

  Future<DeviceLogin> call(String clientId) => _repository.startDeviceLogin(clientId);
}

class PollDeviceLogin {
  const PollDeviceLogin(this._repository);

  final AuthRepository _repository;

  Future<DevicePollResult> call(DeviceLogin login) => _repository.pollDeviceLogin(login);
}

class SignOut {
  const SignOut(this._repository);

  final AuthRepository _repository;

  Future<void> call() => _repository.signOut();
}

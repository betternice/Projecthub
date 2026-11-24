import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../settings/domain/usecases/settings_usecases.dart';
import '../../domain/entities/device_login.dart';
import '../../domain/usecases/auth_usecases.dart';

final _clientIdPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

bool isValidClientId(String value) => _clientIdPattern.hasMatch(value.trim());

class SignInState extends Equatable {
  const SignInState({
    this.initialClientId = '',
    this.initialTmdbKey = '',
    this.starting = false,
    this.login,
    this.errorMessage,
  });

  /// ค่าที่บันทึกไว้ ใช้เติมฟอร์มตอนเปิดหน้าครั้งแรก
  final String initialClientId;
  final String initialTmdbKey;
  final bool starting;
  final DeviceLogin? login;
  final String? errorMessage;

  SignInState copyWith({
    String? initialClientId,
    String? initialTmdbKey,
    bool? starting,
    DeviceLogin? Function()? login,
    String? Function()? errorMessage,
  }) {
    return SignInState(
      initialClientId: initialClientId ?? this.initialClientId,
      initialTmdbKey: initialTmdbKey ?? this.initialTmdbKey,
      starting: starting ?? this.starting,
      login: login != null ? login() : this.login,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [initialClientId, initialTmdbKey, starting, login, errorMessage];
}

/// ขั้นตอน device code ของ Microsoft: ขอรหัส แล้ว poll จนผู้ใช้ยืนยันในเบราว์เซอร์
/// เมื่อสำเร็จ repository จะประกาศเซสชันใหม่ และ router จะพาไปหน้าคลังเอง
class SignInCubit extends Cubit<SignInState> {
  SignInCubit({
    required GetSavedClientId getSavedClientId,
    required StartDeviceLogin startDeviceLogin,
    required PollDeviceLogin pollDeviceLogin,
    required GetTmdbApiKey getTmdbApiKey,
    required SaveTmdbApiKey saveTmdbApiKey,
  }) : _getSavedClientId = getSavedClientId,
       _startDeviceLogin = startDeviceLogin,
       _pollDeviceLogin = pollDeviceLogin,
       _getTmdbApiKey = getTmdbApiKey,
       _saveTmdbApiKey = saveTmdbApiKey,
       super(const SignInState());

  final GetSavedClientId _getSavedClientId;
  final StartDeviceLogin _startDeviceLogin;
  final PollDeviceLogin _pollDeviceLogin;
  final GetTmdbApiKey _getTmdbApiKey;
  final SaveTmdbApiKey _saveTmdbApiKey;

  Timer? _timer;

  Future<void> load() async {
    final (clientId, tmdbKey) = await (_getSavedClientId(), _getTmdbApiKey()).wait;
    if (isClosed) return;
    emit(state.copyWith(initialClientId: clientId, initialTmdbKey: tmdbKey ?? ''));
  }

  Future<void> start({required String clientId, required String tmdbKey}) async {
    final id = clientId.trim();
    if (!isValidClientId(id) || state.starting) return;
    emit(state.copyWith(starting: true, errorMessage: () => null));
    try {
      await _saveTmdbApiKey(tmdbKey);
      final login = await _startDeviceLogin(id);
      if (isClosed) return;
      emit(state.copyWith(starting: false, login: () => login));
      _schedule(login, login.interval);
    } on Failure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(starting: false, errorMessage: () => failure.message));
    }
  }

  void cancel() {
    _timer?.cancel();
    emit(state.copyWith(login: () => null));
  }

  void _schedule(DeviceLogin login, Duration wait) {
    _timer?.cancel();
    _timer = Timer(wait, () => _poll(login, wait));
  }

  Future<void> _poll(DeviceLogin login, Duration wait) async {
    try {
      final result = await _pollDeviceLogin(login);
      if (isClosed || state.login != login) return;
      switch (result) {
        case DevicePollPending():
          _schedule(login, wait);
        case DevicePollSlowDown():
          _schedule(login, wait + const Duration(seconds: 5));
        case DevicePollExpired():
          _stop('รหัสหมดอายุแล้ว ลองเข้าสู่ระบบใหม่');
        case DevicePollDenied():
          _stop('ยกเลิกการเข้าสู่ระบบ');
        case DevicePollSuccess():
          _timer?.cancel();
      }
    } on NetworkFailure {
      // เน็ตหลุดชั่วคราวระหว่างรอผู้ใช้ยืนยัน ให้ลองต่อจนกว่ารหัสจะหมดอายุ
      if (!isClosed && state.login == login) _schedule(login, wait);
    } on Failure catch (failure) {
      if (!isClosed && state.login == login) _stop(failure.message);
    }
  }

  void _stop(String message) {
    _timer?.cancel();
    emit(state.copyWith(login: () => null, errorMessage: () => message));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}

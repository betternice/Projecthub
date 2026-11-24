import 'package:equatable/equatable.dart';

import 'session.dart';

class DeviceLogin extends Equatable {
  const DeviceLogin({
    required this.clientId,
    required this.userCode,
    required this.deviceCode,
    required this.verificationUri,
    required this.interval,
  });

  final String clientId;
  final String userCode;
  final String deviceCode;
  final Uri verificationUri;
  final Duration interval;

  @override
  List<Object?> get props => [clientId, userCode, deviceCode, verificationUri, interval];
}

sealed class DevicePollResult {
  const DevicePollResult();
}

class DevicePollPending extends DevicePollResult {
  const DevicePollPending();
}

/// Microsoft ขอให้ยิงช้าลง ต้องเพิ่มช่วงรออีก 5 วินาทีตาม RFC 8628
class DevicePollSlowDown extends DevicePollResult {
  const DevicePollSlowDown();
}

class DevicePollExpired extends DevicePollResult {
  const DevicePollExpired();
}

class DevicePollDenied extends DevicePollResult {
  const DevicePollDenied();
}

class DevicePollSuccess extends DevicePollResult {
  const DevicePollSuccess(this.session);

  final Session session;
}

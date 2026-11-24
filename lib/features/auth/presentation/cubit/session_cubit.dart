import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/session.dart';
import '../../domain/usecases/auth_usecases.dart';

enum SessionStatus { unknown, authenticated, unauthenticated }

class SessionState extends Equatable {
  const SessionState._(this.status, this.session);

  const SessionState.unknown() : this._(SessionStatus.unknown, null);

  const SessionState.authenticated(Session session) : this._(SessionStatus.authenticated, session);

  const SessionState.unauthenticated() : this._(SessionStatus.unauthenticated, null);

  final SessionStatus status;
  final Session? session;

  @override
  List<Object?> get props => [status, session];
}

/// สถานะเข้าสู่ระบบของทั้งแอป router ใช้ตัวนี้ตัดสินว่าจะพาไปหน้าไหน
class SessionCubit extends Cubit<SessionState> {
  SessionCubit({required RestoreSession restoreSession, required WatchSession watchSession, required SignOut signOut})
    : _restoreSession = restoreSession,
      _signOut = signOut,
      super(const SessionState.unknown()) {
    _subscription = watchSession().listen(_apply);
  }

  final RestoreSession _restoreSession;
  final SignOut _signOut;
  late final StreamSubscription<Session?> _subscription;

  Future<void> restore() async {
    _apply(await _restoreSession());
  }

  Future<void> signOut() => _signOut();

  void _apply(Session? session) {
    if (isClosed) return;
    emit(session == null ? const SessionState.unauthenticated() : SessionState.authenticated(session));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}

import 'package:equatable/equatable.dart';

class TokenSet extends Equatable {
  const TokenSet({required this.accessToken, required this.refreshToken, required this.expiresAt});

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt];
}

class Session extends Equatable {
  const Session({required this.tokens, required this.displayName, required this.clientId});

  final TokenSet tokens;
  final String displayName;
  final String clientId;

  /// ถือว่าหมดอายุก่อนเวลาจริง 1 นาที กัน token หมดกลางทาง request
  bool isExpiredAt(DateTime now) => !tokens.expiresAt.subtract(const Duration(minutes: 1)).isAfter(now);

  Session withTokens(TokenSet next) => Session(tokens: next, displayName: displayName, clientId: clientId);

  @override
  List<Object?> get props => [tokens, displayName, clientId];
}

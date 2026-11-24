import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../library/domain/entities/drive_item.dart';
import '../../../library/domain/usecases/library_usecases.dart';
import '../../../metadata/domain/entities/media.dart';
import '../../../metadata/domain/usecases/metadata_usecases.dart';
import '../../../settings/domain/usecases/settings_usecases.dart';

class MovieDetailState extends Equatable {
  const MovieDetailState({this.detail, this.preparingPlayback = false, this.playbackError});

  final MediaDetail? detail;
  final bool preparingPlayback;
  final String? playbackError;

  MovieDetailState copyWith({
    MediaDetail? detail,
    bool? preparingPlayback,
    String? Function()? playbackError,
  }) {
    return MovieDetailState(
      detail: detail ?? this.detail,
      preparingPlayback: preparingPlayback ?? this.preparingPlayback,
      playbackError: playbackError != null ? playbackError() : this.playbackError,
    );
  }

  @override
  List<Object?> get props => [detail, preparingPlayback, playbackError];
}

class MovieDetailCubit extends Cubit<MovieDetailState> {
  MovieDetailCubit({
    required this.item,
    required MediaMatch? match,
    required LookupMedia lookupMedia,
    required LookupMediaDetail lookupMediaDetail,
    required GetTmdbApiKey getTmdbApiKey,
    required GetPlaybackUrl getPlaybackUrl,
  }) : _match = match,
       _lookupMedia = lookupMedia,
       _lookupMediaDetail = lookupMediaDetail,
       _getTmdbApiKey = getTmdbApiKey,
       _getPlaybackUrl = getPlaybackUrl,
       super(MovieDetailState(detail: match == null ? null : MediaDetail(match: match)));

  final DriveItem item;
  final MediaMatch? _match;
  final LookupMedia _lookupMedia;
  final LookupMediaDetail _lookupMediaDetail;
  final GetTmdbApiKey _getTmdbApiKey;
  final GetPlaybackUrl _getPlaybackUrl;

  /// รายละเอียดเพิ่มเติมเป็นของเสริม ถ้าโหลดไม่ได้หน้านี้ยังเล่นไฟล์ได้ตามปกติ
  Future<void> load() async {
    try {
      final tmdbApiKey = await _getTmdbApiKey();
      final match = _match ?? await _lookupMedia(item.name, tmdbApiKey: tmdbApiKey);
      if (match == null || isClosed) return;
      final detail = await _lookupMediaDetail(match, tmdbApiKey: tmdbApiKey);
      if (!isClosed) emit(state.copyWith(detail: detail));
    } on Failure {
      return;
    }
  }

  /// คืน URL สำหรับเล่น หรือ null ถ้าขอไม่สำเร็จ (ข้อความ error อยู่ใน state)
  Future<Uri?> preparePlayback() async {
    if (state.preparingPlayback) return null;
    emit(state.copyWith(preparingPlayback: true, playbackError: () => null));
    try {
      final url = await _getPlaybackUrl(item.id);
      if (!isClosed) emit(state.copyWith(preparingPlayback: false));
      return url;
    } on Failure catch (failure) {
      if (!isClosed) emit(state.copyWith(preparingPlayback: false, playbackError: () => failure.message));
      return null;
    }
  }
}

import 'package:equatable/equatable.dart';

enum MediaKind { movie, tv }

class MediaMatch extends Equatable {
  const MediaMatch({
    required this.kind,
    required this.title,
    this.tmdbId,
    this.wikibaseId,
    this.overview,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
  });

  final int? tmdbId;
  final String? wikibaseId;
  final MediaKind kind;
  final String title;
  final String? overview;
  final String? year;
  final String? posterUrl;
  final String? backdropUrl;
  final double? rating;

  MediaMatch copyWith({String? title, String? overview, String? year, String? posterUrl, String? backdropUrl}) {
    return MediaMatch(
      tmdbId: tmdbId,
      wikibaseId: wikibaseId,
      kind: kind,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      year: year ?? this.year,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      rating: rating,
    );
  }

  @override
  List<Object?> get props => [tmdbId, wikibaseId, kind, title, overview, year, posterUrl, backdropUrl, rating];
}

class CastMember extends Equatable {
  const CastMember({required this.name, this.character, this.profileUrl});

  final String name;
  final String? character;
  final String? profileUrl;

  @override
  List<Object?> get props => [name, character, profileUrl];
}

class MediaDetail extends Equatable {
  const MediaDetail({
    required this.match,
    this.runtimeMinutes,
    this.cast = const [],
    this.genres = const [],
    this.director,
  });

  final MediaMatch match;
  final int? runtimeMinutes;
  final List<CastMember> cast;
  final List<String> genres;
  final String? director;

  @override
  List<Object?> get props => [match, runtimeMinutes, cast, genres, director];
}

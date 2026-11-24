class TokenSet {
  const TokenSet({required this.accessToken, required this.refreshToken, required this.expiresAt});

  final String accessToken;
  final String refreshToken;
  final int expiresAt;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
      };

  factory TokenSet.fromJson(Map<String, dynamic> json) {
    return TokenSet(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: json['expiresAt'] as int,
    );
  }
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.displayName,
    required this.clientId,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String displayName;
  final String clientId;

  Session copyWith({String? accessToken, String? refreshToken, int? expiresAt, String? displayName}) {
    return Session(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      displayName: displayName ?? this.displayName,
      clientId: clientId,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
        'displayName': displayName,
        'clientId': clientId,
      };

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: json['expiresAt'] as int,
      displayName: json['displayName'] as String? ?? 'OneDrive',
      clientId: json['clientId'] as String,
    );
  }
}

class DriveItem {
  const DriveItem({
    required this.id,
    required this.name,
    this.size,
    this.isFolder = false,
    this.mimeType,
    this.durationMs,
    this.thumbLarge,
    this.thumbMedium,
  });

  final String id;
  final String name;
  final int? size;
  final bool isFolder;
  final String? mimeType;
  final int? durationMs;
  final String? thumbLarge;
  final String? thumbMedium;

  factory DriveItem.fromJson(Map<String, dynamic> json) {
    final thumbs = json['thumbnails'];
    String? large;
    String? medium;
    if (thumbs is List && thumbs.isNotEmpty && thumbs.first is Map) {
      final first = thumbs.first as Map<String, dynamic>;
      large = (first['large'] as Map?)?['url'] as String?;
      medium = (first['medium'] as Map?)?['url'] as String?;
    }
    final video = json['video'];
    return DriveItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      size: json['size'] as int?,
      isFolder: json['folder'] != null,
      mimeType: (json['file'] as Map?)?['mimeType'] as String?,
      durationMs: video is Map ? video['duration'] as int? : null,
      thumbLarge: large,
      thumbMedium: medium,
    );
  }
}

bool isVideoFile(DriveItem item) {
  if (item.isFolder) return false;
  if (item.mimeType?.startsWith('video/') == true) return true;
  return RegExp(r'\.(mp4|m4v|mov|mkv|avi|webm|wmv|mpg|mpeg)$', caseSensitive: false).hasMatch(item.name);
}

class FolderCrumb {
  const FolderCrumb({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory FolderCrumb.fromJson(Map<String, dynamic> json) {
    return FolderCrumb(id: json['id'] as String, name: json['name'] as String? ?? '');
  }
}

class MediaMatch {
  const MediaMatch({
    required this.tmdbId,
    required this.wikibaseId,
    required this.kind,
    required this.title,
    required this.overview,
    required this.year,
    required this.posterUrl,
    required this.backdropUrl,
    required this.rating,
  });

  final int? tmdbId;
  final String? wikibaseId;
  final String kind;
  final String title;
  final String? overview;
  final String? year;
  final String? posterUrl;
  final String? backdropUrl;
  final double? rating;
}

class CastMember {
  const CastMember({required this.name, this.character, this.profileUrl});

  final String name;
  final String? character;
  final String? profileUrl;
}

class MediaDetail {
  const MediaDetail({
    required this.match,
    required this.runtime,
    required this.cast,
    required this.genres,
    required this.director,
  });

  final MediaMatch match;
  final int? runtime;
  final List<CastMember> cast;
  final List<String> genres;
  final String? director;

  String get title => match.title;
  String? get overview => match.overview;
  String? get year => match.year;
  String? get posterUrl => match.posterUrl;
  String? get backdropUrl => match.backdropUrl;
  double? get rating => match.rating;
}

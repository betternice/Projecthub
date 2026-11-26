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

class SelectedLibraryFolder {
  const SelectedLibraryFolder({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory SelectedLibraryFolder.fromJson(Map<String, dynamic> json) {
    return SelectedLibraryFolder(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

/// โปรไฟล์ในเครื่อง/ซิงก์ OneDrive — คนละชุดเล่นต่อ + Favourite ภายใต้บัญชีเดียว
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.color = 0xFFE50914,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final int color;
  final int updatedAt;

  UserProfile copyWith({String? name, int? color, int? updatedAt}) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'updatedAt': updatedAt,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Profile',
      color: json['color'] as int? ?? 0xFFE50914,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}

/// การเชื่อม OneDrive = คลังไฟล์หนังเท่านั้น ไม่ใช่โปรไฟล์ผู้ใช้ในแอป
class Session {
  const Session({
    required this.id,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.displayName,
    required this.clientId,
    this.label = 'My OneDrive',
    this.accountHint = '',
    this.libraryFolders = const [],
  });

  /// Stable library key (usually Microsoft userPrincipalName / email).
  final String id;
  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String displayName;
  final String clientId;
  /// User-facing library name (Infuse-style).
  final String label;
  final String accountHint;
  /// Empty = แสดงทุกโฟลเดอร์ใน OneDrive; ไม่ว่าง = เฉพาะโฟลเดอร์ที่ติ๊ก
  final List<SelectedLibraryFolder> libraryFolders;

  String get title => label.trim().isNotEmpty ? label : displayName;

  bool get hasLibraryFilter => libraryFolders.isNotEmpty;

  Set<String> get libraryFolderIds => libraryFolders.map((f) => f.id).toSet();

  Session copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresAt,
    String? displayName,
    String? label,
    String? accountHint,
    List<SelectedLibraryFolder>? libraryFolders,
  }) {
    return Session(
      id: id,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      displayName: displayName ?? this.displayName,
      clientId: clientId,
      label: label ?? this.label,
      accountHint: accountHint ?? this.accountHint,
      libraryFolders: libraryFolders ?? this.libraryFolders,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
        'displayName': displayName,
        'clientId': clientId,
        'label': label,
        'accountHint': accountHint,
        'libraryFolders': libraryFolders.map((f) => f.toJson()).toList(),
      };

  factory Session.fromJson(Map<String, dynamic> json) {
    final hint = json['accountHint'] as String? ?? json['displayName'] as String? ?? '';
    final id = (json['id'] as String?)?.trim();
    final foldersRaw = json['libraryFolders'];
    final folders = <SelectedLibraryFolder>[];
    if (foldersRaw is List) {
      for (final entry in foldersRaw) {
        if (entry is Map<String, dynamic>) {
          final folder = SelectedLibraryFolder.fromJson(entry);
          if (folder.id.isNotEmpty) folders.add(folder);
        }
      }
    }
    return Session(
      id: (id != null && id.isNotEmpty) ? id : (hint.isNotEmpty ? hint : 'account'),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: json['expiresAt'] as int,
      displayName: json['displayName'] as String? ?? 'OneDrive',
      clientId: json['clientId'] as String,
      label: json['label'] as String? ?? json['displayName'] as String? ?? 'My OneDrive',
      accountHint: hint,
      libraryFolders: folders,
    );
  }
}

class MsProfile {
  const MsProfile({required this.displayName, required this.userPrincipalName});

  final String displayName;
  final String userPrincipalName;
}

enum MediaSource { overview, local, oneDrive }

String mediaSourceKey(MediaSource source) => switch (source) {
      MediaSource.overview => 'overview',
      MediaSource.local => 'local',
      MediaSource.oneDrive => 'oneDrive',
    };

MediaSource mediaSourceFromKey(String? key) => switch (key) {
      'oneDrive' => MediaSource.oneDrive,
      'local' => MediaSource.local,
      _ => MediaSource.overview,
    };

class LibraryRef {
  const LibraryRef({
    required this.key,
    required this.itemId,
    required this.name,
    required this.title,
    this.accountId,
    this.accountLabel,
    this.localPath,
    this.size,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.overview,
  });

  final String key;
  final String itemId;
  final String name;
  final String title;
  final String? accountId;
  final String? accountLabel;
  final String? localPath;
  final int? size;
  final String? posterUrl;
  final String? backdropUrl;
  final String? year;
  final String? overview;

  bool get isLocal => localPath != null && localPath!.isNotEmpty;

  DriveItem toDriveItem() => DriveItem(
        id: itemId,
        name: name,
        size: size,
        localPath: localPath,
        thumbLarge: posterUrl,
        thumbMedium: posterUrl,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'itemId': itemId,
        'name': name,
        'title': title,
        'accountId': accountId,
        'accountLabel': accountLabel,
        'localPath': localPath,
        'size': size,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'year': year,
        'overview': overview,
      };

  factory LibraryRef.fromJson(Map<String, dynamic> json) {
    return LibraryRef(
      key: json['key'] as String,
      itemId: json['itemId'] as String,
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      accountId: json['accountId'] as String?,
      accountLabel: json['accountLabel'] as String?,
      localPath: json['localPath'] as String?,
      size: json['size'] as int?,
      posterUrl: json['posterUrl'] as String?,
      backdropUrl: json['backdropUrl'] as String?,
      year: json['year'] as String?,
      overview: json['overview'] as String?,
    );
  }

  LibraryRef copyWith({
    String? title,
    String? posterUrl,
    String? backdropUrl,
    String? year,
    String? overview,
  }) {
    return LibraryRef(
      key: key,
      itemId: itemId,
      name: name,
      title: title ?? this.title,
      accountId: accountId,
      accountLabel: accountLabel,
      localPath: localPath,
      size: size,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      year: year ?? this.year,
      overview: overview ?? this.overview,
    );
  }
}

class WatchProgress {
  const WatchProgress({
    required this.ref,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final LibraryRef ref;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  double get ratio => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'ref': ref.toJson(),
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  factory WatchProgress.fromJson(Map<String, dynamic> json) {
    return WatchProgress(
      ref: LibraryRef.fromJson(json['ref'] as Map<String, dynamic>),
      positionMs: json['positionMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}

String libraryKey({String? accountId, required String itemId, String? localPath}) {
  if (localPath != null && localPath.isNotEmpty) return 'local:$localPath';
  return 'od:${accountId ?? 'unknown'}:$itemId';
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
    this.localPath,
  });

  final String id;
  final String name;
  final int? size;
  final bool isFolder;
  final String? mimeType;
  final int? durationMs;
  final String? thumbLarge;
  final String? thumbMedium;
  final String? localPath;

  bool get isLocal => localPath != null && localPath!.isNotEmpty;

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
    this.genres = const [],
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
  final List<String> genres;

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'wikibaseId': wikibaseId,
        'kind': kind,
        'title': title,
        'overview': overview,
        'year': year,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'rating': rating,
        'genres': genres,
      };

  factory MediaMatch.fromJson(Map<String, dynamic> json) {
    return MediaMatch(
      tmdbId: json['tmdbId'] as int?,
      wikibaseId: json['wikibaseId'] as String?,
      kind: json['kind'] as String? ?? 'movie',
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      year: json['year'] as String?,
      posterUrl: json['posterUrl'] as String?,
      backdropUrl: json['backdropUrl'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      genres: (json['genres'] as List<dynamic>?)?.whereType<String>().toList() ?? const [],
    );
  }
}

class CastMember {
  const CastMember({required this.name, this.character, this.profileUrl});

  final String name;
  final String? character;
  final String? profileUrl;

  Map<String, dynamic> toJson() => {
        'name': name,
        'character': character,
        'profileUrl': profileUrl,
      };

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      name: json['name'] as String? ?? '',
      character: json['character'] as String?,
      profileUrl: json['profileUrl'] as String?,
    );
  }
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

  Map<String, dynamic> toJson() => {
        'match': match.toJson(),
        'runtime': runtime,
        'cast': cast.map((c) => c.toJson()).toList(),
        'genres': genres,
        'director': director,
      };

  factory MediaDetail.fromJson(Map<String, dynamic> json) {
    final matchRaw = json['match'];
    return MediaDetail(
      match: matchRaw is Map<String, dynamic>
          ? MediaMatch.fromJson(matchRaw)
          : const MediaMatch(
              tmdbId: null,
              wikibaseId: null,
              kind: 'movie',
              title: '',
              overview: null,
              year: null,
              posterUrl: null,
              backdropUrl: null,
              rating: null,
            ),
      runtime: json['runtime'] as int?,
      cast: (json['cast'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(CastMember.fromJson)
              .toList() ??
          const [],
      genres: (json['genres'] as List<dynamic>?)?.whereType<String>().toList() ?? const [],
      director: json['director'] as String?,
    );
  }
}

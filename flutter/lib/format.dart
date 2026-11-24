class ParsedTitle {
  const ParsedTitle({required this.title, required this.year});

  final String title;
  final String? year;
}

ParsedTitle presentTitle(String filename) {
  final base = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(base)?.group(0);
  final title = base
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\((?!(?:19|20)\d{2}\))[^)]*\)'), ' ')
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ')
      .replaceAll(
        RegExp(
          r'\b(1080p|720p|2160p|4320p|4k|8k|uhd|hdr|x264|x265|h264|h265|hevc|10bit|bluray|bdrip|brrip|webrip|webdl|web-dl|hdrip|dvdrip|remux|aac|dts|truehd|atmos)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return ParsedTitle(title: title.isEmpty ? base : title, year: year);
}

String? formatBytes(int? bytes) {
  if (bytes == null || bytes == 0) return null;
  final gigabytes = bytes / (1024 * 1024 * 1024);
  if (gigabytes >= 1) {
    return '${gigabytes >= 10 ? gigabytes.toStringAsFixed(0) : gigabytes.toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).round().clamp(1, 1 << 30)} MB';
}

String? formatClock(int? milliseconds) {
  if (milliseconds == null || milliseconds < 1000) return null;
  final total = (milliseconds / 1000).round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (hours > 0) return '$hours ชม. $minutes นาที';
  return '$minutes นาที';
}

String? formatRuntime(int? minutes) {
  if (minutes == null || minutes == 0) return null;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours > 0) return '$hours ชม. $rest นาที';
  return '$rest นาที';
}

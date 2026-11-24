import 'package:equatable/equatable.dart';

class ParsedTitle extends Equatable {
  const ParsedTitle({required this.title, this.year});

  final String title;
  final String? year;

  @override
  List<Object?> get props => [title, year];
}

final _extension = RegExp(r'\.[^.]+$');
final _year = RegExp(r'\b(19|20)\d{2}\b');
final _brackets = RegExp(r'\[[^\]]*\]');
final _nonYearParens = RegExp(r'\((?!(?:19|20)\d{2}\))[^)]*\)');
final _separators = RegExp(r'[._]+');
final _emptyParens = RegExp(r'\(\s*\)');
final _releaseTags = RegExp(
  r'\b(1080p|720p|2160p|4320p|4k|8k|uhd|hdr|x264|x265|h264|h265|hevc|10bit|bluray|bdrip|brrip|webrip|webdl|web-dl|hdrip|dvdrip|remux|aac|dts|truehd|atmos)\b',
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');

/// แยกชื่อเรื่องและปีออกจากชื่อไฟล์ เช่น `Inception.2010.1080p.BluRay.mkv`
ParsedTitle parseMediaTitle(String filename) {
  final base = filename.replaceFirst(_extension, '');
  final year = _year.firstMatch(base)?.group(0);
  final title = base
      .replaceAll(_brackets, ' ')
      .replaceAll(_nonYearParens, ' ')
      .replaceAll(_separators, ' ')
      .replaceAll(_year, ' ')
      .replaceAll(_emptyParens, ' ')
      .replaceAll(_releaseTags, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
  return ParsedTitle(title: title.isEmpty ? base : title, year: year);
}

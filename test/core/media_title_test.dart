import 'package:flutter_test/flutter_test.dart';
import 'package:movie_collection/core/utils/formatters.dart';
import 'package:movie_collection/core/utils/media_title.dart';

void main() {
  group('parseMediaTitle', () {
    test('ตัด tag ของไฟล์ release และแยกปีออก', () {
      expect(
        parseMediaTitle('Inception.2010.1080p.BluRay.x264.mkv'),
        const ParsedTitle(title: 'Inception', year: '2010'),
      );
    });

    test('ปีในวงเล็บไม่เหลือวงเล็บว่างค้างในชื่อ', () {
      expect(parseMediaTitle('Inception (2010).mp4'), const ParsedTitle(title: 'Inception', year: '2010'));
    });

    test('ตัดวงเล็บเหลี่ยมและวงเล็บที่ไม่ใช่ปี', () {
      expect(
        parseMediaTitle('[YTS] The Matrix (Remastered) 1999 WEB-DL.mkv'),
        const ParsedTitle(title: 'The Matrix', year: '1999'),
      );
    });

    test('ชื่อภาษาไทยไม่มีปี', () {
      expect(parseMediaTitle('ฉลาดเกมส์โกง.mp4'), const ParsedTitle(title: 'ฉลาดเกมส์โกง'));
    });

    test('ถ้าตัดแล้วว่างให้ใช้ชื่อไฟล์เดิม', () {
      expect(parseMediaTitle('1080p.mkv').title, '1080p');
    });
  });

  group('formatters', () {
    test('formatRuntime', () {
      expect(formatRuntime(148), '2 ชม. 28 นาที');
      expect(formatRuntime(45), '45 นาที');
      expect(formatRuntime(null), isNull);
    });

    test('formatBytes', () {
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
      expect(formatBytes(700 * 1024 * 1024), '700 MB');
      expect(formatBytes(0), isNull);
    });
  });
}

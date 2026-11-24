import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

Future<String> _graphError(http.Response response) async {
  if (response.statusCode == 401) return 'เซสชันหมดอายุ เข้าสู่ระบบอีกครั้ง';
  if (response.statusCode == 403) return 'บัญชีนี้ยังไม่ได้รับสิทธิ์อ่านไฟล์ใน OneDrive';
  return 'โหลดไฟล์จาก OneDrive ไม่สำเร็จ';
}

Future<List<DriveItem>> listChildren(String token, String folderId) async {
  final items = <DriveItem>[];
  var url = folderId == 'root'
      ? 'https://graph.microsoft.com/v1.0/me/drive/root/children?\$top=200&\$expand=thumbnails'
      : 'https://graph.microsoft.com/v1.0/me/drive/items/$folderId/children?\$top=200&\$expand=thumbnails';

  while (url.isNotEmpty) {
    final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) throw Exception(await _graphError(response));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final value = body['value'] as List<dynamic>? ?? [];
    for (final entry in value) {
      if (entry is Map<String, dynamic>) items.add(DriveItem.fromJson(entry));
    }
    url = body['@odata.nextLink'] as String? ?? '';
  }
  return items;
}

Future<String> getPlaybackUrl(String token, String itemId) async {
  final response = await http.get(
    Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$itemId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200) throw Exception(await _graphError(response));
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final url = body['@microsoft.graph.downloadUrl'] as String?;
  if (url == null || url.isEmpty) throw Exception('OneDrive ไม่ได้ให้ลิงก์เล่นไฟล์นี้');
  return url;
}

Future<String> fetchProfileName(String token) async {
  final response = await http.get(
    Uri.parse('https://graph.microsoft.com/v1.0/me?\$select=displayName,userPrincipalName'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200) return 'OneDrive';
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return body['displayName'] as String? ?? body['userPrincipalName'] as String? ?? 'OneDrive';
}

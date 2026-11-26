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

Future<MsProfile> fetchProfile(String token) async {
  final response = await http.get(
    Uri.parse('https://graph.microsoft.com/v1.0/me?\$select=displayName,userPrincipalName,mail'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200) {
    return const MsProfile(displayName: 'OneDrive', userPrincipalName: 'onedrive');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final upn = body['userPrincipalName'] as String? ?? body['mail'] as String? ?? 'onedrive';
  final name = body['displayName'] as String? ?? upn;
  return MsProfile(displayName: name, userPrincipalName: upn);
}

Future<String> fetchProfileName(String token) async {
  final profile = await fetchProfile(token);
  return profile.displayName;
}

const kNiceSyncPath = '/NICE/profile-sync.json';

Future<String?> downloadDriveText(String token, String path) async {
  final encoded = Uri.encodeComponent(path.startsWith('/') ? path.substring(1) : path);
  final meta = await http.get(
    Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root:/$encoded'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (meta.statusCode == 404) return null;
  if (meta.statusCode != 200) throw Exception(await _graphError(meta));
  final body = jsonDecode(meta.body) as Map<String, dynamic>;
  final url = body['@microsoft.graph.downloadUrl'] as String?;
  if (url == null || url.isEmpty) return null;
  final file = await http.get(Uri.parse(url));
  if (file.statusCode != 200) return null;
  return file.body;
}

Future<void> uploadDriveText(String token, String path, String content) async {
  final clean = path.startsWith('/') ? path.substring(1) : path;
  // สร้างโฟลเดอร์ NICE ถ้ายังไม่มี
  final folderName = clean.contains('/') ? clean.split('/').first : null;
  if (folderName != null && folderName.isNotEmpty) {
    await http.post(
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root/children'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': folderName,
        'folder': <String, dynamic>{},
        '@microsoft.graph.conflictBehavior': 'fail',
      }),
    );
  }
  final encoded = Uri.encodeComponent(clean);
  final response = await http.put(
    Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root:/$encoded:/content'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: content,
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(await _graphError(response));
  }
}

import 'package:dio/dio.dart';

import '../../domain/entities/drive_item.dart';
import '../models/drive_item_model.dart';

/// [Dio] ที่ส่งเข้ามาต้องมี base URL ของ Graph และ GraphAuthInterceptor แล้ว
class OneDriveRemoteDataSource {
  OneDriveRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<DriveItem>> listChildren(String folderId) async {
    final items = <DriveItem>[];
    String? url = folderId == FolderCrumb.root.id
        ? '/me/drive/root/children'
        : '/me/drive/items/$folderId/children';
    Map<String, dynamic>? query = {r'$top': 200, r'$expand': 'thumbnails'};

    while (url != null) {
      final response = await _dio.get<Map<String, dynamic>>(url, queryParameters: query);
      final body = response.data ?? const {};
      final values = body['value'];
      if (values is List) {
        items.addAll(values.whereType<Map<String, dynamic>>().map(DriveItemModel.fromJson).whereType<DriveItem>());
      }
      url = body['@odata.nextLink'] as String?;
      // nextLink มี query ครบแล้ว ถ้าส่งซ้ำ Graph จะตอบ 400
      query = null;
    }
    return items;
  }

  Future<String?> downloadUrl(String itemId) async {
    final response = await _dio.get<Map<String, dynamic>>('/me/drive/items/$itemId');
    return response.data?['@microsoft.graph.downloadUrl'] as String?;
  }
}

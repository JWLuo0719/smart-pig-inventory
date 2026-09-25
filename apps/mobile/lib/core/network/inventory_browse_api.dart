import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'api_client.dart';

class InventoryBrowseApi {
  InventoryBrowseApi(String baseUrl, {Dio? dio})
      : _dio = dio ?? createApiDio(BaseOptions(baseUrl: baseUrl));
  final Dio _dio;
  Options _auth(String token, {String? key, ResponseType? type}) =>
      Options(responseType: type, headers: {
        'Authorization': 'Bearer $token',
        if (key != null) 'X-Idempotency-Key': key,
      });
  Future<List<LibraryMedia>> media(String token, DateTime date,
      {String? penId, int offset = 0}) async {
    final response = await _dio.get<dynamic>('/api/v1/media-assets',
        options: _auth(token),
        queryParameters: {
          'businessDate': date.toIso8601String().substring(0, 10),
          if (penId != null) 'penId': penId,
          'offset': offset,
          'limit': 50,
        });
    return (response.data as List)
        .map((e) => LibraryMedia.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LibraryMedia>> sessionMedia(
      String token, String sessionId) async {
    final response = await _dio.get<dynamic>(
        '/api/v1/inventory-sessions/$sessionId/media',
        options: _auth(token));
    return (response.data as List)
        .map((e) => LibraryMedia.fromJson(
            {...e as Map<String, dynamic>, 'sessionId': sessionId}))
        .toList();
  }

  Future<Uint8List> content(String token, String assetId) async {
    final response = await _dio.get<List<int>>(
        '/api/v1/media-assets/$assetId/content',
        options: _auth(token, type: ResponseType.bytes));
    return Uint8List.fromList(response.data!);
  }

  Future<void> delete(String token, String assetId, String key) async {
    await _dio.delete<dynamic>('/api/v1/media-assets/$assetId',
        options: _auth(token, key: key));
  }

  Future<void> download(
      String token, String assetId, String destination) async {
    await _dio.download('/api/v1/media-assets/$assetId/content', destination,
        options: _auth(token));
  }

  Future<List<Map<String, dynamic>>> daily(String token, DateTime date) async {
    final response = await _dio.get<dynamic>('/api/v1/inventory-reports/daily',
        options: _auth(token),
        queryParameters: {
          'businessDate': date.toIso8601String().substring(0, 10)
        });
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> aggregate(
      String token, String penId, DateTime from, DateTime to) async {
    final response = await _dio.get<dynamic>(
        '/api/v1/inventory-reports/aggregate',
        options: _auth(token),
        queryParameters: {
          'penId': penId,
          'from': from.toIso8601String().substring(0, 10),
          'to': to.toIso8601String().substring(0, 10),
        });
    return response.data as Map<String, dynamic>;
  }

  Future<RemoteTrend> trend(String token, DateTime to, {int days = 14}) async {
    final response = await _dio.get<dynamic>('/api/v1/inventory-reports/trend',
        options: _auth(token),
        queryParameters: {
          'to': to.toIso8601String().substring(0, 10),
          'days': days,
        });
    return RemoteTrend.fromJson(response.data as Map<String, dynamic>);
  }
}

/// 近 N 天存栏趋势：total 为场级合计序列，pens 为分栏序列；
/// 缺采集的日期 confirmed/candidate 为 null（不补零，避免误导趋势）。
class RemoteTrend {
  RemoteTrend.fromJson(Map<String, dynamic> body)
      : from = body['from'] as String,
        to = body['to'] as String,
        total = (body['total'] as List)
            .map((e) => RemoteTrendPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        pens = (body['pens'] as List)
            .map((e) => RemotePenTrend.fromJson(e as Map<String, dynamic>))
            .toList();
  final String from, to;
  final List<RemoteTrendPoint> total;
  final List<RemotePenTrend> pens;

  /// penId 为空返回全场合计；指定栏舍返回该栏序列；该栏窗口内无数据返回 null。
  (String, List<RemoteTrendPoint>)? seriesFor(String? penId) {
    if (penId == null) {
      return ('全场合计', total);
    }
    for (final pen in pens) {
      if (pen.penId == penId) {
        return (pen.penLabel, pen.points);
      }
    }
    return null;
  }
}

class RemoteTrendPoint {
  RemoteTrendPoint.fromJson(Map<String, dynamic> value)
      : date = value['date'] as String,
        confirmed = value['confirmed'] as int?,
        candidate = value['candidate'] as int?;
  final String date;
  final int? confirmed, candidate;
}

class RemotePenTrend {
  RemotePenTrend.fromJson(Map<String, dynamic> value)
      : penId = value['penId'] as String,
        penLabel = value['penLabel'] as String,
        points = (value['points'] as List)
            .map((e) => RemoteTrendPoint.fromJson(e as Map<String, dynamic>))
            .toList();
  final String penId;
  final String penLabel;
  final List<RemoteTrendPoint> points;
}

class LibraryMedia {
  LibraryMedia.fromJson(Map<String, dynamic> value)
      : assetId = value['assetId'] as String,
        sessionId = value['sessionId'] as String,
        penId = value['penId'] as String?,
        buildingCode = value['buildingCode'] as String? ?? '',
        penCode = value['penCode'] as String? ?? '',
        date = value['businessDate'] as String? ?? '',
        position = value['viewPosition'] as String,
        contentType = value['contentType'] as String,
        locked = value['locked'] as bool,
        deleted = value['deleted'] as bool;
  final String assetId,
      sessionId,
      buildingCode,
      penCode,
      date,
      position,
      contentType;
  final String? penId;
  final bool locked, deleted;
}

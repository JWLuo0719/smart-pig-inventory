import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/inventory_browse_api.dart';

void main() {
  test(
      'gallery scopes date and pen, preserves lock state and deletion idempotency',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
          requestOptions: request,
          statusCode: request.method == 'DELETE' ? 204 : 200,
          data: request.method == 'DELETE'
              ? null
              : [
                  {
                    'assetId': 'asset',
                    'sessionId': 'session',
                    'penId': 'pen',
                    'businessDate': '2026-09-12',
                    'viewPosition': 'single',
                    'contentType': 'image/jpeg',
                    'locked': true,
                    'deleted': false
                  },
                ]));
    }));
    final api = InventoryBrowseApi('https://example.invalid', dio: dio);
    final media = await api.media('token', DateTime(2026, 9, 12),
        penId: 'pen', offset: 50);
    expect(media.single.locked, isTrue);
    expect(media.single.deleted, isFalse);
    expect(requests.first.queryParameters, {
      'businessDate': '2026-09-12',
      'penId': 'pen',
      'offset': 50,
      'limit': 50
    });
    await api.delete('token', 'asset', 'same-key');
    await api.delete('rotated-token', 'asset', 'same-key');
    expect(requests.last.headers['Authorization'], 'Bearer rotated-token');
    expect(requests.skip(1).map((r) => r.headers['X-Idempotency-Key']),
        everyElement('same-key'));
  });

  test(
      'failed lists and absent aggregate counts never become successful zero data',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/aggregate')) {
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'rawMean': null,
              'roundedCount': null,
              'includedDates': <String>[]
            }));
      } else {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      }
    }));
    final api = InventoryBrowseApi('https://example.invalid', dio: dio);
    await expectLater(api.media('token', DateTime(2026, 9, 12)),
        throwsA(isA<DioException>()));
    await expectLater(api.daily('token', DateTime(2026, 9, 12)),
        throwsA(isA<DioException>()));
    final aggregate = await api.aggregate(
        'token', 'pen', DateTime(2026, 9, 11), DateTime(2026, 9, 12));
    expect(aggregate['rawMean'], isNull);
    expect(aggregate['roundedCount'], isNull);
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/inventory_browse_api.dart';
import 'package:smart_pig_inventory/core/auth/authorized_retry.dart';
import 'support/competition_auth.dart';

void main() {
  test('thumbnail 401 cannot replay after the active identity changes',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.reject(DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 401),
          type: DioExceptionType.badResponse));
    }));
    final api = InventoryBrowseApi('https://example.invalid', dio: dio);
    await expectLater(
        retryOnceAfterUnauthorized(
            initialAuth: competitionAuth(),
            reconnect: () async => competitionAuth(org: 'org-b'),
            request: (token) => api.thumbnail(token, 'asset')),
        throwsA(isA<DioException>()));
    expect(requests, hasLength(1));
    expect(requests.single.path, '/api/v1/media-assets/asset/thumbnail');
    expect(requests.single.headers['Authorization'], 'Bearer synthetic-org-a');
  });
  test(
      'thumbnail uses its authenticated endpoint and never substitutes original',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      if (request.path.endsWith('/thumbnail')) {
        handler.reject(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 422),
            type: DioExceptionType.badResponse));
      } else {
        handler.resolve(Response(
            requestOptions: request, statusCode: 200, data: <int>[1, 2, 3]));
      }
    }));
    final api = InventoryBrowseApi('https://example.invalid', dio: dio);
    await expectLater(
        api.thumbnail('synthetic', 'asset'), throwsA(isA<DioException>()));
    expect(requests.single.path, '/api/v1/media-assets/asset/thumbnail');
    expect(requests.single.headers['Authorization'], 'Bearer synthetic');
    expect(requests.single.responseType, ResponseType.bytes);
    expect(await api.content('synthetic', 'asset'), [1, 2, 3]);
    expect(requests.last.path, '/api/v1/media-assets/asset/content');
  });
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

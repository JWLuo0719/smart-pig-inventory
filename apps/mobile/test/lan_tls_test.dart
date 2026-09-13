import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/api_client.dart';

void main() {
  test('LAN CA cannot be applied to another host or plaintext', () {
    for (final url in ['https://example.com', 'http://pig-inventory.local']) {
      expect(() => createApiDio(BaseOptions(baseUrl: url), acceptanceCa: 'abc'),
          throwsStateError);
    }
    expect(
        () => createApiDio(BaseOptions(baseUrl: 'https://pig-inventory.local'),
            acceptanceCa: ''),
        throwsStateError);
  });

  final directory = Platform.environment['LAN_TLS_DIRECTORY'];
  test('real LAN TLS verifies chain, hostname and origin without bypass',
      () async {
    final ca = File('$directory/ca.pem').readAsBytesSync();
    const endpoint = 'https://pig-inventory.local:8443';
    final dio = createApiDio(BaseOptions(baseUrl: endpoint),
        acceptanceCa: base64Encode(ca));
    try {
      final response = await dio.get<dynamic>('/actuator/health');
      expect(response.data['status'], 'UP');
      await expectLater(dio.get<dynamic>('https://example.com/api/v1/me'),
          throwsA(isA<DioException>()));
    } finally {
      dio.close(force: true);
    }

    final untrusted =
        Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    try {
      await expectLater(
          untrusted.get<dynamic>('$endpoint/actuator/health'),
          throwsA(isA<DioException>().having((e) => e.error.toString(),
              'TLS error', contains('CERTIFICATE_VERIFY_FAILED'))));
    } finally {
      untrusted.close(force: true);
    }

    final wrongHost =
        Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)))
          ..httpClientAdapter = IOHttpClientAdapter(
              createHttpClient: () => HttpClient(
                  context: SecurityContext(withTrustedRoots: false)
                    ..setTrustedCertificatesBytes(ca)));
    try {
      await expectLater(
          wrongHost.get<dynamic>('https://127.0.0.1:8443/actuator/health'),
          throwsA(isA<DioException>().having((e) => e.error.toString(),
              'TLS hostname error', contains('CERTIFICATE_VERIFY_FAILED'))));
    } finally {
      wrongHost.close(force: true);
    }
  },
      skip: directory == null
          ? 'Set LAN_TLS_DIRECTORY for the real TLS acceptance check.'
          : false);
}

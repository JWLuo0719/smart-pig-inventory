import 'package:dio/dio.dart';

Dio createApiDio(BaseOptions options, {required String acceptanceCa}) {
  if (acceptanceCa.isNotEmpty) {
    throw UnsupportedError(
        'LAN acceptance certificates require a native client.');
  }
  return Dio(options);
}

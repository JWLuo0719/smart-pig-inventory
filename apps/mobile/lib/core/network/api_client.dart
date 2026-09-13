import 'package:dio/dio.dart';

import 'api_client_stub.dart' if (dart.library.io) 'api_client_io.dart'
    as platform;

/// Private LAN trust is explicit in acceptance builds and never disables TLS.
Dio createApiDio(
  BaseOptions options, {
  String acceptanceCa =
      const String.fromEnvironment('LAN_ACCEPTANCE_CA_BASE64'),
}) =>
    platform.createApiDio(options, acceptanceCa: acceptanceCa);

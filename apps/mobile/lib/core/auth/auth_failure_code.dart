import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// A bounded support code. Never include messages, URLs, request/response
/// bodies, platform details or credentials from the original exception.
String authFailureCode(Object error) {
  if (error is PlatformException) return 'AUTH-LOCAL-PLATFORM';
  if (error is FormatException) return 'AUTH-LOCAL-FORMAT';
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null && status >= 400 && status <= 599) {
      return 'AUTH-HTTP-$status';
    }
    final transport = switch (error.error.runtimeType.toString()) {
      'SocketException' => 'SOCKET',
      'HandshakeException' || 'TlsException' => 'TLS',
      'HttpException' => 'HTTP',
      'FormatException' => 'FORMAT',
      _ => 'OTHER',
    };
    return 'AUTH-NET-${error.type.name.toUpperCase()}-$transport';
  }
  return 'AUTH-LOCAL-OTHER';
}

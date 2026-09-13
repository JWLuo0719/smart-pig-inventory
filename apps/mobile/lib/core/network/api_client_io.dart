import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

Dio createApiDio(BaseOptions options, {required String acceptanceCa}) {
  final uri = Uri.parse(options.baseUrl);
  if (acceptanceCa.isEmpty) {
    if (uri.host == 'pig-inventory.local') {
      throw StateError('LAN acceptance requires its explicit certificate.');
    }
    return Dio(options);
  }
  if (uri.scheme != 'https' ||
      uri.host != 'pig-inventory.local' ||
      uri.userInfo.isNotEmpty) {
    throw StateError(
        'LAN certificate is restricted to the acceptance HTTPS host.');
  }
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64Decode(acceptanceCa));
  final httpClient = HttpClient(context: context)..findProxy = (_) => 'DIRECT';
  // Windows does not support the reusePort socket option used by the mDNS
  // library. Its resolver can already resolve the local acceptance record;
  // Android performs the explicit multicast lookup below.
  if (!Platform.isWindows) {
    final resolver = _LanMdnsResolver(uri.host, context);
    httpClient.connectionFactory = (requestUri, proxyHost, proxyPort) {
      if (proxyHost != null ||
          proxyPort != null ||
          requestUri.host != uri.host) {
        return Socket.startConnect(requestUri.host, requestUri.port);
      }
      return resolver.connect(requestUri.port);
    };
  }
  final dio = Dio(options.copyWith(followRedirects: false));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => httpClient,
  );
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    if (request.uri.origin != uri.origin) {
      handler.reject(DioException(
          requestOptions: request,
          error: 'Cross-origin LAN request rejected.'));
    } else {
      handler.next(request);
    }
  }));
  return dio;
}

class _LanMdnsResolver {
  _LanMdnsResolver(this._host, this._context);

  final String _host;
  final SecurityContext _context;
  InternetAddress? _cachedAddress;

  Future<ConnectionTask<Socket>> connect(int port) async {
    final InternetAddress address = _cachedAddress ??= await _lookup();
    final socketTask = await Socket.startConnect(address, port);
    return ConnectionTask.fromSocket<Socket>(
      socketTask.socket.then<Socket>(
        (socket) => SecureSocket.secure(socket, host: _host, context: _context),
      ),
      socketTask.cancel,
    );
  }

  Future<InternetAddress> _lookup() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final completer = Completer<InternetAddress>();
    try {
      socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final address = _firstPrivateIpv4Answer(datagram.data);
        if (address != null) completer.complete(address);
      }, onError: completer.completeError);
      socket.send(_queryPacket(), InternetAddress('224.0.0.251'), 5353);
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw const SocketException(
          'LAN service discovery timed out.',
        ),
      );
    } finally {
      socket.close();
    }
  }

  List<int> _queryPacket() {
    final labels = _host.split('.');
    final name = <int>[];
    for (final label in labels) {
      name.add(label.length);
      name.addAll(label.codeUnits);
    }
    name.add(0);
    return <int>[
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      ...name,
      0,
      1,
      0,
      1,
    ];
  }

  InternetAddress? _firstPrivateIpv4Answer(List<int> packet) {
    if (packet.length < 12) return null;
    final questions = _readUint16(packet, 4);
    final answers = _readUint16(packet, 6);
    var offset = 12;
    for (var index = 0; index < questions; index++) {
      offset = _skipDnsName(packet, offset);
      if (offset + 4 > packet.length) return null;
      offset += 4;
    }
    for (var index = 0; index < answers; index++) {
      offset = _skipDnsName(packet, offset);
      if (offset + 10 > packet.length) return null;
      final type = _readUint16(packet, offset);
      final length = _readUint16(packet, offset + 8);
      offset += 10;
      if (offset + length > packet.length) return null;
      if (type == 1 && length == 4) {
        final address = InternetAddress.fromRawAddress(
            Uint8List.fromList(packet.sublist(offset, offset + 4)));
        if (_isPrivateLanAddress(address)) return address;
      }
      offset += length;
    }
    return null;
  }

  int _skipDnsName(List<int> packet, int offset) {
    while (offset < packet.length) {
      final length = packet[offset];
      if (length == 0) return offset + 1;
      if ((length & 0xc0) == 0xc0) return offset + 2;
      offset += length + 1;
    }
    return packet.length;
  }

  int _readUint16(List<int> bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  bool _isPrivateLanAddress(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }
}

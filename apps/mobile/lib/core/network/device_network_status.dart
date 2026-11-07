import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final deviceNetworkStatusProvider =
    Provider<Future<bool?> Function()>((ref) => readDeviceNetworkStatus);

/// False means Android reports no active network. True is only a local link,
/// never proof of server reachability or valid authentication. Null is unknown.
Future<bool?> readDeviceNetworkStatus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await const MethodChannel('com.smartfarm.inventory/network-status')
        .invokeMethod<bool>('hasActiveNetwork')
        .timeout(const Duration(seconds: 1), onTimeout: () => null);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

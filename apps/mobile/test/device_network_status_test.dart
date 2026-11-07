import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/device_network_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.smartfarm.inventory/network-status');
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('Android negative is preserved; a local link is not server verification',
      () async {
    bool linked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'hasActiveNetwork');
      return linked;
    });
    expect(await readDeviceNetworkStatus(), isFalse);
    linked = true;
    expect(await readDeviceNetworkStatus(), isTrue);
  });
  test('unavailable platform channel is unknown, never guessed offline',
      () async {
    expect(await readDeviceNetworkStatus(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (_) async => throw PlatformException(code: 'unavailable'));
    expect(await readDeviceNetworkStatus(), isNull);
  });
}

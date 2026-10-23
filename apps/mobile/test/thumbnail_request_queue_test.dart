import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/features/gallery/application/thumbnail_request_queue.dart';

void main() {
  test('only two thumbnail HTTP operations run concurrently', () async {
    final queue = ThumbnailRequestQueue();
    final controls = List.generate(6, (_) => Completer<Uint8List>());
    var active = 0, peak = 0;
    final started = <int>[];
    final results = List.generate(
        6,
        (index) => queue.load(
            isCurrent: () => true,
            request: () async {
              started.add(index);
              active++;
              if (active > peak) peak = active;
              try {
                return await controls[index].future;
              } finally {
                active--;
              }
            }));
    expect(started, [0, 1]);
    for (var index = 0; index < controls.length; index++) {
      controls[index].complete(Uint8List.fromList([index]));
      await results[index];
    }
    expect(started, [0, 1, 2, 3, 4, 5]);
    expect(peak, 2);
    queue.dispose();
  });

  test('identity is checked again before queued HTTP begins', () async {
    final queue = ThumbnailRequestQueue();
    var isCurrent = true;
    var requests = 0;
    final issued = List.generate(2, (_) => Completer<Uint8List>());
    final results = List.generate(
        5,
        (index) => queue.load(
            isCurrent: () => isCurrent,
            request: () {
              requests++;
              return issued[index].future;
            }));
    expect(requests, 2);
    isCurrent = false;
    issued.first.complete(Uint8List(1));
    expect(await results[0], isNull);
    expect(await results[2], isNull);
    expect(await results[3], isNull);
    expect(await results[4], isNull);
    expect(requests, 2);
    issued.last.complete(Uint8List(1));
    expect(await results[1], isNull);
    queue.dispose();
  });

  test('new query starts independently of two old stalled requests', () async {
    final oldQueue = ThumbnailRequestQueue();
    final issued = List.generate(2, (_) => Completer<Uint8List>());
    var oldRequests = 0;
    final oldResults = List.generate(
        4,
        (index) => oldQueue.load(
            isCurrent: () => true,
            request: () {
              oldRequests++;
              return issued[index].future;
            }));
    oldQueue.dispose();
    expect(await oldResults[2], isNull);
    expect(await oldResults[3], isNull);
    final newQueue = ThumbnailRequestQueue();
    var newRequests = 0;
    expect(
        await newQueue.load(
            isCurrent: () => true,
            request: () async {
              newRequests++;
              return Uint8List.fromList([21]);
            }),
        [21]);
    expect(oldRequests, 2);
    expect(newRequests, 1);
    for (var index = 0; index < issued.length; index++) {
      issued[index].complete(Uint8List(1));
      expect(await oldResults[index], isNull);
    }
    newQueue.dispose();
  });
}

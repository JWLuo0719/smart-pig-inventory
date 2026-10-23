import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// One gallery query owns this queue. Closing it drops pending work and ignores
/// issued responses. A new query owns independent slots, so a stalled old
/// request cannot block another date, screen or login. No bytes are cached.
class ThumbnailRequestQueue {
  static const int maxConcurrent = 2;
  final Queue<_ThumbnailRequest> _pending = Queue<_ThumbnailRequest>();
  int _running = 0;
  bool _disposed = false;

  Future<Uint8List?> load({
    required bool Function() isCurrent,
    required Future<Uint8List> Function() request,
  }) {
    final job = _ThumbnailRequest(isCurrent, request);
    if (_disposed || !isCurrent()) {
      job.result.complete(null);
    } else {
      _pending.add(job);
      _drain();
    }
    return job.result.future;
  }

  void dispose() {
    _disposed = true;
    while (_pending.isNotEmpty) {
      _pending.removeFirst().result.complete(null);
    }
  }

  bool _isCurrent(_ThumbnailRequest job) => !_disposed && job.isCurrent();

  void _drain() {
    if (_disposed) return;
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeFirst();
      if (!_isCurrent(job)) {
        job.result.complete(null);
        continue;
      }
      _running++;
      unawaited(_execute(job));
    }
  }

  Future<void> _execute(_ThumbnailRequest job) async {
    try {
      if (!_isCurrent(job)) {
        job.result.complete(null);
        return;
      }
      final bytes = await job.request();
      job.result.complete(_isCurrent(job) ? bytes : null);
    } catch (error, stack) {
      if (_isCurrent(job)) {
        job.result.completeError(error, stack);
      } else {
        job.result.complete(null);
      }
    } finally {
      _running--;
      _drain();
    }
  }
}

class _ThumbnailRequest {
  _ThumbnailRequest(this.isCurrent, this.request);
  final bool Function() isCurrent;
  final Future<Uint8List> Function() request;
  final Completer<Uint8List?> result = Completer<Uint8List?>();
}

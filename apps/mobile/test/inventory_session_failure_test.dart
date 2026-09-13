import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/inventory_api.dart';

void main() {
  test('parses structured inference failure without inventing a count', () {
    final RemoteInventorySession session = RemoteInventorySession.fromJson(
      <String, dynamic>{
        'id': 'session-1',
        'penId': 'pen-1',
        'businessDate': '2026-08-31',
        'status': 'review_required',
        'count': null,
        'rawModelCount': null,
        'inferenceSource': 'provider-error',
        'warnings': <String>['Manual review required'],
        'inferenceStatus': 'failed',
        'failureCode': 'PROVIDER_TIMEOUT',
        'failureMessage': 'Counting provider timed out before returning a result',
      },
    );

    expect(session.requiresReview, isTrue);
    expect(session.count, isNull);
    expect(session.rawModelCount, isNull);
    expect(session.inferenceStatus, 'failed');
    expect(session.failureCode, 'PROVIDER_TIMEOUT');
  });
}

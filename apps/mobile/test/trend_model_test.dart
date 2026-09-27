import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pig_inventory/core/network/inventory_browse_api.dart';

void main() {
  test('parses the trend report with totals and per-pen series', () {
    final trend = RemoteTrend.fromJson(const {
      'from': '2026-09-06',
      'to': '2026-09-19',
      'total': [
        {'date': '2026-09-18', 'confirmed': 56, 'candidate': 56},
        {'date': '2026-09-19', 'confirmed': null, 'candidate': 27},
      ],
      'pens': [
        {
          'penId': 'p1',
          'penLabel': '01 1号栏舍',
          'points': [
            {'date': '2026-09-19', 'confirmed': null, 'candidate': 27},
          ],
        },
      ],
    });
    expect(trend.from, '2026-09-06');
    expect(trend.total.first.confirmed, 56);
    expect(trend.total.last.confirmed, isNull);
    expect(trend.total.last.candidate, 27);
    expect(trend.pens.single.penLabel, '01 1号栏舍');
    expect(trend.pens.single.points.single.candidate, 27);
  });

  test('seriesFor switches between organization total and one pen', () {
    final trend = RemoteTrend.fromJson(const {
      'from': '2026-09-06',
      'to': '2026-09-19',
      'total': [
        {'date': '2026-09-19', 'confirmed': 50, 'candidate': 50},
      ],
      'pens': [
        {
          'penId': 'p1',
          'penLabel': '01 1号栏舍',
          'points': [
            {'date': '2026-09-19', 'confirmed': 20, 'candidate': 20},
          ],
        },
      ],
    });
    final (totalLabel, totalPoints) = trend.seriesFor(null)!;
    expect(totalLabel, '全场合计');
    expect(totalPoints.single.confirmed, 50);
    final (penLabel, penPoints) = trend.seriesFor('p1')!;
    expect(penLabel, '01 1号栏舍');
    expect(penPoints.single.confirmed, 20);
    expect(trend.seriesFor('missing'), isNull);
  });
}

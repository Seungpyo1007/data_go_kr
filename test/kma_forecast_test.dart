import 'package:data_go_kr/data_go_kr.dart';
import 'package:test/test.dart';

/// A KST wall clock time expressed as UTC, so the tests do not depend on the
/// machine's time zone.
DateTime kst(int year, int month, int day, int hour, int minute) =>
    DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
    ).subtract(const Duration(hours: 9));

void main() {
  group('KmaBaseTime.latest', () {
    test('village forecast waits ten minutes after each slot', () {
      expect(
        KmaBaseTime.latest(KmaService.village, now: kst(2026, 9, 16, 5, 9)),
        const KmaBaseTime('20260916', '0200'),
      );
      expect(
        KmaBaseTime.latest(KmaService.village, now: kst(2026, 9, 16, 5, 10)),
        const KmaBaseTime('20260916', '0500'),
      );
      expect(
        KmaBaseTime.latest(KmaService.village, now: kst(2026, 9, 16, 23, 59)),
        const KmaBaseTime('20260916', '2300'),
      );
    });

    test('village forecast falls back to yesterday before 02:10', () {
      expect(
        KmaBaseTime.latest(KmaService.village, now: kst(2026, 9, 16, 0, 5)),
        const KmaBaseTime('20260915', '2300'),
      );
      expect(
        KmaBaseTime.latest(KmaService.village, now: kst(2026, 1, 1, 2, 9)),
        const KmaBaseTime('20251231', '2300'),
      );
    });

    test('nowcast waits 40 minutes past the hour', () {
      expect(
        KmaBaseTime.latest(
          KmaService.ultraShortNowcast,
          now: kst(2026, 9, 16, 10, 39),
        ),
        const KmaBaseTime('20260916', '0900'),
      );
      expect(
        KmaBaseTime.latest(
          KmaService.ultraShortNowcast,
          now: kst(2026, 9, 16, 10, 40),
        ),
        const KmaBaseTime('20260916', '1000'),
      );
      expect(
        KmaBaseTime.latest(
          KmaService.ultraShortNowcast,
          now: kst(2026, 9, 16, 0, 10),
        ),
        const KmaBaseTime('20260915', '2300'),
      );
    });

    test('ultra short forecast uses the half hour, 45 minutes later', () {
      expect(
        KmaBaseTime.latest(
          KmaService.ultraShortForecast,
          now: kst(2026, 9, 16, 10, 44),
        ),
        const KmaBaseTime('20260916', '0930'),
      );
      expect(
        KmaBaseTime.latest(
          KmaService.ultraShortForecast,
          now: kst(2026, 9, 16, 10, 45),
        ),
        const KmaBaseTime('20260916', '1030'),
      );
    });

    test('converts any time zone to Korea Standard Time', () {
      // 2026-09-16 01:00 UTC is 10:00 KST, so the 09:30 slot is the newest.
      final utc = DateTime.utc(2026, 9, 16, 1, 0);
      expect(
        KmaBaseTime.latest(KmaService.ultraShortForecast, now: utc),
        const KmaBaseTime('20260916', '0930'),
      );
      // The same instant written in another zone gives the same answer.
      final elsewhere = utc.add(const Duration(hours: 0)).toLocal();
      expect(
        KmaBaseTime.latest(KmaService.ultraShortForecast, now: elsewhere),
        const KmaBaseTime('20260916', '0930'),
      );
    });

    test('compares by value', () {
      expect(
        const KmaBaseTime('20260916', '0500'),
        const KmaBaseTime('20260916', '0500'),
      );
      expect(
        const KmaBaseTime('20260916', '0500').toString(),
        'KmaBaseTime(20260916, 0500)',
      );
    });
  });

  group('codes', () {
    test('reads sky conditions', () {
      expect(KmaSky.fromCode('1'), KmaSky.clear);
      expect(KmaSky.fromCode('3'), KmaSky.partlyCloudy);
      expect(KmaSky.fromCode('4')?.label, '흐림');
      expect(KmaSky.fromCode('2'), isNull);
    });

    test('reads precipitation, including ultra short only codes', () {
      expect(KmaPrecipitation.fromCode('0'), KmaPrecipitation.none);
      expect(KmaPrecipitation.fromCode('0')!.isWet, isFalse);
      expect(KmaPrecipitation.fromCode('4')?.label, '소나기');
      expect(KmaPrecipitation.fromCode('7'), KmaPrecipitation.snowFlurry);
      expect(KmaPrecipitation.fromCode('7')!.isWet, isTrue);
      expect(KmaPrecipitation.fromCode('9'), isNull);
    });

    test('describes category codes', () {
      expect(kmaCategory('TMP'), (label: '1시간 기온', unit: '℃'));
      expect(kmaCategory('wsd'), (label: '풍속', unit: 'm/s'));
      expect(kmaCategory(' POP ')?.unit, '%');
      expect(kmaCategory('NOPE'), isNull);
    });
  });
}

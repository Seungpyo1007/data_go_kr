import 'package:data_go_kr/data_go_kr.dart';
import 'package:test/test.dart';

Map<String, Object?> _row(
  String category,
  Object value, {
  String date = '20261022',
  String time = '1500',
  String baseDate = '20261022',
  String baseTime = '1100',
}) => {
  'baseDate': baseDate,
  'baseTime': baseTime,
  'category': category,
  'fcstDate': date,
  'fcstTime': time,
  'fcstValue': value,
  'nx': 60,
  'ny': 127,
};

void main() {
  group('KmaAmount.parse', () {
    KmaAmount mm(String raw, {bool qualitative = false}) =>
        KmaAmount.parse(raw, unit: 'mm', qualitative: qualitative);

    test('reads every precipitation class of the guide', () {
      expect(mm('강수없음').isNone, isTrue);
      expect(mm('강수없음').value, 0);
      expect(mm('-').isNone, isTrue);
      expect(mm('0').isNone, isTrue);
      expect(mm('').isNone, isTrue);

      final light = mm('1mm 미만');
      expect(light.kind, KmaAmountKind.lessThan);
      expect((light.min, light.max), (0, 1));
      expect(light.value, isNull);

      final exact = mm('6.2mm');
      expect(exact.kind, KmaAmountKind.exact);
      expect(exact.value, 6.2);

      final range = mm('30.0~50.0mm');
      expect(range.kind, KmaAmountKind.range);
      expect((range.min, range.max), (30, 50));

      final heavy = mm('50.0mm 이상');
      expect(heavy.kind, KmaAmountKind.atLeast);
      expect((heavy.min, heavy.max), (50, null));

      // A plain number, as the nowcast sends RN1.
      expect(mm('3.5').value, 3.5);
    });

    test('reads snow classes', () {
      final snow = KmaAmount.parse('0.5cm 미만', unit: 'cm');
      expect(
        (snow.kind, snow.max, snow.unit),
        (KmaAmountKind.lessThan, 0.5, 'cm'),
      );
      expect(KmaAmount.parse('적설없음', unit: 'cm').isNone, isTrue);
      expect(KmaAmount.parse('5.0cm 이상', unit: 'cm').min, 5);
    });

    test('reads the missing marker', () {
      expect(mm('900').isMissing, isTrue);
      expect(mm('-999').isMissing, isTrue);
      expect(mm('899').isMissing, isFalse);
      expect(mm('900').min, isNull);
    });

    test('reads qualitative codes of the extended range', () {
      expect(mm('2', qualitative: true).intensity, KmaIntensity.moderateRain);
      expect(
        KmaAmount.parse('2', unit: 'cm', qualitative: true).intensity,
        KmaIntensity.heavySnow,
      );
      final wind = KmaAmount.parse('3', unit: 'm/s', qualitative: true);
      expect(wind.intensity, KmaIntensity.strongWind);
      expect((wind.min, wind.max), (9, null));
      // Labels are read too, with or without the flag.
      expect(mm('약한 비').intensity, KmaIntensity.lightRain);
      // Without the flag, a number is an amount.
      expect(mm('2').value, 2);
      // A code out of range is read as a number.
      expect(mm('4', qualitative: true).value, 4);
    });

    test('rejects unknown text', () {
      expect(() => mm('많이 옴'), throwsFormatException);
    });
  });

  test('KmaCompass follows the guide formula', () {
    expect(KmaCompass.fromDegrees(0), KmaCompass.n);
    expect(KmaCompass.fromDegrees(11.24), KmaCompass.n);
    expect(KmaCompass.fromDegrees(11.25), KmaCompass.nne);
    expect(KmaCompass.fromDegrees(90), KmaCompass.e);
    // The guide's own example: 339 → 15.56 → 15.
    expect(KmaCompass.fromDegrees(339), KmaCompass.nnw);
    expect(KmaCompass.fromDegrees(350), KmaCompass.n);
    expect(KmaCompass.fromDegrees(360), KmaCompass.n);
    expect(KmaCompass.nnw.label, '북북서');
  });

  group('KmaForecast.fromItems', () {
    test('groups rows by time and reads every category', () {
      final forecast = KmaForecast.fromItems([
        _row('TMP', '21'),
        _row('SKY', '3'),
        _row('PTY', '1'),
        _row('POP', '60'),
        _row('PCP', '1mm 미만'),
        _row('SNO', '적설없음'),
        _row('REH', '85'),
        _row('WSD', '2.1'),
        _row('VEC', '339'),
        _row('UUU', '-0.8'),
        _row('VVV', '1.9'),
        _row('WAV', '0.5'),
        _row('TMP', '19', time: '1600'),
        _row('TMX', '23.0', time: '1500'),
        _row('TMN', '12.0', date: '20261023', time: '0600'),
      ]);

      expect(forecast.hours, hasLength(2));
      final hour = forecast.hours.first;
      expect(hour.date, '20261022');
      expect(hour.hourText, '1500');
      // 15:00 KST is 06:00 UTC.
      expect(hour.time, DateTime.utc(2026, 10, 22, 6));
      expect(hour.temperature, 21);
      expect(hour.sky, KmaSky.partlyCloudy);
      expect(hour.precipitationType, KmaPrecipitation.rain);
      expect(hour.precipitationProbability, 60);
      expect(hour.precipitation?.kind, KmaAmountKind.lessThan);
      expect(hour.snow?.isNone, isTrue);
      expect(hour.humidity, 85);
      expect(hour.windSpeed?.value, 2.1);
      expect(hour.windDirection, 339);
      expect(hour.compass, KmaCompass.nnw);
      expect((hour.windEastward, hour.windNorthward), (-0.8, 1.9));
      expect(hour.waveHeight, 0.5);
      expect(hour.isExtended, isFalse);
      expect(hour.values['TMP'], '21');
      expect(forecast.hours.last.temperature, 19);

      expect(forecast.days.map((d) => (d.date, d.low, d.high)), [
        ('20261022', null, 23.0),
        ('20261023', 12.0, null),
      ]);
    });

    test('drops the missing marker', () {
      final hour = KmaForecast.fromItems([
        _row('TMP', '-999'),
        _row('REH', '900'),
        _row('PCP', '999'),
        _row('SKY', '1'),
      ]).hours.single;
      expect(hour.temperature, isNull);
      expect(hour.humidity, isNull);
      expect(hour.precipitation, isNull);
      expect(hour.sky, KmaSky.clear);
    });

    test('reads PCP, SNO, and WSD as codes in the extended range', () {
      // A 11:00 slot's extended range starts three days later (글피); a
      // 17:00 slot's four days later (그글피).
      final forecast = KmaForecast.fromItems([
        _row('PCP', '2', date: '20261024'),
        _row('PCP', '2', date: '20261025'),
        _row('WSD', '3', date: '20261025', time: '1800'),
        _row('SNO', '1', date: '20261028', baseTime: '1700', time: '0000'),
        _row('SNO', '1', date: '20261025', baseTime: '1700', time: '0300'),
      ]);
      final byKey = {
        for (final h in forecast.hours) '${h.date}${h.hourText}': h,
      };

      expect(byKey['202610241500']!.isExtended, isFalse);
      expect(byKey['202610241500']!.precipitation?.value, 2);
      expect(byKey['202610251500']!.isExtended, isTrue);
      expect(
        byKey['202610251500']!.precipitation?.intensity,
        KmaIntensity.moderateRain,
      );
      expect(
        byKey['202610251800']!.windSpeed?.intensity,
        KmaIntensity.strongWind,
      );
      expect(byKey['202610280000']!.snow?.intensity, KmaIntensity.moderateSnow);
      // Three days after a 17:00 slot is not extended yet.
      expect(byKey['202610250300']!.snow?.value, 1);
    });

    test('places nowcast rows at their base time', () {
      final forecast = KmaForecast.fromItems([
        {
          'baseDate': '20261022',
          'baseTime': '1400',
          'category': 'T1H',
          'obsrValue': '18.4',
          'nx': 60,
          'ny': 127,
        },
        {
          'baseDate': '20261022',
          'baseTime': '1400',
          'category': 'RN1',
          'obsrValue': '0',
          'nx': 60,
          'ny': 127,
        },
      ]);
      final now = forecast.hours.single;
      expect(now.hourText, '1400');
      expect(now.temperature, 18.4);
      expect(now.precipitation?.isNone, isTrue);
    });

    test('reads POP of the ultra short forecast', () {
      final hour = KmaForecast.fromItems([
        _row('T1H', '17', baseTime: '1430'),
        _row('POP', '30', baseTime: '1430'),
        _row('RN1', '1.0mm', baseTime: '1430'),
        _row('LGT', '0', baseTime: '1430'),
      ]).hours.single;
      expect(hour.temperature, 17);
      expect(hour.precipitationProbability, 30);
      expect(hour.precipitation?.value, 1);
      expect(hour.lightning, 0);
    });

    test('at finds the forecast time an instant falls in', () {
      final forecast = KmaForecast.fromItems([
        _row('TMP', '21', time: '1500'),
        _row('TMP', '19', time: '1600'),
      ]);
      expect(forecast.at(DateTime.utc(2026, 10, 22, 5, 59)), isNull);
      expect(forecast.at(DateTime.utc(2026, 10, 22, 6, 30))?.temperature, 21);
      expect(forecast.at(DateTime.utc(2026, 10, 22, 9))?.temperature, 19);
    });
  });

  group('KmaBaseTime', () {
    // 2026-10-22 in KST.
    DateTime kst(int hour, int minute) => DateTime.utc(
      2026,
      10,
      22,
      hour,
      minute,
    ).subtract(const Duration(hours: 9));

    test('a longer delay steps back to the slot before', () {
      expect(
        KmaBaseTime.latest(KmaService.village, now: kst(14, 15)),
        const KmaBaseTime('20261022', '1400'),
      );
      expect(
        KmaBaseTime.latest(
          KmaService.village,
          now: kst(14, 15),
          delay: const Duration(minutes: 20),
        ),
        const KmaBaseTime('20261022', '1100'),
      );
      expect(
        KmaBaseTime.latest(
          KmaService.ultraShortNowcast,
          now: kst(0, 15),
          delay: const Duration(minutes: 20),
        ),
        const KmaBaseTime('20261021', '2300'),
      );
    });

    test('previous steps back one slot across midnight', () {
      expect(
        const KmaBaseTime('20261022', '0200').previous(KmaService.village),
        const KmaBaseTime('20261021', '2300'),
      );
      expect(
        const KmaBaseTime('20261022', '1400').previous(KmaService.village),
        const KmaBaseTime('20261022', '1100'),
      );
      expect(
        const KmaBaseTime(
          '20260301',
          '0030',
        ).previous(KmaService.ultraShortForecast),
        const KmaBaseTime('20260228', '2330'),
      );
      expect(
        const KmaBaseTime(
          '20270101',
          '0000',
        ).previous(KmaService.ultraShortNowcast),
        const KmaBaseTime('20261231', '2300'),
      );
    });
  });
}

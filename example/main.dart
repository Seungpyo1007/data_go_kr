import 'dart:io';

import 'package:data_go_kr/data_go_kr.dart';

/// Reads the newest short-term forecast for Seoul City Hall:
///
///     DATA_GO_KR_KEY=<decoded key> dart run example/main.dart
///
/// The key must be approved for 기상청_단기예보 조회서비스 on data.go.kr.
Future<void> main() async {
  final key = Platform.environment['DATA_GO_KR_KEY'];
  if (key == null || key.isEmpty) {
    print('Set DATA_GO_KR_KEY to your decoded data.go.kr service key.');
    return;
  }

  final cell = KmaGrid.fromLatLon(37.5665, 126.9780); // Seoul City Hall
  var base = KmaBaseTime.latest(KmaService.village);
  print('grid ${cell.nx},${cell.ny} | base ${base.date} ${base.time}');

  final client = DataGoKrClient(serviceKey: key);
  try {
    Future<DataGoKrResponse> read(KmaBaseTime base) => client.get(
      'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst',
      query: {
        'base_date': base.date,
        'base_time': base.time,
        'nx': cell.nx,
        'ny': cell.ny,
      },
      rows: 1000,
    );

    var page = await read(base);
    if (page.isEmpty) {
      // Published late: use the slot before.
      base = base.previous(KmaService.village);
      page = await read(base);
    }

    final forecast = KmaForecast.fromItems(page.items);
    for (final day in forecast.days) {
      print('${day.date}  최저 ${day.low ?? '-'}℃  최고 ${day.high ?? '-'}℃');
    }
    for (final hour in forecast.hours.take(12)) {
      print(
        '${hour.date} ${hour.hourText}  '
        '${hour.temperature}℃  ${hour.sky?.label ?? '-'}  '
        '강수 ${hour.precipitationProbability ?? '-'}% '
        '${_describe(hour.precipitation)}  '
        '바람 ${hour.compass?.label ?? '-'} ${_describe(hour.windSpeed)}',
      );
    }
  } on DataGoKrException catch (error) {
    print('${error.code}: $error');
  } finally {
    client.close();
  }
}

/// `강수없음`-style values stay quiet; codes of the extended range show their
/// class; everything else shows as KMA sent it.
String _describe(KmaAmount? amount) => switch (amount) {
  null || KmaAmount(isNone: true) => '',
  KmaAmount(:final intensity?) => intensity.label,
  KmaAmount(kind: KmaAmountKind.exact, :final value, :final unit) =>
    '$value$unit',
  KmaAmount(:final raw) => raw,
};

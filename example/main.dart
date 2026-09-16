import 'dart:io';

import 'package:data_go_kr/data_go_kr.dart';

/// Reads the newest short-term forecast for Seoul City Hall:
///
///     DATA_GO_KR_KEY=<decoded key> dart run example/main.dart
Future<void> main() async {
  final key = Platform.environment['DATA_GO_KR_KEY'];
  if (key == null || key.isEmpty) {
    print('Set DATA_GO_KR_KEY to your decoded data.go.kr service key.');
    return;
  }

  final cell = KmaGrid.fromLatLon(37.5665, 126.9780); // Seoul City Hall
  final base = KmaBaseTime.latest(KmaService.village);
  print('grid ${cell.nx},${cell.ny} | base ${base.date} ${base.time}');

  final client = DataGoKrClient(serviceKey: key);
  try {
    final forecast = await client.get(
      'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst',
      query: {
        'base_date': base.date,
        'base_time': base.time,
        'nx': cell.nx,
        'ny': cell.ny,
      },
      rows: 8,
    );

    print(
      '${forecast.totalCount} rows total, showing ${forecast.items.length}',
    );
    for (final row in forecast.items) {
      final category = '${row['category']}';
      final value = '${row['fcstValue']}';
      final reading = switch (category) {
        'SKY' => '하늘상태: ${KmaSky.fromCode(value)?.label ?? value}',
        'PTY' => '강수형태: ${KmaPrecipitation.fromCode(value)?.label ?? value}',
        _ =>
          '${kmaCategory(category)?.label ?? category}: '
              '$value${kmaCategory(category)?.unit ?? ''}',
      };
      print('  ${row['fcstTime']}  $reading');
    }
  } on DataGoKrException catch (error) {
    print('${error.code}: $error');
  } finally {
    client.close();
  }
}

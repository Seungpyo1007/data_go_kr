import 'dart:io';

import 'package:data_go_kr/data_go_kr.dart';

/// Reads a short-term forecast from the Korea Meteorological Administration:
///
///     DATA_GO_KR_KEY=<decoded key> dart run example/main.dart
Future<void> main() async {
  final key = Platform.environment['DATA_GO_KR_KEY'];
  if (key == null || key.isEmpty) {
    print('Set DATA_GO_KR_KEY to your decoded data.go.kr service key.');
    return;
  }

  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  final baseDate =
      '${yesterday.year}'
      '${yesterday.month.toString().padLeft(2, '0')}'
      '${yesterday.day.toString().padLeft(2, '0')}';

  final client = DataGoKrClient(serviceKey: key);
  try {
    final response = await client.get(
      'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst',
      query: {'base_date': baseDate, 'base_time': '0500', 'nx': 60, 'ny': 127},
      rows: 5,
    );
    print(
      '${response.totalCount} rows total, showing ${response.items.length}',
    );
    for (final row in response.items) {
      print('  ${row['fcstTime']} ${row['category']} = ${row['fcstValue']}');
    }
  } on DataGoKrException catch (error) {
    print('${error.code}: $error');
  } finally {
    client.close();
  }
}

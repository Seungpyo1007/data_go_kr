import 'client.dart';

/// An AirKorea index grade, used by every `*Grade` field.
enum AirQualityGrade {
  /// `1`, 좋음.
  good(1, '좋음'),

  /// `2`, 보통.
  moderate(2, '보통'),

  /// `3`, 나쁨.
  bad(3, '나쁨'),

  /// `4`, 매우나쁨.
  veryBad(4, '매우나쁨');

  const AirQualityGrade(this.code, this.label);

  /// The value the API sends.
  final int code;

  /// Korean label used by AirKorea.
  final String label;

  /// Reads a grade, or returns `null` for an empty or unknown one.
  static AirQualityGrade? fromCode(Object? code) {
    final number = int.tryParse('${code ?? ''}'.trim());
    for (final grade in values) {
      if (grade.code == number) return grade;
    }
    return null;
  }
}

/// How far back a station query reaches, the `dataTerm` parameter.
enum AirKoreaPeriod {
  /// `DAILY`, the last day.
  day('DAILY'),

  /// `MONTH`, the last month.
  month('MONTH'),

  /// `3MONTH`, the last three months.
  threeMonths('3MONTH');

  const AirKoreaPeriod(this.code);

  /// The value the API takes.
  final String code;
}

/// One hourly measurement at an AirKorea station.
///
/// Values are `null` when the station sent `-` or nothing, which happens
/// while an instrument is checked; the matching `*Flag` says why.
class AirQualityMeasurement {
  /// Creates a measurement.
  const AirQualityMeasurement({
    required this.dataTime,
    required this.dataTimeText,
    this.stationName,
    this.stationCode,
    this.sidoName,
    this.networkType,
    this.so2,
    this.co,
    this.o3,
    this.no2,
    this.pm10,
    this.pm10Day,
    this.pm25,
    this.pm25Day,
    this.khaiValue,
    this.khaiGrade,
    this.so2Grade,
    this.coGrade,
    this.o3Grade,
    this.no2Grade,
    this.pm10Grade,
    this.pm25Grade,
    this.pm10Grade1h,
    this.pm25Grade1h,
    this.so2Flag,
    this.coFlag,
    this.o3Flag,
    this.no2Flag,
    this.pm10Flag,
    this.pm25Flag,
    this.raw = const <String, Object?>{},
  });

  /// Reads one row of `getMsrstnAcctoRltmMesureDnsty` or
  /// `getCtprvnRltmMesureDnsty`.
  factory AirQualityMeasurement.fromRow(Map<String, Object?> row) {
    String? text(String key) {
      final value = '${row[key] ?? ''}'.trim();
      return value.isEmpty || value == '-' ? null : value;
    }

    double? number(String key) => double.tryParse(text(key) ?? '');
    final time = text('dataTime') ?? '';
    return AirQualityMeasurement(
      dataTime: _parseDataTime(time),
      dataTimeText: time,
      stationName: text('stationName'),
      stationCode: text('stationCode'),
      sidoName: text('sidoName'),
      networkType: text('mangName'),
      so2: number('so2Value'),
      co: number('coValue'),
      o3: number('o3Value'),
      no2: number('no2Value'),
      pm10: number('pm10Value'),
      pm10Day: number('pm10Value24'),
      pm25: number('pm25Value'),
      pm25Day: number('pm25Value24'),
      khaiValue: number('khaiValue'),
      khaiGrade: AirQualityGrade.fromCode(text('khaiGrade')),
      so2Grade: AirQualityGrade.fromCode(text('so2Grade')),
      coGrade: AirQualityGrade.fromCode(text('coGrade')),
      o3Grade: AirQualityGrade.fromCode(text('o3Grade')),
      no2Grade: AirQualityGrade.fromCode(text('no2Grade')),
      pm10Grade: AirQualityGrade.fromCode(text('pm10Grade')),
      pm25Grade: AirQualityGrade.fromCode(text('pm25Grade')),
      pm10Grade1h: AirQualityGrade.fromCode(text('pm10Grade1h')),
      pm25Grade1h: AirQualityGrade.fromCode(text('pm25Grade1h')),
      so2Flag: text('so2Flag'),
      coFlag: text('coFlag'),
      o3Flag: text('o3Flag'),
      no2Flag: text('no2Flag'),
      pm10Flag: text('pm10Flag'),
      pm25Flag: text('pm25Flag'),
      raw: Map.unmodifiable(row),
    );
  }

  /// When the hour ended, in UTC, or `null` when [dataTimeText] does not
  /// parse. AirKorea writes midnight as `24:00` of the day before.
  final DateTime? dataTime;

  /// `dataTime` as sent, `yyyy-MM-dd HH:mm` in Korea Standard Time.
  final String dataTimeText;

  /// `stationName`, such as `종로구`.
  final String? stationName;

  /// `stationCode`.
  final String? stationCode;

  /// `sidoName`, sent by province queries.
  final String? sidoName;

  /// `mangName`: 도시대기, 도로변대기, 국가배경농도, 교외대기, or 항만.
  final String? networkType;

  /// `so2Value`, sulfur dioxide in ppm.
  final double? so2;

  /// `coValue`, carbon monoxide in ppm.
  final double? co;

  /// `o3Value`, ozone in ppm.
  final double? o3;

  /// `no2Value`, nitrogen dioxide in ppm.
  final double? no2;

  /// `pm10Value`, PM10 in µg/m³.
  final double? pm10;

  /// `pm10Value24`, the predicted 24-hour moving average of PM10 in µg/m³.
  final double? pm10Day;

  /// `pm25Value`, PM2.5 in µg/m³.
  final double? pm25;

  /// `pm25Value24`, the predicted 24-hour moving average of PM2.5 in µg/m³.
  final double? pm25Day;

  /// `khaiValue`, the Comprehensive Air-quality Index (통합대기환경수치).
  final double? khaiValue;

  /// `khaiGrade`.
  final AirQualityGrade? khaiGrade;

  /// `so2Grade`.
  final AirQualityGrade? so2Grade;

  /// `coGrade`.
  final AirQualityGrade? coGrade;

  /// `o3Grade`.
  final AirQualityGrade? o3Grade;

  /// `no2Grade`.
  final AirQualityGrade? no2Grade;

  /// `pm10Grade`, the 24-hour grade.
  final AirQualityGrade? pm10Grade;

  /// `pm25Grade`, the 24-hour grade.
  final AirQualityGrade? pm25Grade;

  /// `pm10Grade1h`, the one-hour grade.
  final AirQualityGrade? pm10Grade1h;

  /// `pm25Grade1h`, the one-hour grade.
  final AirQualityGrade? pm25Grade1h;

  /// `so2Flag`: 점검및교정, 장비점검, 자료이상, or 통신장애 when the value is
  /// unreliable.
  final String? so2Flag;

  /// `coFlag`.
  final String? coFlag;

  /// `o3Flag`.
  final String? o3Flag;

  /// `no2Flag`.
  final String? no2Flag;

  /// `pm10Flag`.
  final String? pm10Flag;

  /// `pm25Flag`.
  final String? pm25Flag;

  /// The row as the service sent it.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      'AirQualityMeasurement($stationName $dataTimeText, PM10 $pm10, '
      'PM2.5 $pm25)';
}

/// Real-time air pollution from AirKorea (한국환경공단 에어코리아 대기오염정보,
/// `ArpltnInforInqireSvc`).
///
/// Apply for "한국환경공단_에어코리아_대기오염정보" on data.go.kr; the
/// client's service key must be approved for it. Requests use version 1.5 of
/// each operation, which includes PM2.5, 24-hour averages, one-hour grades,
/// station codes, and the network type.
///
/// ```dart
/// final now = await AirKorea(client).station('종로구');
/// print('${now.first.pm10} µg/m³, ${now.first.pm10Grade?.label}');
/// ```
class AirKorea {
  /// Wraps [client].
  AirKorea(this.client);

  /// The client that sends the requests.
  final DataGoKrClient client;

  /// Base URL of the service.
  static const endpoint =
      'https://apis.data.go.kr/B552584/ArpltnInforInqireSvc';

  /// Measurements at one station (`getMsrstnAcctoRltmMesureDnsty`), newest
  /// first, as the service orders them.
  ///
  /// [stationName] is an AirKorea station such as `종로구`; AirKorea's station
  /// service (`MsrstnInfoInqireSvc`) lists them.
  Future<List<AirQualityMeasurement>> station(
    String stationName, {
    AirKoreaPeriod period = AirKoreaPeriod.day,
    int maxPages = 100,
  }) => _rows('getMsrstnAcctoRltmMesureDnsty', {
    'stationName': stationName,
    'dataTerm': period.code,
  }, maxPages);

  /// The latest measurement at every station of a province
  /// (`getCtprvnRltmMesureDnsty`).
  ///
  /// [sidoName] is one of 전국, 서울, 부산, 대구, 인천, 광주, 대전, 울산, 경기,
  /// 강원, 충북, 충남, 전북, 전남, 경북, 경남, 제주, 세종, or 전남광주.
  Future<List<AirQualityMeasurement>> province(
    String sidoName, {
    int maxPages = 100,
  }) => _rows('getCtprvnRltmMesureDnsty', {'sidoName': sidoName}, maxPages);

  Future<List<AirQualityMeasurement>> _rows(
    String operation,
    Map<String, Object?> query,
    int maxPages,
  ) async {
    final rows = <AirQualityMeasurement>[];
    await for (final row in client.paginate(
      '$endpoint/$operation',
      // This service takes returnType, not dataType.
      query: {...query, 'returnType': 'json', 'ver': '1.5'},
      maxPages: maxPages,
    )) {
      rows.add(AirQualityMeasurement.fromRow(row));
    }
    return rows;
  }
}

/// Reads `yyyy-MM-dd HH:mm` in KST, where `24:00` is the next midnight.
DateTime? _parseDataTime(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
  ).firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  if (hour > 24 || minute > 59 || (hour == 24 && minute != 0)) return null;
  return DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    hour,
    minute,
  ).subtract(const Duration(hours: 9));
}

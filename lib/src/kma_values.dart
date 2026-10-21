import 'kma_forecast.dart';

// Rules on this page come from the KMA guide, 기상청41_단기예보 조회서비스
// 오픈API활용가이드 (2026-10), sections "코드값 정보", "특정 요소의 코드값 및
// 범주", and "단기예보 연장에 따른 코드값 정보".

/// Whether a KMA value is a missing marker: the guide reserves `+900` and
/// above and `-900` and below for "no data", as over the sea or when an
/// instrument fails.
bool isKmaMissing(num value) => value >= 900 || value <= -900;

/// How a [KmaAmount] is given.
enum KmaAmountKind {
  /// None fell: `강수없음`, `적설없음`, `-`, `0`, or an empty value.
  none,

  /// Below a bound, such as `1mm 미만`: [KmaAmount.max] is the bound.
  lessThan,

  /// An exact amount, such as `6.2mm`: [KmaAmount.value] is set.
  exact,

  /// A range, such as `30.0~50.0mm`.
  range,

  /// At least a bound, such as `50.0mm 이상`: [KmaAmount.min] is the bound.
  atLeast,

  /// A qualitative code from the extended village forecast, such as
  /// `약한 비`: [KmaAmount.intensity] is set, with the range it stands for.
  qualitative,

  /// The missing marker (`+900` and above, `-900` and below).
  missing,
}

/// Qualitative amounts the village forecast gives instead of numbers on its
/// last day (글피 for slots up to 14:00, 그글피 for 17:00 and later).
enum KmaIntensity {
  /// Precipitation `1`, 약한 비: under 3 mm an hour.
  lightRain('약한 비', 0, 3),

  /// Precipitation `2`, 보통 비: 3 to 15 mm an hour.
  moderateRain('보통 비', 3, 15),

  /// Precipitation `3`, 강한 비: 15 mm an hour or more.
  heavyRain('강한 비', 15, null),

  /// Snow `1`, 보통 눈: under 1 cm an hour.
  moderateSnow('보통 눈', 0, 1),

  /// Snow `2`, 많은 눈: 1 cm an hour or more.
  heavySnow('많은 눈', 1, null),

  /// Wind `1`, 약한 바람: under 4 m/s.
  ///
  /// The guide's table says "4m/s 이상의 약한 바람"; the next class starts at
  /// 4 m/s, so this one is read as below it.
  lightWind('약한 바람', 0, 4),

  /// Wind `2`, 약간 강한 바람: 4 to 9 m/s.
  moderateWind('약간 강한 바람', 4, 9),

  /// Wind `3`, 강한 바람: 9 m/s or more.
  strongWind('강한 바람', 9, null);

  const KmaIntensity(this.label, this.min, this.max);

  /// Korean label used by KMA.
  final String label;

  /// Lower end of the class.
  final double min;

  /// Upper end of the class, exclusive, or `null` when it has none.
  final double? max;
}

/// An amount of precipitation (`PCP`, `RN1`), new snow (`SNO`), or wind
/// speed (`WSD`) as KMA sends it: often a class such as `1mm 미만` rather
/// than a number.
///
/// ```dart
/// KmaAmount.parse('30.0~50.0mm', unit: 'mm'); // range 30 to 50
/// KmaAmount.parse('강수없음', unit: 'mm').isNone; // true
/// ```
class KmaAmount {
  /// Creates an amount.
  const KmaAmount({
    required this.kind,
    required this.unit,
    required this.raw,
    this.min,
    this.max,
    this.intensity,
  });

  /// Reads a value as the API sends it.
  ///
  /// [unit] is the category's unit (`mm`, `cm`, or `m/s`); a unit inside
  /// [raw] is accepted and dropped. Set [qualitative] for values of the
  /// extended village forecast, where `PCP`, `SNO`, and `WSD` are codes;
  /// [KmaForecast] sets it for you. Text this method does not recognize
  /// throws a [FormatException].
  factory KmaAmount.parse(
    String raw, {
    required String unit,
    bool qualitative = false,
  }) {
    final text = raw.trim();
    KmaAmount of(KmaAmountKind kind, {double? min, double? max}) =>
        KmaAmount(kind: kind, unit: unit, raw: raw, min: min, max: max);

    if (text.isEmpty ||
        text == '-' ||
        text == 'null' ||
        text == '강수없음' ||
        text == '적설없음') {
      return of(KmaAmountKind.none, min: 0, max: 0);
    }
    final plain = double.tryParse(text);
    if (plain != null && isKmaMissing(plain)) {
      return of(KmaAmountKind.missing);
    }
    if (qualitative) {
      final intensity = _intensityFor(text, unit);
      if (intensity != null) {
        return KmaAmount(
          kind: KmaAmountKind.qualitative,
          unit: unit,
          raw: raw,
          min: intensity.min,
          max: intensity.max,
          intensity: intensity,
        );
      }
    }
    if (plain != null) {
      return plain == 0
          ? of(KmaAmountKind.none, min: 0, max: 0)
          : of(KmaAmountKind.exact, min: plain, max: plain);
    }

    // Drop the unit and spaces: "1.0 mm 미만" reads like "1.0미만".
    final bare = text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'(mm|cm|m/s)', caseSensitive: false), '');
    final number = r'(\d+(?:\.\d+)?)';
    if (RegExp('^$number\$').firstMatch(bare) case final m?) {
      final value = double.parse(m[1]!);
      return of(KmaAmountKind.exact, min: value, max: value);
    }
    if (RegExp('^$number미만\$').firstMatch(bare) case final m?) {
      return of(KmaAmountKind.lessThan, min: 0, max: double.parse(m[1]!));
    }
    if (RegExp('^$number이상\$').firstMatch(bare) case final m?) {
      return of(KmaAmountKind.atLeast, min: double.parse(m[1]!));
    }
    if (RegExp('^$number~$number\$').firstMatch(bare) case final m?) {
      return of(
        KmaAmountKind.range,
        min: double.parse(m[1]!),
        max: double.parse(m[2]!),
      );
    }
    final named = _intensityFor(text, unit);
    if (named != null) {
      return KmaAmount(
        kind: KmaAmountKind.qualitative,
        unit: unit,
        raw: raw,
        min: named.min,
        max: named.max,
        intensity: named,
      );
    }
    throw FormatException('Not a KMA amount', raw);
  }

  /// How the amount is given.
  final KmaAmountKind kind;

  /// Unit of [min] and [max]: `mm`, `cm`, or `m/s`.
  final String unit;

  /// The value as the API sent it.
  final String raw;

  /// Lower end, `0` for [KmaAmountKind.none] and [KmaAmountKind.lessThan],
  /// or `null` when missing.
  final double? min;

  /// Upper end (exclusive for a class), or `null` when there is none or the
  /// value is missing.
  final double? max;

  /// The class of a qualitative value.
  final KmaIntensity? intensity;

  /// The exact amount, when one was given; `0` when none fell.
  double? get value => switch (kind) {
    KmaAmountKind.exact => min,
    KmaAmountKind.none => 0,
    _ => null,
  };

  /// Whether none fell.
  bool get isNone => kind == KmaAmountKind.none;

  /// Whether the value is the missing marker.
  bool get isMissing => kind == KmaAmountKind.missing;

  static KmaIntensity? _intensityFor(String text, String unit) {
    for (final intensity in KmaIntensity.values) {
      if (intensity.label == text) return intensity;
    }
    final code = int.tryParse(text);
    if (code == null) return null;
    final group = switch (unit) {
      'mm' => const [
        KmaIntensity.lightRain,
        KmaIntensity.moderateRain,
        KmaIntensity.heavyRain,
      ],
      'cm' => const [KmaIntensity.moderateSnow, KmaIntensity.heavySnow],
      _ => const [
        KmaIntensity.lightWind,
        KmaIntensity.moderateWind,
        KmaIntensity.strongWind,
      ],
    };
    return code >= 1 && code <= group.length ? group[code - 1] : null;
  }

  @override
  bool operator ==(Object other) =>
      other is KmaAmount &&
      other.kind == kind &&
      other.unit == unit &&
      other.min == min &&
      other.max == max &&
      other.intensity == intensity;

  @override
  int get hashCode => Object.hash(kind, unit, min, max, intensity);

  @override
  String toString() => 'KmaAmount($raw)';
}

/// The 16 compass points KMA names wind directions with.
enum KmaCompass {
  /// North.
  n('N', '북'),

  /// North-northeast.
  nne('NNE', '북북동'),

  /// Northeast.
  ne('NE', '북동'),

  /// East-northeast.
  ene('ENE', '동북동'),

  /// East.
  e('E', '동'),

  /// East-southeast.
  ese('ESE', '동남동'),

  /// Southeast.
  se('SE', '남동'),

  /// South-southeast.
  sse('SSE', '남남동'),

  /// South.
  s('S', '남'),

  /// South-southwest.
  ssw('SSW', '남남서'),

  /// Southwest.
  sw('SW', '남서'),

  /// West-southwest.
  wsw('WSW', '서남서'),

  /// West.
  w('W', '서'),

  /// West-northwest.
  wnw('WNW', '서북서'),

  /// Northwest.
  nw('NW', '북서'),

  /// North-northwest.
  nnw('NNW', '북북서');

  const KmaCompass(this.symbol, this.label);

  /// English abbreviation, such as `NNE`.
  final String symbol;

  /// Korean name, such as `북북동`.
  final String label;

  /// The point for a `VEC` value in degrees, with the guide's formula
  /// `(VEC + 22.5 * 0.5) / 22.5`, truncated; 16 wraps to north.
  static KmaCompass fromDegrees(num degrees) {
    final index = ((degrees % 360) + 22.5 * 0.5) ~/ 22.5;
    return values[index % 16];
  }
}

/// One forecast time with every category KMA sent for it.
///
/// Values are `null` when the service did not send the category for this
/// time, or sent the missing marker.
class KmaForecastHour {
  /// Creates a forecast time.
  const KmaForecastHour({
    required this.time,
    required this.date,
    required this.hourText,
    this.isExtended = false,
    this.temperature,
    this.sky,
    this.precipitationType,
    this.precipitationProbability,
    this.precipitation,
    this.snow,
    this.humidity,
    this.windSpeed,
    this.windDirection,
    this.windEastward,
    this.windNorthward,
    this.waveHeight,
    this.lightning,
    this.values = const <String, String>{},
  });

  /// The instant this forecast is for, in UTC.
  final DateTime time;

  /// `yyyyMMdd` in Korea Standard Time (`fcstDate`, or `baseDate` for a
  /// nowcast).
  final String date;

  /// `HHmm` in Korea Standard Time (`fcstTime`, or `baseTime` for a
  /// nowcast).
  final String hourText;

  /// Whether this time is in the extended range of the village forecast:
  /// three-hourly, with qualitative precipitation, snow, and wind.
  final bool isExtended;

  /// `TMP` or `T1H`, in ℃.
  final double? temperature;

  /// `SKY`.
  final KmaSky? sky;

  /// `PTY`.
  final KmaPrecipitation? precipitationType;

  /// `POP`, in percent. The ultra short forecast sends it since 2026-06-23.
  final int? precipitationProbability;

  /// `PCP` or `RN1`.
  final KmaAmount? precipitation;

  /// `SNO`.
  final KmaAmount? snow;

  /// `REH`, in percent.
  final int? humidity;

  /// `WSD`; qualitative in the extended range.
  final KmaAmount? windSpeed;

  /// `VEC`, in degrees. See [compass].
  final int? windDirection;

  /// `UUU`, in m/s; positive is eastward.
  final double? windEastward;

  /// `VVV`, in m/s; positive is northward.
  final double? windNorthward;

  /// `WAV`, in metres.
  final double? waveHeight;

  /// `LGT`, in kA.
  final double? lightning;

  /// Every category as sent, such as `{'TMP': '21'}`, including ones this
  /// class does not model.
  final Map<String, String> values;

  /// The compass point of [windDirection].
  KmaCompass? get compass =>
      windDirection == null ? null : KmaCompass.fromDegrees(windDirection!);

  @override
  String toString() => 'KmaForecastHour($date $hourText)';
}

/// Lowest and highest temperature of one day (`TMN`, `TMX`).
class KmaForecastDay {
  /// Creates a day.
  const KmaForecastDay({required this.date, this.low, this.high});

  /// `yyyyMMdd` in Korea Standard Time.
  final String date;

  /// `TMN`, in ℃. Only slots published at 02:00 carry today's low.
  final double? low;

  /// `TMX`, in ℃.
  final double? high;

  @override
  String toString() => 'KmaForecastDay($date, $low, $high)';
}

/// Rows of a KMA forecast or nowcast, grouped by time.
///
/// The services send one row per category and time, such as `TMP` at 15:00.
/// [KmaForecast.fromItems] groups them into [hours], reads codes and classes,
/// and drops the missing marker.
///
/// ```dart
/// final page = await client.get(endpoint, query: {...}, rows: 1000);
/// final forecast = KmaForecast.fromItems(page.items);
/// for (final hour in forecast.hours) {
///   print('${hour.hourText} ${hour.temperature}℃ ${hour.sky?.label}');
/// }
/// ```
class KmaForecast {
  /// Creates a forecast.
  const KmaForecast({required this.hours, this.days = const []});

  /// Groups the rows of `getVilageFcst`, `getUltraSrtFcst`, or
  /// `getUltraSrtNcst`.
  ///
  /// Rows of the village forecast's extended range (글피 for slots up to
  /// 14:00, 그글피 for 17:00 and later) read `PCP`, `SNO`, and `WSD` as
  /// qualitative codes. Nowcast rows (`obsrValue`, no `fcstDate`) are placed
  /// at their base time.
  factory KmaForecast.fromItems(Iterable<Map<String, Object?>> items) {
    final byTime = <String, _HourBuilder>{};
    final lows = <String, double>{};
    final highs = <String, double>{};

    for (final row in items) {
      final category = _text(row['category'])?.toUpperCase();
      final value = _text(row['fcstValue']) ?? _text(row['obsrValue']);
      final date = _text(row['fcstDate']) ?? _text(row['baseDate']);
      final hour = _text(row['fcstTime']) ?? _text(row['baseTime']);
      if (category == null || value == null || date == null || hour == null) {
        continue;
      }
      if (category == 'TMN' || category == 'TMX') {
        final degrees = _number(value);
        if (degrees != null) (category == 'TMN' ? lows : highs)[date] = degrees;
        continue;
      }
      final builder = byTime.putIfAbsent(
        '$date$hour',
        () => _HourBuilder(
          date,
          hour,
          extended: _isExtended(
            _text(row['baseDate']),
            _text(row['baseTime']),
            date,
          ),
        ),
      );
      builder.values[category] = value;
    }

    final hours = [for (final builder in byTime.values) builder.build()]
      ..sort((a, b) => a.time.compareTo(b.time));
    final dates = {...lows.keys, ...highs.keys}.toList()..sort();
    return KmaForecast(
      hours: hours,
      days: [
        for (final date in dates)
          KmaForecastDay(date: date, low: lows[date], high: highs[date]),
      ],
    );
  }

  /// Forecast times, earliest first.
  final List<KmaForecastHour> hours;

  /// Daily lows and highs, earliest first.
  final List<KmaForecastDay> days;

  /// The forecast time [instant] falls in: the latest one at or before it.
  /// Returns `null` before the first.
  KmaForecastHour? at(DateTime instant) {
    KmaForecastHour? found;
    for (final hour in hours) {
      if (hour.time.isAfter(instant)) break;
      found = hour;
    }
    return found;
  }

  /// Whether a forecast date is in the village forecast's extended range:
  /// three days after a slot up to 14:00, four after 17:00 and later.
  static bool _isExtended(String? baseDate, String? baseTime, String date) {
    if (baseDate == null || baseTime == null || baseTime.length < 2) {
      return false;
    }
    final base = _day(baseDate);
    final target = _day(date);
    final hour = int.tryParse(baseTime.substring(0, 2));
    if (base == null || target == null || hour == null) return false;
    final days = target.difference(base).inDays;
    return days >= (hour <= 14 ? 3 : 4);
  }

  static DateTime? _day(String date) {
    if (date.length != 8) return null;
    final y = int.tryParse(date.substring(0, 4));
    final m = int.tryParse(date.substring(4, 6));
    final d = int.tryParse(date.substring(6, 8));
    return y == null || m == null || d == null ? null : DateTime.utc(y, m, d);
  }
}

class _HourBuilder {
  _HourBuilder(this.date, this.hour, {required this.extended});

  final String date;
  final String hour;
  final bool extended;
  final values = <String, String>{};

  KmaForecastHour build() {
    final day = KmaForecast._day(date);
    final hh = int.tryParse(hour.padRight(4, '0').substring(0, 2)) ?? 0;
    final mm = int.tryParse(hour.padRight(4, '0').substring(2, 4)) ?? 0;
    // KST wall-clock time minus nine hours is the UTC instant.
    final time = (day ?? DateTime.utc(1970))
        .add(Duration(hours: hh, minutes: mm))
        .subtract(const Duration(hours: 9));

    KmaAmount? amount(String category, String unit) {
      final raw = values[category];
      if (raw == null) return null;
      try {
        final parsed = KmaAmount.parse(raw, unit: unit, qualitative: extended);
        return parsed.isMissing ? null : parsed;
      } on FormatException {
        return null;
      }
    }

    String? code(String category) {
      final raw = values[category];
      if (raw == null) return null;
      final number = double.tryParse(raw);
      return number != null && isKmaMissing(number) ? null : raw;
    }

    return KmaForecastHour(
      time: time,
      date: date,
      hourText: hour,
      isExtended: extended,
      temperature: _number(values['TMP'] ?? values['T1H']),
      sky: code('SKY') == null ? null : KmaSky.fromCode(code('SKY')!),
      precipitationType: code('PTY') == null
          ? null
          : KmaPrecipitation.fromCode(code('PTY')!),
      precipitationProbability: _number(values['POP'])?.round(),
      precipitation: amount('PCP', 'mm') ?? amount('RN1', 'mm'),
      snow: amount('SNO', 'cm'),
      humidity: _number(values['REH'])?.round(),
      windSpeed: amount('WSD', 'm/s'),
      windDirection: _number(values['VEC'])?.round(),
      windEastward: _number(values['UUU']),
      windNorthward: _number(values['VVV']),
      waveHeight: _number(values['WAV']),
      lightning: _number(values['LGT']),
      values: Map.unmodifiable(values),
    );
  }
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

/// A plain number, or `null` for text and the missing marker.
double? _number(String? value) {
  final number = value == null ? null : double.tryParse(value.trim());
  return number == null || isKmaMissing(number) ? null : number;
}

/// Which Korea Meteorological Administration forecast service a request is
/// for. Each one publishes on its own schedule.
enum KmaService {
  /// `getVilageFcst`, published eight times a day for the next three days.
  village,

  /// `getUltraSrtNcst`, the observation for the current hour.
  ultraShortNowcast,

  /// `getUltraSrtFcst`, the forecast for the next six hours.
  ultraShortForecast,
}

/// The `base_date` and `base_time` a KMA request needs.
///
/// Services reject a time they have not published yet, and each one becomes
/// available some minutes after its slot, so the newest usable slot is not
/// simply the current hour.
///
/// ```dart
/// final base = KmaBaseTime.latest(KmaService.village);
/// await client.get(endpoint, query: {
///   'base_date': base.date,
///   'base_time': base.time,
///   'nx': cell.nx,
///   'ny': cell.ny,
/// });
/// ```
class KmaBaseTime {
  /// Creates a base date and time.
  const KmaBaseTime(this.date, this.time);

  /// Newest slot the service has published, in Korea Standard Time.
  ///
  /// [now] defaults to the current time. It is an instant, converted to KST
  /// first: pass `DateTime.now()`, a UTC time, or a local time of the device.
  /// A `DateTime(...)` built from Korean wall-clock values on a device in
  /// another time zone names a different instant and gives a different slot.
  ///
  /// [delay] is how long after its slot a service is assumed to publish:
  /// ten minutes for the village forecast and the nowcast, 45 for the ultra
  /// short forecast, from the KMA guide. Pass a longer one to stay clear of
  /// the edge, where a service sometimes publishes a minute or two late.
  factory KmaBaseTime.latest(
    KmaService service, {
    DateTime? now,
    Duration? delay,
  }) {
    // KST is UTC+9 all year; Korea observes no daylight saving time.
    final kst = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));

    // Delays from the KMA guide (기상청41_단기예보 조회서비스 오픈API
    // 활용가이드, 2026-10): the village forecast and the nowcast are called
    // ten minutes after their slot, the ultra short forecast 45 minutes after
    // the hour.
    final minutes = delay?.inMinutes;
    return switch (service) {
      KmaService.village => _village(kst, delay: minutes ?? 10),
      KmaService.ultraShortNowcast => _hourly(kst, delay: minutes ?? 10, at: 0),
      KmaService.ultraShortForecast => _hourly(
        kst,
        delay: minutes ?? 45,
        at: 30,
      ),
    };
  }

  /// The slot published before this one: three hours earlier for the
  /// village forecast, one hour for the others.
  ///
  /// Use it when a service answers "no data" (`03`) for the newest slot,
  /// which happens when it publishes late.
  KmaBaseTime previous(KmaService service) {
    final slot = DateTime.utc(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(4, 6)),
      int.parse(date.substring(6, 8)),
      int.parse(time.substring(0, 2)),
      int.parse(time.substring(2, 4)),
    );
    final earlier = slot.subtract(
      Duration(hours: service == KmaService.village ? 3 : 1),
    );
    return KmaBaseTime(
      _date(earlier),
      '${_two(earlier.hour)}${_two(earlier.minute)}',
    );
  }

  /// `yyyyMMdd` in Korea Standard Time.
  final String date;

  /// `HHmm` in Korea Standard Time.
  final String time;

  /// The eight daily slots of the village forecast, published [delay]
  /// minutes after each slot.
  static KmaBaseTime _village(DateTime kst, {required int delay}) {
    // Step back by the delay, then take the slot that time falls in.
    final published = kst.subtract(Duration(minutes: delay));
    const slots = [2, 5, 8, 11, 14, 17, 20, 23];
    for (final hour in slots.reversed) {
      if (published.hour >= hour) {
        return KmaBaseTime(_date(published), '${_two(hour)}00');
      }
    }
    // Before the 02:00 slot is out, the newest one is yesterday's 23:00.
    return KmaBaseTime(
      _date(published.subtract(const Duration(days: 1))),
      '2300',
    );
  }

  /// Hourly slots at [at] minutes past the hour, published [delay] minutes
  /// after the hour.
  static KmaBaseTime _hourly(
    DateTime kst, {
    required int delay,
    required int at,
  }) {
    // Step back by the delay: the hour that time falls in is the newest one
    // published. Delays of an hour or more work the same way.
    final published = kst.subtract(Duration(minutes: delay));
    return KmaBaseTime(_date(published), '${_two(published.hour)}${_two(at)}');
  }

  static String _date(DateTime kst) =>
      '${kst.year}${_two(kst.month)}${_two(kst.day)}';

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  bool operator ==(Object other) =>
      other is KmaBaseTime && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => 'KmaBaseTime($date, $time)';
}

/// Sky condition, the `SKY` category.
enum KmaSky {
  /// `1`, 맑음.
  clear('1', '맑음'),

  /// `3`, 구름많음.
  partlyCloudy('3', '구름많음'),

  /// `4`, 흐림.
  cloudy('4', '흐림');

  const KmaSky(this.code, this.label);

  /// The value the API sends in `fcstValue`.
  final String code;

  /// Korean label used by KMA.
  final String label;

  /// Reads a `SKY` value, or returns `null` for an unknown code.
  static KmaSky? fromCode(String code) {
    for (final value in values) {
      if (value.code == code.trim()) return value;
    }
    return null;
  }
}

/// Precipitation form, the `PTY` category.
///
/// The village forecast uses `0` to `4`; the ultra short nowcast and forecast
/// use `0` to `7`, so all are listed here. [fromCode] reads either.
enum KmaPrecipitation {
  /// `0`, 없음.
  none('0', '없음'),

  /// `1`, 비.
  rain('1', '비'),

  /// `2`, 비/눈.
  rainOrSnow('2', '비/눈'),

  /// `3`, 눈.
  snow('3', '눈'),

  /// `4`, 소나기.
  shower('4', '소나기'),

  /// `5`, 빗방울.
  drizzle('5', '빗방울'),

  /// `6`, 빗방울눈날림.
  drizzleAndSnowFlurry('6', '빗방울눈날림'),

  /// `7`, 눈날림.
  snowFlurry('7', '눈날림');

  const KmaPrecipitation(this.code, this.label);

  /// The value the API sends in `fcstValue` or `obsrValue`.
  final String code;

  /// Korean label used by KMA.
  final String label;

  /// Whether any precipitation is falling.
  bool get isWet => this != none;

  /// Reads a `PTY` value, or returns `null` for an unknown code.
  static KmaPrecipitation? fromCode(String code) {
    for (final value in values) {
      if (value.code == code.trim()) return value;
    }
    return null;
  }
}

/// What a KMA category code means, such as `TMP` for temperature.
///
/// ```dart
/// final info = kmaCategory('TMP'); // (label: '1시간 기온', unit: '℃')
/// ```
({String label, String unit})? kmaCategory(String code) =>
    _categories[code.trim().toUpperCase()];

const _categories = <String, ({String label, String unit})>{
  'POP': (label: '강수확률', unit: '%'),
  'PTY': (label: '강수형태', unit: '코드'),
  'PCP': (label: '1시간 강수량', unit: 'mm'),
  'REH': (label: '습도', unit: '%'),
  'SNO': (label: '1시간 신적설', unit: 'cm'),
  'SKY': (label: '하늘상태', unit: '코드'),
  'TMP': (label: '1시간 기온', unit: '℃'),
  'TMN': (label: '일 최저기온', unit: '℃'),
  'TMX': (label: '일 최고기온', unit: '℃'),
  'UUU': (label: '풍속(동서성분)', unit: 'm/s'),
  'VVV': (label: '풍속(남북성분)', unit: 'm/s'),
  'WAV': (label: '파고', unit: 'M'),
  'VEC': (label: '풍향', unit: 'deg'),
  'WSD': (label: '풍속', unit: 'm/s'),
  'T1H': (label: '기온', unit: '℃'),
  'RN1': (label: '1시간 강수량', unit: 'mm'),
  'LGT': (label: '낙뢰', unit: 'kA'),
};

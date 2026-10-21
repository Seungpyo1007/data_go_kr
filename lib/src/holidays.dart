import 'client.dart';

/// What kind of day a [KoreanSpecialDay] is, the `dateKind` field.
enum KoreanDateKind {
  /// `01`, 국경일 and other public holidays, such as 광복절 or 설날.
  national('01', '국경일'),

  /// `02`, 기념일, such as 의병의 날.
  anniversary('02', '기념일'),

  /// `03`, one of the 24 solar terms (24절기), such as 청명.
  solarTerm('03', '24절기'),

  /// `04`, 잡절, such as 단오 or 한식.
  sundry('04', '잡절');

  const KoreanDateKind(this.code, this.label);

  /// The value the API sends.
  final String code;

  /// Korean name of the kind.
  final String label;

  /// Reads a `dateKind` value, or returns `null` for an unknown one.
  static KoreanDateKind? fromCode(String code) {
    for (final kind in values) {
      if (kind.code == code.trim()) return kind;
    }
    return null;
  }
}

/// One day from the Korea Astronomy and Space Science Institute's special
/// day service (한국천문연구원 특일 정보).
class KoreanSpecialDay {
  /// Creates a day.
  const KoreanSpecialDay({
    required this.date,
    required this.name,
    required this.isHoliday,
    this.kind,
    this.seq,
    this.time,
    this.sunLongitude,
    this.raw = const <String, Object?>{},
  });

  /// Reads one row of the service.
  factory KoreanSpecialDay.fromRow(Map<String, Object?> row) {
    final locdate = '${row['locdate'] ?? ''}'.trim();
    final date = _parseDate(locdate);
    if (date == null) {
      throw FormatException('Not a yyyyMMdd date', locdate);
    }
    String? text(String key) {
      final value = '${row[key] ?? ''}'.trim();
      return value.isEmpty ? null : value;
    }

    return KoreanSpecialDay(
      date: date,
      name: text('dateName') ?? '',
      isHoliday: text('isHoliday')?.toUpperCase() == 'Y',
      kind: KoreanDateKind.fromCode(text('dateKind') ?? ''),
      seq: int.tryParse(text('seq') ?? ''),
      time: text('kst'),
      sunLongitude: int.tryParse(text('sunLongitude') ?? ''),
      raw: Map.unmodifiable(row),
    );
  }

  /// The date, as a UTC midnight so it names the same calendar day in every
  /// time zone.
  final DateTime date;

  /// `dateName`, such as `광복절` or `대체공휴일`.
  final String name;

  /// `isHoliday`: whether public offices close.
  final bool isHoliday;

  /// `dateKind`.
  final KoreanDateKind? kind;

  /// `seq`, the order of days sharing a date.
  final int? seq;

  /// `kst`, `HHmm`: the moment a solar term starts. Only solar terms and
  /// sundry days carry it.
  final String? time;

  /// `sunLongitude`, in degrees: the sun's longitude at a solar term.
  final int? sunLongitude;

  /// The row as the service sent it.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      'KoreanSpecialDay(${date.toIso8601String().substring(0, 10)} $name)';
}

/// Public holidays, anniversaries, and solar terms from the special day
/// service (한국천문연구원 특일 정보, `SpcdeInfoService`).
///
/// Apply for "한국천문연구원_특일 정보" on data.go.kr; the client's service
/// key must be approved for it.
///
/// ```dart
/// final days = await KoreanHolidays(client).restDays(2026, month: 10);
/// ```
///
/// The service updates each year once the government publishes its
/// calendar, usually two years ahead; temporary holidays appear within a day
/// of being declared.
class KoreanHolidays {
  /// Wraps [client].
  KoreanHolidays(this.client);

  /// The client that sends the requests.
  final DataGoKrClient client;

  /// Base URL of the service.
  static const endpoint =
      'https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService';

  /// Days off (`getRestDeInfo`): public holidays and substitute holidays,
  /// with [KoreanSpecialDay.isHoliday] true. 제헌절 is not one.
  Future<List<KoreanSpecialDay>> restDays(int year, {int? month}) =>
      _days('getRestDeInfo', year, month);

  /// National days (`getHoliDeInfo`), including 제헌절 with
  /// [KoreanSpecialDay.isHoliday] false.
  Future<List<KoreanSpecialDay>> nationalDays(int year, {int? month}) =>
      _days('getHoliDeInfo', year, month);

  /// Anniversaries (`getAnniversaryInfo`).
  Future<List<KoreanSpecialDay>> anniversaries(int year, {int? month}) =>
      _days('getAnniversaryInfo', year, month);

  /// The 24 solar terms (`get24DivisionsInfo`).
  Future<List<KoreanSpecialDay>> solarTerms(int year, {int? month}) =>
      _days('get24DivisionsInfo', year, month);

  /// Sundry days such as 단오 and 한식 (`getSundryDayInfo`).
  Future<List<KoreanSpecialDay>> sundryDays(int year, {int? month}) =>
      _days('getSundryDayInfo', year, month);

  /// Whether [date] is a day off by [restDays]. Weekends are not included:
  /// check `date.weekday` for those.
  ///
  /// [date]'s year, month, and day are used as they are.
  Future<bool> isRestDay(DateTime date) async {
    final days = await restDays(date.year, month: date.month);
    return days.any(
      (day) =>
          day.isHoliday &&
          day.date.year == date.year &&
          day.date.month == date.month &&
          day.date.day == date.day,
    );
  }

  Future<List<KoreanSpecialDay>> _days(
    String operation,
    int year,
    int? month,
  ) async {
    if (year < 1000 || year > 9999) {
      throw ArgumentError.value(year, 'year', 'Must have four digits');
    }
    if (month != null && (month < 1 || month > 12)) {
      throw ArgumentError.value(month, 'month', 'Must be 1 to 12');
    }
    final days = <KoreanSpecialDay>[];
    await for (final row in client.paginate(
      '$endpoint/$operation',
      query: {
        'solYear': '$year',
        if (month != null) 'solMonth': month.toString().padLeft(2, '0'),
        // This service takes _type, not dataType.
        '_type': 'json',
      },
      rows: 100,
    )) {
      days.add(KoreanSpecialDay.fromRow(row));
    }
    days.sort((a, b) => a.date.compareTo(b.date));
    return days;
  }
}

DateTime? _parseDate(String text) {
  if (!RegExp(r'^\d{8}$').hasMatch(text)) return null;
  final y = int.parse(text.substring(0, 4));
  final m = int.parse(text.substring(4, 6));
  final d = int.parse(text.substring(6, 8));
  final date = DateTime.utc(y, m, d);
  return date.month == m && date.day == d ? date : null;
}

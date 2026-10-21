import 'client.dart';

/// A taxpayer's state, the `b_stt_cd` field.
enum BusinessState {
  /// `01`, 계속사업자: in business.
  active('01', '계속사업자'),

  /// `02`, 휴업자: suspended.
  suspended('02', '휴업자'),

  /// `03`, 폐업자: closed.
  closed('03', '폐업자');

  const BusinessState(this.code, this.label);

  /// The value the API sends.
  final String code;

  /// Korean label used by the National Tax Service.
  final String label;

  /// Reads a `b_stt_cd` value, or returns `null` for an empty or unknown one.
  static BusinessState? fromCode(String? code) {
    for (final state in values) {
      if (state.code == code?.trim()) return state;
    }
    return null;
  }
}

/// A VAT taxation type, the `tax_type_cd` and `rbf_tax_type_cd` fields.
enum BusinessTaxType {
  /// `01`, 부가가치세 일반과세자.
  general('01', '부가가치세 일반과세자'),

  /// `02`, 부가가치세 간이과세자.
  simplified('02', '부가가치세 간이과세자'),

  /// `03`, 부가가치세 과세특례자.
  special('03', '부가가치세 과세특례자'),

  /// `04`, 부가가치세 면세사업자.
  exempt('04', '부가가치세 면세사업자'),

  /// `05`, a non-profit corporation without profit-making business, or an
  /// organization or state agency with a unique number.
  nonProfit('05', '수익사업을 영위하지 않는 비영리법인이거나 고유번호가 부여된 단체,국가기관 등'),

  /// `06`, 고유번호가 부여된 단체.
  organization('06', '고유번호가 부여된 단체'),

  /// `07`, 부가가치세 간이과세자 that issues tax invoices.
  simplifiedInvoicing('07', '부가가치세 간이과세자(세금계산서 발급사업자)');

  const BusinessTaxType(this.code, this.label);

  /// The value the API sends.
  final String code;

  /// Korean label used by the National Tax Service.
  final String label;

  /// Reads a code, or returns `null` for an empty, unknown, or `99`
  /// (해당없음) one.
  static BusinessTaxType? fromCode(String? code) {
    for (final type in values) {
      if (type.code == code?.trim()) return type;
    }
    return null;
  }
}

/// The National Tax Service's answer for one business registration number.
class BusinessStatus {
  /// Creates a status.
  const BusinessStatus({
    required this.number,
    required this.isRegistered,
    this.state,
    this.stateLabel,
    this.taxType,
    this.taxTypeLabel,
    this.closedOn,
    this.closedForUnitTaxation,
    this.taxTypeChangedOn,
    this.invoiceAppliedOn,
    this.previousTaxType,
    this.previousTaxTypeLabel,
    this.raw = const <String, Object?>{},
  });

  /// Reads one entry of the `data` list.
  factory BusinessStatus.fromRow(Map<String, Object?> row) {
    String? text(String key) {
      final value = '${row[key] ?? ''}'.trim();
      return value.isEmpty ? null : value;
    }

    final state = BusinessState.fromCode(text('b_stt_cd'));
    final taxType = BusinessTaxType.fromCode(text('tax_type_cd'));
    return BusinessStatus(
      number: text('b_no') ?? '',
      // An unknown number comes back with empty codes and a tax_type of
      // "국세청에 등록되지 않은 사업자등록번호입니다".
      isRegistered: state != null || taxType != null,
      state: state,
      stateLabel: text('b_stt'),
      taxType: taxType,
      taxTypeLabel: text('tax_type'),
      closedOn: _date(text('end_dt')),
      closedForUnitTaxation: switch (text('utcc_yn')?.toUpperCase()) {
        'Y' => true,
        'N' => false,
        _ => null,
      },
      taxTypeChangedOn: _date(text('tax_type_change_dt')),
      invoiceAppliedOn: _date(text('invoice_apply_dt')),
      previousTaxType: BusinessTaxType.fromCode(text('rbf_tax_type_cd')),
      previousTaxTypeLabel: text('rbf_tax_type'),
      raw: Map.unmodifiable(row),
    );
  }

  /// `b_no`, ten digits.
  final String number;

  /// Whether the National Tax Service knows the number.
  final bool isRegistered;

  /// `b_stt_cd`.
  final BusinessState? state;

  /// `b_stt`, as sent.
  final String? stateLabel;

  /// `tax_type_cd`.
  final BusinessTaxType? taxType;

  /// `tax_type`, as sent. For an unknown number it says so in Korean.
  final String? taxTypeLabel;

  /// `end_dt`, the closing date, as a UTC midnight.
  final DateTime? closedOn;

  /// `utcc_yn`: whether the business closed to switch to unit taxation
  /// (단위과세전환폐업).
  final bool? closedForUnitTaxation;

  /// `tax_type_change_dt`, the latest change of taxation type.
  final DateTime? taxTypeChangedOn;

  /// `invoice_apply_dt`, since when it issues tax invoices.
  final DateTime? invoiceAppliedOn;

  /// `rbf_tax_type_cd`, the previous taxation type; `null` for `99`
  /// (해당없음).
  final BusinessTaxType? previousTaxType;

  /// `rbf_tax_type`, as sent.
  final String? previousTaxTypeLabel;

  /// The entry as the service sent it.
  final Map<String, Object?> raw;

  @override
  String toString() =>
      'BusinessStatus($number, ${state?.label ?? taxTypeLabel})';
}

/// The National Tax Service's business status lookup (국세청 사업자등록정보
/// 상태조회, `nts-businessman/v1/status` on `api.odcloud.kr`).
///
/// Apply for "국세청_사업자등록정보 진위확인 및 상태조회 서비스" on
/// data.go.kr; the client's service key must be approved for it.
///
/// ```dart
/// final [status] = await BusinessStatusService(client).check(['1248100998']);
/// print(status.state?.label); // 계속사업자
/// ```
class BusinessStatusService {
  /// Wraps [client].
  BusinessStatusService(this.client);

  /// The client that sends the requests.
  final DataGoKrClient client;

  /// URL of the status operation.
  static const endpoint =
      'https://api.odcloud.kr/api/nts-businessman/v1/status';

  /// Numbers one request may hold.
  static const batchSize = 100;

  /// Looks up [numbers], in the same order.
  ///
  /// Hyphens and spaces are removed, so `124-81-00998` works. More than
  /// [batchSize] numbers are sent in several requests. Throws an
  /// [ArgumentError] for a number that is not ten digits, before anything is
  /// sent.
  Future<List<BusinessStatus>> check(Iterable<String> numbers) async {
    final cleaned = [for (final number in numbers) normalize(number)];
    for (final number in cleaned) {
      if (!RegExp(r'^\d{10}$').hasMatch(number)) {
        throw ArgumentError.value(number, 'numbers', 'Must be ten digits');
      }
    }
    final byNumber = <String, BusinessStatus>{};
    for (var start = 0; start < cleaned.length; start += batchSize) {
      final batch = cleaned.sublist(
        start,
        (start + batchSize).clamp(0, cleaned.length),
      );
      final response = await client.post(
        endpoint,
        json: {'b_no': batch},
        // A lookup changes nothing, so it is safe to send again.
        idempotent: true,
      );
      for (final row in response.items) {
        final status = BusinessStatus.fromRow(row);
        byNumber[status.number] = status;
      }
    }
    return [
      for (final number in cleaned)
        byNumber[number] ?? BusinessStatus(number: number, isRegistered: false),
    ];
  }

  /// [number] without hyphens and spaces.
  static String normalize(String number) =>
      number.replaceAll(RegExp(r'[\s-]'), '');

  /// Whether [number] passes the business registration number checksum.
  ///
  /// A failing number cannot be registered; a passing one still has to be
  /// looked up with [check].
  static bool isValidNumber(String number) {
    final digits = normalize(number);
    if (!RegExp(r'^\d{10}$').hasMatch(digits)) return false;
    const weights = [1, 3, 7, 1, 3, 7, 1, 3, 5];
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(digits[i]) * weights[i];
    }
    sum += int.parse(digits[8]) * 5 ~/ 10;
    return (10 - sum % 10) % 10 == int.parse(digits[9]);
  }
}

DateTime? _date(String? text) {
  if (text == null || !RegExp(r'^\d{8}$').hasMatch(text)) return null;
  final y = int.parse(text.substring(0, 4));
  final m = int.parse(text.substring(4, 6));
  final d = int.parse(text.substring(6, 8));
  final date = DateTime.utc(y, m, d);
  return date.month == m && date.day == d ? date : null;
}

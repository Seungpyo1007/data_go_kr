/// One page of results from a data.go.kr open API.
class DataGoKrResponse {
  /// Creates a page of results.
  const DataGoKrResponse({
    this.items = const <Map<String, Object?>>[],
    this.totalCount,
    this.pageNo,
    this.numOfRows,
    this.resultCode,
    this.resultMsg,
    this.body = '',
  });

  /// Rows of the page. Each row maps field names to values; XML values are
  /// always strings, JSON values keep their original type.
  final List<Map<String, Object?>> items;

  /// Total number of rows the service reports, when it reports one.
  final int? totalCount;

  /// Page number this response belongs to.
  final int? pageNo;

  /// Rows per page the service used.
  final int? numOfRows;

  /// Service result code, such as `00` for a normal response.
  final String? resultCode;

  /// Service result message.
  final String? resultMsg;

  /// The raw response body, for fields this class does not model.
  final String body;

  /// Whether the page has no rows.
  bool get isEmpty => items.isEmpty;
}

/// A failed call to a data.go.kr open API.
class DataGoKrException implements Exception {
  /// Creates a failure.
  const DataGoKrException(
    this.message, {
    required this.code,
    this.reasonCode,
    this.statusCode,
  });

  /// Safe error description, including the portal's own message when it sends
  /// one. The service key is never included.
  final String message;

  /// Stable error code: `unauthorized_key`, `rate_limit`, `invalid_parameter`,
  /// `unknown_service`, `service_error`, `http_error`, `timeout`, or
  /// `invalid_response`.
  final String code;

  /// The portal's own reason code, such as `30`, when it sends one.
  final String? reasonCode;

  /// HTTP status code, when the server answered.
  final int? statusCode;

  @override
  String toString() => message;
}

/// Maps a portal reason code to a stable [DataGoKrException.code].
///
/// The portal sends these as `returnReasonCode` in its error envelopes and as
/// `resultCode` in normal envelopes.
///
/// Portal codes: `20`–`33` key problems, `22` quota, `10`/`11` parameters,
/// `12` no such service, `05` the service timed out, `04` an HTTP error
/// between the gateway and the service. `api.odcloud.kr` sends negative
/// codes: `-3` no such service, `-4` and `-401` a missing or unknown key; its
/// National Tax Service lookups send a `status_code` such as
/// `TOO_LARGE_REQUEST` instead.
String errorCodeFor(String? reasonCode) => switch (reasonCode) {
  '20' ||
  '21' ||
  '30' ||
  '31' ||
  '32' ||
  '33' ||
  '-4' ||
  '-401' => 'unauthorized_key',
  '22' => 'rate_limit',
  '10' || '11' => 'invalid_parameter',
  '12' || '-3' => 'unknown_service',
  'BAD_JSON_REQUEST' ||
  'REQUEST_DATA_MALFORMED' ||
  'TOO_LARGE_REQUEST' => 'invalid_parameter',
  '05' || '5' => 'timeout',
  '04' || '4' => 'http_error',
  _ => 'service_error',
};

/// Maps a failing HTTP status to a [DataGoKrException.code], for answers
/// whose body says nothing usable. Returns `null` for success statuses.
String? errorCodeForStatus(int? statusCode) => switch (statusCode) {
  null || < 300 => null,
  401 || 403 => 'unauthorized_key',
  429 => 'rate_limit',
  _ => 'http_error',
};

/// Whether a code means "the query matched nothing", which this package
/// reports as an empty page instead of an error.
bool isNoData(String? code) => code == '03' || code == '3';

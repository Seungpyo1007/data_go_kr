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
String errorCodeFor(String? reasonCode) => switch (reasonCode) {
  '20' || '30' || '31' || '32' || '33' || '-4' => 'unauthorized_key',
  '22' => 'rate_limit',
  '10' || '11' => 'invalid_parameter',
  '12' => 'unknown_service',
  _ => 'service_error',
};

/// Whether a code means "the query matched nothing", which this package
/// reports as an empty page instead of an error.
bool isNoData(String? code) => code == '03' || code == '3';

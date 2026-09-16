import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'parse.dart';
import 'response.dart';

/// Calls open APIs published on the Korean public data portal.
///
/// The client adds the service key, asks for JSON, and parses both JSON and
/// XML answers, so any service on `apis.data.go.kr` or `api.odcloud.kr` can be
/// called through one client.
class DataGoKrClient {
  /// Creates a client for one service key.
  ///
  /// Pass the **decoded** key from data.go.kr; it is percent-encoded for every
  /// request. A key that is already encoded is used as it is.
  DataGoKrClient({
    required this.serviceKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.numOfRows = 100,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Service key issued by data.go.kr.
  final String serviceKey;

  /// Time limit for each request.
  final Duration timeout;

  /// Default number of rows per page.
  final int numOfRows;

  /// Closes the HTTP client this instance created. An injected client is left
  /// open for its owner.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Requests one page from [endpoint].
  ///
  /// [query] holds the service's own parameters; entries with a `null` value
  /// are dropped. `pageNo`, `numOfRows`, and `dataType` are added unless
  /// [query] already sets them. Throws a [DataGoKrException] when the call
  /// fails.
  Future<DataGoKrResponse> get(
    String endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    int pageNo = 1,
    int? rows,
  }) async {
    final uri = _uriFor(endpoint, query, pageNo, rows ?? numOfRows);
    final (body, statusCode) = await _send(uri);
    return parseBody(body, statusCode: statusCode);
  }

  /// Requests page after page and yields every row.
  ///
  /// Stops at the reported `totalCount`, at the first empty page, or after
  /// [maxPages] pages.
  Stream<Map<String, Object?>> paginate(
    String endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    int? rows,
    int maxPages = 100,
  }) async* {
    final size = rows ?? numOfRows;
    var seen = 0;
    for (var page = 1; page <= maxPages; page++) {
      final response = await get(
        endpoint,
        query: query,
        pageNo: page,
        rows: size,
      );
      if (response.items.isEmpty) return;
      yield* Stream<Map<String, Object?>>.fromIterable(response.items);
      seen += response.items.length;
      final total = response.totalCount;
      if (total != null && seen >= total) return;
    }
  }

  Uri _uriFor(
    String endpoint,
    Map<String, Object?> query,
    int pageNo,
    int rows,
  ) {
    final base = Uri.parse(endpoint);
    final pairs = <String>[];
    void add(String key, String value) => pairs.add(
      '${Uri.encodeQueryComponent(key)}=${Uri.encodeComponent(value)}',
    );

    base.queryParameters.forEach(add);
    for (final entry in query.entries) {
      if (entry.value != null) add(entry.key, '${entry.value}');
    }
    if (!query.containsKey('pageNo')) add('pageNo', '$pageNo');
    if (!query.containsKey('numOfRows')) add('numOfRows', '$rows');
    if (!query.containsKey('dataType') &&
        !query.containsKey('type') &&
        !query.containsKey('_type')) {
      add('dataType', 'JSON');
    }
    // Added last and encoded separately: an already encoded key must not be
    // encoded twice.
    pairs.add('serviceKey=${encodeServiceKey(serviceKey)}');
    return base.replace(query: pairs.join('&'));
  }

  Future<(String, int)> _send(Uri uri) async {
    Future<http.Response> get() => _client
        .get(uri, headers: const {'accept': 'application/json, text/xml'})
        .timeout(timeout);

    final http.Response response;
    try {
      // A server can close a reused keep-alive connection before answering.
      // GET is idempotent: retry once on a fresh connection.
      response = await get().onError<http.ClientException>((_, _) => get());
    } on TimeoutException {
      throw DataGoKrException(
        'The request to ${uri.host} timed out.',
        code: 'timeout',
      );
    } on http.ClientException catch (error) {
      throw DataGoKrException(
        'The request to ${uri.host} failed: ${error.message}',
        code: 'http_error',
      );
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    // Services report errors with 200, 401, or 403 and describe them in the
    // body, so the body is parsed first and the status is only a fallback.
    if (body.trim().isEmpty) {
      throw DataGoKrException(
        '${uri.host} returned an empty body (HTTP ${response.statusCode}).',
        code: response.statusCode == 200 ? 'invalid_response' : 'http_error',
        statusCode: response.statusCode,
      );
    }
    return (body, response.statusCode);
  }
}

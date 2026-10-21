import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'parse.dart';
import 'response.dart';
import 'retry.dart';

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
    this.retry = const RetryPolicy(),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Service key issued by data.go.kr.
  final String serviceKey;

  /// Time limit for each attempt. A request still running when it passes is
  /// aborted, not only abandoned, when the HTTP client supports aborting.
  final Duration timeout;

  /// When failed requests are tried again. Retries apply to GET requests and
  /// to POST requests marked `idempotent`.
  final RetryPolicy retry;

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
  /// [query] already sets them; `api.odcloud.kr` gets `page` and `perPage`
  /// instead. [query] must not contain `serviceKey`. Throws a
  /// [DataGoKrException] when the call fails.
  Future<DataGoKrResponse> get(
    String endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    int pageNo = 1,
    int? rows,
  }) {
    final uri = _uriFor(endpoint, query, pageNo, rows ?? numOfRows);
    return _withRetries(() => _call('GET', uri), retries: true);
  }

  /// Sends [json] as a JSON body to [endpoint], for services that take POST
  /// requests such as the National Tax Service business status lookup on
  /// `api.odcloud.kr`.
  ///
  /// [query] is added to the URL like for [get], without paging parameters or
  /// `dataType`. POST requests are retried only when [idempotent] is true:
  /// set it for lookups that change nothing on the server. Throws a
  /// [DataGoKrException] when the call fails.
  Future<DataGoKrResponse> post(
    String endpoint, {
    required Map<String, Object?> json,
    Map<String, Object?> query = const <String, Object?>{},
    bool idempotent = false,
  }) {
    final uri = _uriFor(endpoint, query, null, null);
    return _withRetries(
      () => _call('POST', uri, body: jsonEncode(json)),
      retries: idempotent,
    );
  }

  /// Requests page after page and yields every row.
  ///
  /// Stops at the reported `totalCount`, at the first empty page, or after
  /// [maxPages] pages. Paging parameters in [query] are replaced by the page
  /// being read; a `numOfRows` or `perPage` there is used as [rows].
  Stream<Map<String, Object?>> paginate(
    String endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    int? rows,
    int maxPages = 100,
  }) async* {
    final names = _pagingNames(Uri.parse(endpoint));
    final size =
        rows ?? int.tryParse('${query[names.rows] ?? ''}') ?? numOfRows;
    final pageQuery = {...query}
      ..remove(names.page)
      ..remove(names.rows);
    var seen = 0;
    for (var page = 1; page <= maxPages; page++) {
      final response = await get(
        endpoint,
        query: pageQuery,
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

  /// The request URL. [pageNo] and [rows] are null for POST requests, which
  /// get neither paging parameters nor `dataType`.
  Uri _uriFor(
    String endpoint,
    Map<String, Object?> query,
    int? pageNo,
    int? rows,
  ) {
    final base = Uri.parse(endpoint);
    bool isKey(String name) => name.toLowerCase() == 'servicekey';
    if (base.queryParameters.keys.any(isKey) || query.keys.any(isKey)) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Pass the service key to DataGoKrClient, not in the endpoint or query',
      );
    }

    final pairs = <String>[];
    void add(String key, String value) => pairs.add(
      '${Uri.encodeQueryComponent(key)}=${Uri.encodeComponent(value)}',
    );
    bool sets(String key) => query[key] != null;

    base.queryParameters.forEach(add);
    for (final entry in query.entries) {
      if (entry.value != null) add(entry.key, '${entry.value}');
    }
    final names = _pagingNames(base);
    if (pageNo != null && !sets(names.page)) add(names.page, '$pageNo');
    if (rows != null && !sets(names.rows)) add(names.rows, '$rows');
    // api.odcloud.kr always answers in JSON.
    if (pageNo != null &&
        !names.odcloud &&
        !const ['dataType', 'type', '_type', 'returnType'].any(sets)) {
      add('dataType', 'JSON');
    }
    // Added last and encoded separately: an already encoded key must not be
    // encoded twice.
    pairs.add('serviceKey=${encodeServiceKey(serviceKey)}');
    return base.replace(query: pairs.join('&'));
  }

  /// Paging parameter names: `api.odcloud.kr` uses `page` and `perPage`,
  /// every other host `pageNo` and `numOfRows`.
  static ({String page, String rows, bool odcloud}) _pagingNames(Uri uri) =>
      uri.host == 'api.odcloud.kr'
      ? (page: 'page', rows: 'perPage', odcloud: true)
      : (page: 'pageNo', rows: 'numOfRows', odcloud: false);

  /// Runs [attempt], trying again as [retry] allows when [retries] is true.
  Future<DataGoKrResponse> _withRetries(
    Future<DataGoKrResponse> Function() attempt, {
    required bool retries,
  }) async {
    for (var count = 0; ; count++) {
      try {
        return await attempt();
      } on DataGoKrException catch (error) {
        if (!retries ||
            count >= retry.maxRetries ||
            !retry.shouldRetry(error)) {
          rethrow;
        }
        await retry.wait(count);
      }
    }
  }

  Future<DataGoKrResponse> _call(String method, Uri uri, {String? body}) async {
    final (text, statusCode) = await _send(method, uri, body: body);
    return parseBody(text, statusCode: statusCode);
  }

  Future<(String, int)> _send(String method, Uri uri, {String? body}) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..headers['accept'] = 'application/json, text/xml';
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json; charset=utf-8'
        ..body = body;
    }

    final http.Response response;
    try {
      // The trigger aborts the request in clients that support it; the race
      // ends the wait in clients that don't.
      response = await Future.any([
        _client.send(request).then(http.Response.fromStream),
        abort.future.then<http.Response>((_) => throw TimeoutException(null)),
      ]);
    } on TimeoutException {
      throw _timedOut(uri);
    } on http.RequestAbortedException {
      throw _timedOut(uri);
    } on http.ClientException catch (error) {
      throw DataGoKrException(
        'The request to ${uri.host} failed: ${error.message}',
        code: 'http_error',
      );
    } on DataGoKrException {
      rethrow;
    } on Exception catch (error) {
      // TLS failures such as HandshakeException are not ClientExceptions.
      // Only the type is reported: other exceptions may carry the URL, and
      // with it the key.
      throw DataGoKrException(
        'The request to ${uri.host} failed (${error.runtimeType}).',
        code: 'http_error',
      );
    } finally {
      timer.cancel();
    }

    final text = _decode(response);
    // Services report errors with 200, 401, or 403 and describe them in the
    // body, so the body is parsed first and the status is only a fallback.
    if (text.trim().isEmpty) {
      throw DataGoKrException(
        '${uri.host} returned an empty body (HTTP ${response.statusCode}).',
        code: response.statusCode == 200
            ? 'invalid_response'
            : errorCodeForStatus(response.statusCode) ?? 'http_error',
        statusCode: response.statusCode,
      );
    }
    return (text, response.statusCode);
  }

  static DataGoKrException _timedOut(Uri uri) => DataGoKrException(
    'The request to ${uri.host} timed out.',
    code: 'timeout',
  );

  /// Decodes the body in the `charset` the server declares, UTF-8 when it
  /// declares none or one `dart:convert` lacks (such as EUC-KR).
  static String _decode(http.Response response) {
    final type = response.headers['content-type'] ?? '';
    final charset = RegExp(
      r'charset=\s*"?([^";\s]+)',
      caseSensitive: false,
    ).firstMatch(type)?.group(1);
    final encoding = charset == null ? null : Encoding.getByName(charset);
    if (encoding != null && encoding != utf8) {
      try {
        return encoding.decode(response.bodyBytes);
      } on FormatException {
        // A wrong declaration; fall back to UTF-8.
      }
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

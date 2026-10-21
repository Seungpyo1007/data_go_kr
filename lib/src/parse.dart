import 'dart:convert';

import 'package:xml/xml.dart';

import 'response.dart';

/// Percent-encodes a decoded service key.
///
/// Decoded keys contain `+`, `/`, and `=`, which change meaning inside a query
/// string and are the usual cause of `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`. A
/// key that is already percent-encoded is passed through unchanged. Spaces and
/// line breaks around the key, common when it is read from a file or an
/// environment variable, are removed.
String encodeServiceKey(String key) {
  final trimmed = key.trim();
  return RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(trimmed)
      ? trimmed
      : Uri.encodeComponent(trimmed);
}

/// Parses a response body in either JSON or XML.
///
/// Throws a [DataGoKrException] when the service reports an error.
DataGoKrResponse parseBody(String body, {int? statusCode}) {
  final text = body.trimLeft();
  if (text.startsWith('<?xml') || text.startsWith('<response')) {
    return _parseXml(text, body, statusCode);
  }
  if (text.startsWith('{') || text.startsWith('[')) {
    return _parseJson(text, body, statusCode);
  }
  if (text.startsWith('<')) return _parseXml(text, body, statusCode);
  throw _unreadable('neither JSON nor XML', statusCode);
}

/// A body this package cannot read. A failing HTTP status, when there is one,
/// says more than the body: a gateway's plain `Unauthorized` is still a key
/// problem.
DataGoKrException _unreadable(String what, int? statusCode) =>
    DataGoKrException(
      'The service returned $what'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
      code: errorCodeForStatus(statusCode) ?? 'invalid_response',
      statusCode: statusCode,
    );

DataGoKrResponse _parseXml(String text, String body, int? statusCode) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException {
    throw _unreadable('malformed XML', statusCode);
  }
  final root = document.rootElement;

  // Authentication and quota failures use their own envelope.
  if (root.name.local == 'OpenAPI_ServiceResponse') {
    _throwPortalError(
      _xmlText(root, 'returnReasonCode'),
      _portalMessage(_xmlText(root, 'errMsg'), _xmlText(root, 'returnAuthMsg')),
      statusCode,
    );
  }
  if (root.name.local.toLowerCase() == 'html') {
    throw _unreadable('an HTML page', statusCode);
  }

  final resultCode = _xmlText(root, 'resultCode');
  final resultMsg = _xmlText(root, 'resultMsg');
  if (isNoData(resultCode)) {
    return DataGoKrResponse(
      resultCode: resultCode,
      resultMsg: resultMsg,
      body: body,
    );
  }
  if (resultCode != null && !_isOk(resultCode)) {
    _throwPortalError(resultCode, resultMsg, statusCode);
  }

  return DataGoKrResponse(
    items: [for (final item in _xmlRows(root)) _xmlItem(item)],
    totalCount: _toInt(_xmlText(root, 'totalCount')),
    pageNo: _toInt(_xmlText(root, 'pageNo')),
    numOfRows: _toInt(_xmlText(root, 'numOfRows')),
    resultCode: resultCode,
    resultMsg: resultMsg,
    body: body,
  );
}

DataGoKrResponse _parseJson(String text, String body, int? statusCode) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw _unreadable('malformed JSON', statusCode);
  }
  if (json is! Map<String, Object?>) {
    throw _unreadable('a JSON value that is not an object', statusCode);
  }

  // Authentication and quota failures use their own envelope.
  final envelope = json['OpenAPI_ServiceResponse'];
  if (envelope is Map) {
    final header = envelope['cmmMsgHeader'];
    final fields = header is Map ? header : envelope;
    _throwPortalError(
      _string(fields['returnReasonCode']),
      _portalMessage(
        _string(fields['errMsg']),
        _string(fields['returnAuthMsg']),
      ),
      statusCode,
    );
  }

  // api.odcloud.kr reports errors as {"code": -4, "msg": "..."}.
  if (json['code'] is num && json['msg'] is String) {
    _throwPortalError(_string(json['code']), json['msg'] as String, statusCode);
  }

  // Some api.odcloud.kr services, such as the National Tax Service lookups,
  // answer {"status_code": "OK", "data": [...]} and fail with another
  // status_code, such as TOO_LARGE_REQUEST.
  final status = json['status_code'];
  if (status is String && status.toUpperCase() != 'OK') {
    _throwPortalError(status, null, statusCode);
  }

  // api.odcloud.kr answers normally as {"data": [...], "totalCount": 41, ...}.
  final data = json['data'];
  if (data is List) {
    return DataGoKrResponse(
      items: [...data.whereType<Map>().map(_jsonItem)],
      totalCount: _toInt(json['totalCount']),
      pageNo: _toInt(json['page']),
      numOfRows: _toInt(json['perPage']),
      body: body,
    );
  }

  // Most services wrap header and body in "response"; some, such as several
  // food and drug services, send them at the top level.
  final response =
      json['response'] ??
      (json['header'] is Map || json['body'] is Map ? json : null);
  if (response is! Map) {
    throw _unreadable('JSON without a response envelope', statusCode);
  }
  final header = response['header'];
  final resultCode = header is Map ? _string(header['resultCode']) : null;
  final resultMsg = header is Map ? _string(header['resultMsg']) : null;
  if (isNoData(resultCode)) {
    return DataGoKrResponse(
      resultCode: resultCode,
      resultMsg: resultMsg,
      body: body,
    );
  }
  if (resultCode != null && !_isOk(resultCode)) {
    _throwPortalError(resultCode, resultMsg, statusCode);
  }

  final responseBody = response['body'];
  if (responseBody is! Map) {
    return DataGoKrResponse(
      resultCode: resultCode,
      resultMsg: resultMsg,
      body: body,
    );
  }
  return DataGoKrResponse(
    items: _jsonItems(responseBody['items']),
    totalCount: _toInt(responseBody['totalCount']),
    pageNo: _toInt(responseBody['pageNo']),
    numOfRows: _toInt(responseBody['numOfRows']),
    resultCode: resultCode,
    resultMsg: resultMsg,
    body: body,
  );
}

/// Normalizes `items`, which is a list for several rows, an object for one row,
/// and an empty string or null when the query matched nothing.
List<Map<String, Object?>> _jsonItems(Object? items) => switch (items) {
  final List list => [...list.whereType<Map>().map(_jsonItem)],
  final Map map when map['item'] != null => _jsonItems(map['item']),
  final Map map when map.isNotEmpty => [_jsonItem(map)],
  _ => const <Map<String, Object?>>[],
};

Map<String, Object?> _jsonItem(Map<Object?, Object?> item) => <String, Object?>{
  for (final entry in item.entries) '${entry.key}': entry.value,
};

/// The `<item>` rows of a page: the children of `<items>`, so an element
/// named `item` inside a row is not mistaken for another row.
Iterable<XmlElement> _xmlRows(XmlElement root) {
  final items = _outsideRows(root, 'items').firstOrNull;
  return items == null
      ? _outsideRows(root, 'item')
      : items.childElements.where((element) => element.name.local == 'item');
}

Map<String, Object?> _xmlItem(XmlElement item) => <String, Object?>{
  for (final field in item.childElements)
    field.name.local: field.innerText.trim(),
};

/// The message of a portal error envelope. Current gateways put the reason
/// in `errMsg` and a Korean description in `returnAuthMsg`; older ones put a
/// bare `SERVICE ERROR` in `errMsg` and the reason in `returnAuthMsg`. The
/// specific one comes first, the other follows in parentheses.
String? _portalMessage(String? errMsg, String? returnAuthMsg) {
  final generic = errMsg == null || errMsg.toUpperCase() == 'SERVICE ERROR';
  final primary = generic ? returnAuthMsg ?? errMsg : errMsg;
  final secondary = generic ? errMsg : returnAuthMsg;
  if (primary == null) return secondary;
  return secondary == null || secondary == primary
      ? primary
      : '$primary ($secondary)';
}

Never _throwPortalError(String? reasonCode, String? message, int? statusCode) {
  final reason = (reasonCode ?? '').trim();
  final text = (message ?? '').trim();
  throw DataGoKrException(
    text.isEmpty
        ? 'The service rejected the request'
              '${reason.isEmpty ? '' : ' (code $reason)'}.'
        : text,
    code: errorCodeFor(reason.isEmpty ? null : reason),
    reasonCode: reason.isEmpty ? null : reason,
    statusCode: statusCode,
  );
}

bool _isOk(String resultCode) {
  final code = resultCode.trim();
  return code.isEmpty || code == '00' || code == '0';
}

String? _string(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

/// Text of the first [name] element that is not inside a row, so a row field
/// called `resultCode` or `totalCount` is not read as the page's.
String? _xmlText(XmlElement root, String name) =>
    _outsideRows(root, name).firstOrNull?.innerText.trim();

Iterable<XmlElement> _outsideRows(XmlElement root, String name) => root
    .findAllElements(name)
    .where(
      (element) => !element.ancestorElements.any(
        (ancestor) => ancestor.name.local == 'item',
      ),
    );

int? _toInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}'.trim());

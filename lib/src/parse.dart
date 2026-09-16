import 'dart:convert';

import 'package:xml/xml.dart';

import 'response.dart';

/// Percent-encodes a decoded service key.
///
/// Decoded keys contain `+`, `/`, and `=`, which change meaning inside a query
/// string and are the usual cause of `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`. A
/// key that is already percent-encoded is passed through unchanged.
String encodeServiceKey(String key) =>
    RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(key) ? key : Uri.encodeComponent(key);

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
  throw DataGoKrException(
    'The service returned neither JSON nor XML'
    '${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
    code: 'invalid_response',
    statusCode: statusCode,
  );
}

DataGoKrResponse _parseXml(String text, String body, int? statusCode) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException {
    throw DataGoKrException(
      'The service returned malformed XML'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
      code: 'invalid_response',
      statusCode: statusCode,
    );
  }
  final root = document.rootElement;

  // Authentication and quota failures use their own envelope.
  if (root.name.local == 'OpenAPI_ServiceResponse') {
    _throwPortalError(
      _xmlText(root, 'returnReasonCode'),
      _xmlText(root, 'errMsg') ?? _xmlText(root, 'returnAuthMsg'),
      statusCode,
    );
  }
  if (root.name.local == 'html' || root.name.local == 'HTML') {
    throw DataGoKrException(
      'The service returned an HTML page'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
      code: 'invalid_response',
      statusCode: statusCode,
    );
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
    items: [for (final item in root.findAllElements('item')) _xmlItem(item)],
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
    throw DataGoKrException(
      'The service returned malformed JSON'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}.',
      code: 'invalid_response',
      statusCode: statusCode,
    );
  }
  if (json is! Map<String, Object?>) {
    throw DataGoKrException(
      'The service returned a JSON value that is not an object.',
      code: 'invalid_response',
      statusCode: statusCode,
    );
  }

  // Authentication and quota failures use their own envelope.
  final envelope = json['OpenAPI_ServiceResponse'];
  if (envelope is Map) {
    final header = envelope['cmmMsgHeader'];
    final fields = header is Map ? header : envelope;
    _throwPortalError(
      _string(fields['returnReasonCode']),
      _string(fields['errMsg']) ?? _string(fields['returnAuthMsg']),
      statusCode,
    );
  }

  // api.odcloud.kr reports errors as {"code": -4, "msg": "..."}.
  if (json['code'] is num && json['msg'] is String) {
    _throwPortalError(_string(json['code']), json['msg'] as String, statusCode);
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

  final response = json['response'];
  if (response is! Map) {
    throw DataGoKrException(
      'The service returned JSON without a response envelope.',
      code: 'invalid_response',
      statusCode: statusCode,
    );
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

Map<String, Object?> _xmlItem(XmlElement item) => <String, Object?>{
  for (final field in item.childElements)
    field.name.local: field.innerText.trim(),
};

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

String? _xmlText(XmlElement root, String name) =>
    root.findAllElements(name).firstOrNull?.innerText.trim();

int? _toInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}'.trim());

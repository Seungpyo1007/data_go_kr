import 'dart:convert';

import 'package:data_go_kr/data_go_kr.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _endpoint =
    'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst';

/// Answers every request with [body], recording the requested URLs.
MockClient _serves(String body, {int status = 200, List<Uri>? requests}) =>
    MockClient((request) async {
      requests?.add(request.url);
      return http.Response(
        body,
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

String _jsonPage({required String items, int total = 2}) =>
    '{"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE."},'
    '"body":{"dataType":"JSON","items":$items,'
    '"pageNo":1,"numOfRows":10,"totalCount":$total}}}';

/// Stands in for a TLS failure, which `http` does not wrap.
class _HandshakeFailure implements Exception {
  _HandshakeFailure(this.url);
  final String url;
  @override
  String toString() => 'HandshakeException: $url';
}

Matcher _throwsCode(String code) =>
    throwsA(isA<DataGoKrException>().having((e) => e.code, 'code', code));

void main() {
  group('request building', () {
    test('percent-encodes a decoded service key', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'ab+cd/ef==',
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get(_endpoint, query: {'nx': 60, 'ny': 127});

      expect(requests.single.query, contains('serviceKey=ab%2Bcd%2Fef%3D%3D'));
      expect(requests.single.queryParameters['serviceKey'], 'ab+cd/ef==');
    });

    test('passes an already encoded key through unchanged', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'ab%2Bcd%2Fef%3D%3D',
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get(_endpoint);

      expect(requests.single.query, contains('serviceKey=ab%2Bcd%2Fef%3D%3D'));
    });

    test('adds paging defaults and keeps endpoint parameters', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'key',
        numOfRows: 50,
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get('$_endpoint?serviceName=test', query: {'nx': 60});

      final query = requests.single.queryParameters;
      expect(query['serviceName'], 'test');
      expect(query['nx'], '60');
      expect(query['pageNo'], '1');
      expect(query['numOfRows'], '50');
      expect(query['dataType'], 'JSON');
    });

    test('trims the key and rejects a second key', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: ' ab+cd==\n',
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get(_endpoint);
      expect(requests.single.query, contains('serviceKey=ab%2Bcd%3D%3D'));
      expect(requests.single.query, isNot(contains('%0A')));

      expect(
        () => client.get(_endpoint, query: {'serviceKey': 'other'}),
        throwsArgumentError,
      );
      expect(
        () => client.get('$_endpoint?ServiceKey=other'),
        throwsArgumentError,
      );
    });

    test('keeps returnType and uses odcloud paging names', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get(_endpoint, query: {'returnType': 'json'});
      await client.get('https://api.odcloud.kr/api/x/v1/y', pageNo: 3, rows: 7);

      expect(requests.first.queryParameters.containsKey('dataType'), isFalse);
      final odcloud = requests.last.queryParameters;
      expect(odcloud['page'], '3');
      expect(odcloud['perPage'], '7');
      expect(odcloud.containsKey('pageNo'), isFalse);
      expect(odcloud.containsKey('numOfRows'), isFalse);
      expect(odcloud.containsKey('dataType'), isFalse);
    });

    test('adds a default for paging parameters set to null', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get(_endpoint, query: {'pageNo': null}, pageNo: 2);

      expect(requests.single.queryParameters['pageNo'], '2');
    });

    test('decodes the declared charset', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: MockClient(
          (request) async => http.Response.bytes(
            latin1.encode(_jsonPage(items: '{"item":[{"n":"caf\u00e9"}]}')),
            200,
            headers: {'content-type': 'application/json; charset=ISO-8859-1'},
          ),
        ),
      );

      expect((await client.get(_endpoint)).items.single['n'], 'café');
    });

    test('lets the caller override defaults and drops null values', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(_jsonPage(items: '{"item":[]}'), requests: requests),
      );

      await client.get(
        _endpoint,
        query: {'dataType': 'XML', 'numOfRows': 5, 'skipped': null},
      );

      final query = requests.single.queryParameters;
      expect(query['dataType'], 'XML');
      expect(query['numOfRows'], '5');
      expect(query.containsKey('skipped'), isFalse);
    });
  });

  group('JSON answers', () {
    test('reads rows, counts, and the result code', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          _jsonPage(
            items:
                '{"item":[{"category":"TMP","fcstValue":"21"},'
                '{"category":"POP","fcstValue":"30"}]}',
          ),
        ),
      );

      final response = await client.get(_endpoint);

      expect(response.items, [
        {'category': 'TMP', 'fcstValue': '21'},
        {'category': 'POP', 'fcstValue': '30'},
      ]);
      expect(response.totalCount, 2);
      expect(response.pageNo, 1);
      expect(response.numOfRows, 10);
      expect(response.resultCode, '00');
      expect(response.isEmpty, isFalse);
    });

    test('wraps a single item object in a list', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          _jsonPage(items: '{"item":{"category":"TMP"}}', total: 1),
        ),
      );

      expect((await client.get(_endpoint)).items, [
        {'category': 'TMP'},
      ]);
    });

    test('treats an empty items string as no rows', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(_jsonPage(items: '""', total: 0)),
      );

      expect((await client.get(_endpoint)).isEmpty, isTrue);
    });

    test('reports no data as an empty page, not an error', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '{"response":{"header":{"resultCode":"03",'
          '"resultMsg":"NODATA_ERROR"}}}',
        ),
      );

      final response = await client.get(_endpoint);
      expect(response.items, isEmpty);
      expect(response.resultCode, '03');
    });

    test('reads the api.odcloud.kr shape', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '{"currentCount":1,"data":[{"name":"seoul"}],"matchCount":1,'
          '"page":2,"perPage":10,"totalCount":41}',
        ),
      );

      final response = await client.get('https://api.odcloud.kr/api/x/v1/y');

      expect(response.items, [
        {'name': 'seoul'},
      ]);
      expect(response.totalCount, 41);
      expect(response.pageNo, 2);
      expect(response.numOfRows, 10);
    });
  });

  group('XML answers', () {
    test('reads rows and counts, trimming values', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '<?xml version="1.0" encoding="UTF-8"?><response><header>'
          '<resultCode>00</resultCode><resultMsg>NORMAL SERVICE.</resultMsg>'
          '</header><body><items>'
          '<item><aptNm> 래미안 </aptNm><dealAmount>120,000</dealAmount></item>'
          '<item><aptNm>힐스테이트</aptNm><dealAmount>95,000</dealAmount></item>'
          '</items><numOfRows>10</numOfRows><pageNo>1</pageNo>'
          '<totalCount>2</totalCount></body></response>',
        ),
      );

      final response = await client.get(_endpoint, query: {'dataType': 'XML'});

      expect(response.items.first, {'aptNm': '래미안', 'dealAmount': '120,000'});
      expect(response.items, hasLength(2));
      expect(response.totalCount, 2);
      expect(response.resultMsg, 'NORMAL SERVICE.');
    });

    test('maps the XML error envelope', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '<?xml version="1.0" encoding="UTF-8"?><OpenAPI_ServiceResponse>'
          '<cmmMsgHeader><errMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</errMsg>'
          '<returnAuthMsg>등록되지 않은 서비스키</returnAuthMsg>'
          '<returnReasonCode>30</returnReasonCode></cmmMsgHeader>'
          '</OpenAPI_ServiceResponse>',
          status: 403,
        ),
      );

      await expectLater(
        client.get(_endpoint),
        throwsA(
          isA<DataGoKrException>()
              .having((e) => e.code, 'code', 'unauthorized_key')
              .having((e) => e.reasonCode, 'reasonCode', '30')
              .having((e) => e.statusCode, 'statusCode', 403)
              .having(
                (e) => e.message,
                'message',
                'SERVICE_KEY_IS_NOT_REGISTERED_ERROR (등록되지 않은 서비스키)',
              ),
        ),
      );
    });

    test('prefers the reason over an older gateway\'s SERVICE ERROR', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '<OpenAPI_ServiceResponse><cmmMsgHeader>'
          '<errMsg>SERVICE ERROR</errMsg>'
          '<returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg>'
          '<returnReasonCode>30</returnReasonCode></cmmMsgHeader>'
          '</OpenAPI_ServiceResponse>',
        ),
      );

      await expectLater(
        client.get(_endpoint),
        throwsA(
          isA<DataGoKrException>().having(
            (e) => e.message,
            'message',
            'SERVICE_KEY_IS_NOT_REGISTERED_ERROR (SERVICE ERROR)',
          ),
        ),
      );
    });

    test(
      'reads rows only from <items>, not elements nested in a row',
      () async {
        final client = DataGoKrClient(
          serviceKey: 'key',
          client: _serves(
            '<response><header><resultCode>00</resultCode></header><body>'
            '<items><item><name>a</name><parts><item>x</item></parts>'
            '<totalCount>9</totalCount></item>'
            '<item><name>b</name></item></items>'
            '<totalCount>2</totalCount></body></response>',
          ),
        );

        final response = await client.get(_endpoint);

        expect(response.items.map((row) => row['name']), ['a', 'b']);
        expect(response.totalCount, 2);
      },
    );
  });

  group('errors', () {
    test('maps the JSON error envelope', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '{"OpenAPI_ServiceResponse":{"cmmMsgHeader":{'
          '"errMsg":"LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR",'
          '"returnAuthMsg":"서비스 요청제한횟수 초과에러",'
          '"returnReasonCode":"22"}}}',
          status: 403,
        ),
      );

      await expectLater(client.get(_endpoint), _throwsCode('rate_limit'));
    });

    test('maps the api.odcloud.kr error shape', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves('{"code":-4,"msg":"등록되지 않은 인증키 입니다."}', status: 401),
      );

      await expectLater(
        client.get('https://api.odcloud.kr/api/x/v1/y'),
        _throwsCode('unauthorized_key'),
      );
    });

    test('maps an invalid parameter result code', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '{"response":{"header":{"resultCode":"10",'
          '"resultMsg":"INVALID_REQUEST_PARAMETER_ERROR"}}}',
        ),
      );

      await expectLater(
        client.get(_endpoint),
        _throwsCode('invalid_parameter'),
      );
    });

    test('rejects HTML, malformed, and empty bodies', () async {
      final html = DataGoKrClient(
        serviceKey: 'key',
        client: _serves('<!doctype html><html><body>503</body></html>'),
      );
      await expectLater(html.get(_endpoint), _throwsCode('invalid_response'));

      final broken = DataGoKrClient(
        serviceKey: 'key',
        client: _serves('{"response":'),
      );
      await expectLater(broken.get(_endpoint), _throwsCode('invalid_response'));

      final empty = DataGoKrClient(serviceKey: 'key', client: _serves('   '));
      await expectLater(empty.get(_endpoint), _throwsCode('invalid_response'));
    });

    test('falls back to the HTTP status for an unreadable body', () async {
      Future<void> expectStatus(int status, String body, String code) async {
        final client = DataGoKrClient(
          serviceKey: 'key',
          client: _serves(body, status: status),
        );
        await expectLater(
          client.get(_endpoint),
          throwsA(
            isA<DataGoKrException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.statusCode, 'statusCode', status),
          ),
        );
      }

      await expectStatus(401, 'Unauthorized', 'unauthorized_key');
      await expectStatus(
        403,
        '<html><body>Forbidden</body></html>',
        'unauthorized_key',
      );
      await expectStatus(429, 'Too Many Requests', 'rate_limit');
      await expectStatus(503, '<!doctype html><html></html>', 'http_error');
      await expectStatus(502, '', 'http_error');
      await expectStatus(401, '', 'unauthorized_key');
    });

    test('maps more portal and odcloud reason codes', () {
      expect(errorCodeFor('21'), 'unauthorized_key');
      expect(errorCodeFor('05'), 'timeout');
      expect(errorCodeFor('04'), 'http_error');
      expect(errorCodeFor('99'), 'service_error');
      expect(errorCodeFor('-3'), 'unknown_service');
      expect(errorCodeFor('-401'), 'unauthorized_key');
    });

    test('reads a header and body sent without a response wrapper', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: _serves(
          '{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE."},'
          '"body":{"items":[{"ITEM_NAME":"a"}],"totalCount":1,'
          '"pageNo":1,"numOfRows":10}}',
        ),
      );

      final response = await client.get(_endpoint);

      expect(response.items, [
        {'ITEM_NAME': 'a'},
      ]);
      expect(response.totalCount, 1);
    });

    test('wraps other client failures without the URL', () async {
      final client = DataGoKrClient(
        serviceKey: 'secret',
        client: MockClient(
          (request) async => throw _HandshakeFailure('${request.url}'),
        ),
      );

      await expectLater(
        client.get(_endpoint),
        throwsA(
          isA<DataGoKrException>()
              .having((e) => e.code, 'code', 'http_error')
              .having((e) => e.message, 'message', isNot(contains('secret'))),
        ),
      );
    });

    test('times out, and retries once when the connection drops', () async {
      final slow = DataGoKrClient(
        serviceKey: 'key',
        timeout: const Duration(milliseconds: 20),
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(slow.get(_endpoint), _throwsCode('timeout'));

      var calls = 0;
      final dropping = DataGoKrClient(
        serviceKey: 'key',
        client: MockClient((request) async {
          if (calls++ == 0) {
            throw http.ClientException('Connection closed', request.url);
          }
          return http.Response(_jsonPage(items: '{"item":[{"a":"b"}]}'), 200);
        }),
      );

      expect((await dropping.get(_endpoint)).items, [
        {'a': 'b'},
      ]);
      expect(calls, 2);
    });
  });

  test('paginate follows totalCount and stops', () async {
    var lastPage = 0;
    final client = DataGoKrClient(
      serviceKey: 'key',
      client: MockClient((request) async {
        lastPage = int.parse(request.url.queryParameters['pageNo']!);
        final rows = lastPage < 3
            ? '[{"n":"$lastPage-1"},{"n":"$lastPage-2"}]'
            : '[{"n":"5"}]';
        return http.Response(_jsonPage(items: '{"item":$rows}', total: 5), 200);
      }),
    );

    final rows = await client.paginate(_endpoint, rows: 2).toList();

    expect(rows, hasLength(5));
    expect(lastPage, 3);
  });

  test('paginate stops at an empty page', () async {
    final client = DataGoKrClient(
      serviceKey: 'key',
      client: MockClient((request) async {
        final page = int.parse(request.url.queryParameters['pageNo']!);
        return http.Response(
          _jsonPage(
            items: page == 1 ? '{"item":[{"n":"1"}]}' : '""',
            total: 99,
          ),
          200,
        );
      }),
    );

    expect(await client.paginate(_endpoint, rows: 1).toList(), hasLength(1));
  });

  test('paginate reads odcloud pages with page and perPage', () async {
    final requested = <String>[];
    final client = DataGoKrClient(
      serviceKey: 'key',
      client: MockClient((request) async {
        final query = request.url.queryParameters;
        requested.add('${query['page']}/${query['perPage']}');
        final page = int.parse(query['page']!);
        final rows = page < 3
            ? '[{"n":"$page-1"},{"n":"$page-2"}]'
            : '[{"n":"5"}]';
        return http.Response(
          '{"data":$rows,"page":$page,"perPage":2,"totalCount":5}',
          200,
        );
      }),
    );

    final rows = await client
        .paginate('https://api.odcloud.kr/api/x/v1/y', rows: 2)
        .toList();

    expect(rows.map((row) => row['n']), ['1-1', '1-2', '2-1', '2-2', '5']);
    expect(requested, ['1/2', '2/2', '3/2']);
  });

  test('paginate replaces paging parameters given in query', () async {
    final pages = <String>[];
    final client = DataGoKrClient(
      serviceKey: 'key',
      client: MockClient((request) async {
        final query = request.url.queryParameters;
        pages.add('${query['pageNo']}/${query['numOfRows']}');
        final page = int.parse(query['pageNo']!);
        return http.Response(
          _jsonPage(items: '{"item":[{"n":"$page"}]}', total: 2),
          200,
        );
      }),
    );

    final rows = await client
        .paginate(_endpoint, query: {'pageNo': 1, 'numOfRows': 1})
        .toList();

    expect(rows, hasLength(2));
    expect(pages, ['1/1', '2/1']);
  });
}

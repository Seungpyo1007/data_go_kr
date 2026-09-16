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
                'SERVICE_KEY_IS_NOT_REGISTERED_ERROR',
              ),
        ),
      );
    });
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
        client: _serves(
          '<!doctype html><html><body>503</body></html>',
          status: 503,
        ),
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
}

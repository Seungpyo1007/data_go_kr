import 'dart:async';
import 'dart:convert';

import 'package:data_go_kr/data_go_kr.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _forecast =
    'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _page(Object? items, {int total = 1}) => {
  'response': {
    'header': {'resultCode': '00', 'resultMsg': 'NORMAL SERVICE.'},
    'body': {
      'items': items,
      'numOfRows': 100,
      'pageNo': 1,
      'totalCount': total,
    },
  },
};

/// A retry policy that records its waits instead of sleeping.
RetryPolicy _recording(List<Duration> waits, {int maxRetries = 2}) =>
    RetryPolicy(
      maxRetries: maxRetries,
      sleep: (delay) async => waits.add(delay),
    );

Matcher _throwsCode(String code) =>
    throwsA(isA<DataGoKrException>().having((e) => e.code, 'code', code));

void main() {
  group('RetryPolicy', () {
    test('backs off exponentially up to the cap', () {
      const policy = RetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 350),
      );
      expect(
        [for (var i = 0; i < 4; i++) policy.delayFor(i).inMilliseconds],
        [100, 200, 350, 350],
      );
    });

    test('retries server errors, timeouts, and rate limits only', () {
      const policy = RetryPolicy();
      DataGoKrException error(String code, {int? status, String? reason}) =>
          DataGoKrException(
            'x',
            code: code,
            statusCode: status,
            reasonCode: reason,
          );
      expect(policy.shouldRetry(error('http_error')), isTrue);
      expect(policy.shouldRetry(error('http_error', status: 503)), isTrue);
      expect(policy.shouldRetry(error('http_error', status: 404)), isFalse);
      expect(policy.shouldRetry(error('timeout')), isTrue);
      expect(policy.shouldRetry(error('rate_limit', status: 429)), isTrue);
      // The portal's 22 is a daily quota: waiting does not help.
      expect(
        policy.shouldRetry(error('rate_limit', status: 200, reason: '22')),
        isFalse,
      );
      expect(policy.shouldRetry(error('unauthorized_key')), isFalse);
      expect(policy.shouldRetry(error('invalid_parameter')), isFalse);
    });

    test('the client retries 5xx, portal timeouts, and 429', () async {
      final waits = <Duration>[];
      final answers = [
        http.Response('<html>Bad Gateway</html>', 502),
        _json({
          'response': {
            'header': {'resultCode': '05', 'resultMsg': 'SERVICETIME_OUT'},
          },
        }),
        http.Response('', 429),
        _json(
          _page([
            {'a': 1},
          ]),
        ),
      ];
      var calls = 0;
      final client = DataGoKrClient(
        serviceKey: 'key',
        retry: _recording(waits, maxRetries: 3),
        client: MockClient((request) async => answers[calls++]),
      );

      final page = await client.get(_forecast);
      expect(page.items, [
        {'a': 1},
      ]);
      expect(calls, 4);
      expect(waits, const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
        Duration(seconds: 1),
      ]);
    });

    test('gives up after maxRetries and keeps the last error', () async {
      final waits = <Duration>[];
      var calls = 0;
      final client = DataGoKrClient(
        serviceKey: 'key',
        retry: _recording(waits),
        client: MockClient((request) async {
          calls++;
          return http.Response('', 503);
        }),
      );
      await expectLater(client.get(_forecast), _throwsCode('http_error'));
      expect(calls, 3);
      expect(waits, hasLength(2));
    });

    test('does not retry key errors or RetryPolicy.none', () async {
      var calls = 0;
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: MockClient((request) async {
          calls++;
          return _json({
            'OpenAPI_ServiceResponse': {
              'cmmMsgHeader': {
                'errMsg': 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR',
                'returnAuthMsg': '등록되지 않은 서비스키',
                'returnReasonCode': '30',
              },
            },
          });
        }),
      );
      await expectLater(client.get(_forecast), _throwsCode('unauthorized_key'));
      expect(calls, 1);

      calls = 0;
      final once = DataGoKrClient(
        serviceKey: 'key',
        retry: RetryPolicy.none,
        client: MockClient((request) async {
          calls++;
          return http.Response('', 503);
        }),
      );
      await expectLater(once.get(_forecast), _throwsCode('http_error'));
      expect(calls, 1);
    });
  });

  group('timeouts', () {
    test('abort the request through its trigger', () async {
      final aborted = Completer<void>();
      final client = DataGoKrClient(
        serviceKey: 'key',
        timeout: const Duration(milliseconds: 20),
        retry: RetryPolicy.none,
        client: _AbortRecordingClient(aborted),
      );
      await expectLater(client.get(_forecast), _throwsCode('timeout'));
      await aborted.future.timeout(const Duration(seconds: 1));
    });

    test('end the wait even when the client ignores the trigger', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        timeout: const Duration(milliseconds: 20),
        retry: RetryPolicy.none,
        client: MockClient((request) => Completer<http.Response>().future),
      );
      await expectLater(client.get(_forecast), _throwsCode('timeout'));
    });

    test('are retried for GET', () async {
      final waits = <Duration>[];
      var calls = 0;
      final client = DataGoKrClient(
        serviceKey: 'key',
        timeout: const Duration(milliseconds: 20),
        retry: _recording(waits),
        client: MockClient((request) async {
          if (calls++ == 0) return Completer<http.Response>().future;
          return _json(
            _page([
              {'a': 1},
            ]),
          );
        }),
      );
      expect((await client.get(_forecast)).items, hasLength(1));
      expect(calls, 2);
    });
  });

  group('post', () {
    test('sends a JSON body with the key and no paging parameters', () async {
      late http.Request sent;
      final client = DataGoKrClient(
        serviceKey: 'a+b/c=',
        client: MockClient((request) async {
          sent = request;
          return _json({
            'status_code': 'OK',
            'request_cnt': 1,
            'data': [
              {'b_no': '1234567890'},
            ],
          });
        }),
      );

      final response = await client.post(
        'https://api.odcloud.kr/api/nts-businessman/v1/status',
        json: {
          'b_no': ['1234567890'],
        },
      );

      expect(sent.method, 'POST');
      expect(sent.url.query, 'serviceKey=a%2Bb%2Fc%3D');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {
        'b_no': ['1234567890'],
      });
      expect(response.items.single['b_no'], '1234567890');
    });

    test('is retried only when idempotent', () async {
      for (final idempotent in [false, true]) {
        var calls = 0;
        final client = DataGoKrClient(
          serviceKey: 'key',
          retry: _recording([]),
          client: MockClient((request) async {
            calls++;
            return http.Response('', 503);
          }),
        );
        await expectLater(
          client.post(
            'https://api.odcloud.kr/x',
            json: const {},
            idempotent: idempotent,
          ),
          _throwsCode('http_error'),
        );
        expect(calls, idempotent ? 3 : 1);
      }
    });

    test('maps the National Tax Service status codes', () async {
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: MockClient(
          (request) async =>
              _json({'status_code': 'TOO_LARGE_REQUEST'}, status: 413),
        ),
      );
      await expectLater(
        client.post('https://api.odcloud.kr/x', json: const {}),
        throwsA(
          isA<DataGoKrException>()
              .having((e) => e.code, 'code', 'invalid_parameter')
              .having((e) => e.reasonCode, 'reasonCode', 'TOO_LARGE_REQUEST')
              .having((e) => e.statusCode, 'statusCode', 413),
        ),
      );
    });
  });

  group('KoreanHolidays', () {
    test('reads rest days in the guide shape', () async {
      final requests = <Uri>[];
      final client = DataGoKrClient(
        serviceKey: 'key',
        client: MockClient((request) async {
          requests.add(request.url);
          return _json(
            _page({
              'item': [
                {
                  'dateKind': '01',
                  'dateName': '한글날',
                  'isHoliday': 'Y',
                  'locdate': 20261009,
                  'seq': 1,
                },
                {
                  'dateKind': '01',
                  'dateName': '개천절',
                  'isHoliday': 'Y',
                  'locdate': 20261003,
                  'seq': 1,
                },
              ],
            }, total: 2),
          );
        }),
      );

      final days = await KoreanHolidays(client).restDays(2026, month: 10);

      final url = requests.single;
      expect(
        url.path,
        '/B090041/openapi/service/SpcdeInfoService/getRestDeInfo',
      );
      expect(url.queryParameters['solYear'], '2026');
      expect(url.queryParameters['solMonth'], '10');
      expect(url.queryParameters['_type'], 'json');
      expect(url.queryParameters.containsKey('dataType'), isFalse);
      // Sorted by date.
      expect(days.map((d) => d.name), ['개천절', '한글날']);
      expect(days.first.date, DateTime.utc(2026, 10, 3));
      expect(days.first.isHoliday, isTrue);
      expect(days.first.kind, KoreanDateKind.national);
    });

    test('reads one item, solar term fields, and an empty month', () async {
      final bodies = [
        _page({
          'item': {
            'dateKind': '03',
            'dateName': '상강',
            'isHoliday': 'N',
            'kst': '1251',
            'locdate': '20261023',
            'seq': '1',
            'sunLongitude': '210',
          },
        }),
        _page(''),
      ];
      var call = 0;
      final holidays = KoreanHolidays(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient((request) async => _json(bodies[call++])),
        ),
      );

      final term = (await holidays.solarTerms(2026, month: 10)).single;
      expect(term.kind, KoreanDateKind.solarTerm);
      expect(term.isHoliday, isFalse);
      expect(term.time, '1251');
      expect(term.sunLongitude, 210);
      expect(await holidays.restDays(2026, month: 2), isEmpty);
    });

    test('isRestDay and argument checks', () async {
      final holidays = KoreanHolidays(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient(
            (request) async => _json(
              _page({
                'item': {
                  'dateKind': '01',
                  'dateName': '추석',
                  'isHoliday': 'Y',
                  'locdate': 20260925,
                  'seq': 1,
                },
              }),
            ),
          ),
        ),
      );
      expect(await holidays.isRestDay(DateTime(2026, 9, 25)), isTrue);
      expect(await holidays.isRestDay(DateTime(2026, 9, 24)), isFalse);
      await expectLater(holidays.restDays(26), throwsArgumentError);
      await expectLater(
        holidays.restDays(2026, month: 13),
        throwsArgumentError,
      );
    });
  });

  group('AirKorea', () {
    // The guide's sample row, with an instrument under check.
    const checking = <String, Object?>{
      'so2Grade': '',
      'coFlag': '점검및교정',
      'khaiValue': '-',
      'so2Value': '0.020',
      'coValue': '2.1',
      'pm10Flag': '점검및교정',
      'pm10Value': '13',
      'dataTime': '2020-11-25 13:00',
      'no2Value': '0.011',
      'o3Value': '0.068',
    };

    test('queries a station with returnType and version 1.5', () async {
      final requests = <Uri>[];
      final air = AirKorea(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient((request) async {
            requests.add(request.url);
            return _json(
              _page([
                {
                  'dataTime': '2026-10-22 24:00',
                  'stationName': '종로구',
                  'stationCode': '111123',
                  'mangName': '도시대기',
                  'pm10Value': '35',
                  'pm10Value24': '30',
                  'pm25Value': '18',
                  'pm25Value24': '15',
                  'pm10Grade': '2',
                  'pm25Grade': '2',
                  'pm10Grade1h': '1',
                  'pm25Grade1h': '2',
                  'khaiValue': '61',
                  'khaiGrade': '2',
                  'o3Value': '0.0321',
                  'o3Grade': '1',
                },
                checking,
              ], total: 2),
            );
          }),
        ),
      );

      final rows = await air.station('종로구', period: AirKoreaPeriod.month);

      final url = requests.single;
      expect(
        url.path,
        '/B552584/ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty',
      );
      expect(url.queryParameters['stationName'], '종로구');
      expect(url.queryParameters['dataTerm'], 'MONTH');
      expect(url.queryParameters['returnType'], 'json');
      expect(url.queryParameters['ver'], '1.5');
      expect(url.queryParameters.containsKey('dataType'), isFalse);

      final now = rows.first;
      // 24:00 KST is the next midnight, 15:00 UTC of the same day.
      expect(now.dataTime, DateTime.utc(2026, 10, 22, 15));
      expect(now.networkType, '도시대기');
      expect((now.pm10, now.pm10Day, now.pm25, now.pm25Day), (35, 30, 18, 15));
      expect(now.pm10Grade, AirQualityGrade.moderate);
      expect(now.pm10Grade1h, AirQualityGrade.good);
      expect(now.khaiGrade?.label, '보통');
      expect(now.o3, 0.0321);

      final checked = rows.last;
      expect(checked.khaiValue, isNull);
      expect(checked.so2Grade, isNull);
      expect(checked.pm10, 13);
      expect(checked.pm10Flag, '점검및교정');
      expect(checked.dataTime, DateTime.utc(2020, 11, 25, 4));
    });

    test('queries a province', () async {
      late Uri url;
      final air = AirKorea(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient((request) async {
            url = request.url;
            return _json(
              _page([
                {
                  'sidoName': '서울',
                  'stationName': '중구',
                  'dataTime': '2026-10-22 13:00',
                },
              ]),
            );
          }),
        ),
      );
      final rows = await air.province('서울');
      expect(url.path, endsWith('/getCtprvnRltmMesureDnsty'));
      expect(url.queryParameters['sidoName'], '서울');
      expect(rows.single.sidoName, '서울');
      expect(
        AirQualityMeasurement.fromRow(const {'dataTime': 'x'}).dataTime,
        isNull,
      );
    });
  });

  group('BusinessStatusService', () {
    test('checks numbers in batches and keeps the order', () async {
      final bodies = <List<String>>[];
      final service = BusinessStatusService(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient((request) async {
            final numbers = [
              for (final n in (jsonDecode(request.body) as Map)['b_no'] as List)
                '$n',
            ];
            bodies.add(numbers);
            return _json({
              'status_code': 'OK',
              'match_cnt': numbers.length,
              'request_cnt': numbers.length,
              'data': [
                for (final n in numbers.reversed)
                  {
                    'b_no': n,
                    'b_stt': '계속사업자',
                    'b_stt_cd': '01',
                    'tax_type': '부가가치세 일반과세자',
                    'tax_type_cd': '01',
                    'end_dt': '',
                    'utcc_yn': 'N',
                    'tax_type_change_dt': '20200101',
                    'invoice_apply_dt': '',
                    'rbf_tax_type': '해당없음',
                    'rbf_tax_type_cd': '99',
                  },
              ],
            });
          }),
        ),
      );

      final numbers = [for (var i = 0; i < 150; i++) '${1000000000 + i}'];
      numbers[0] = '124-81-00998';
      final statuses = await service.check(numbers);

      expect(bodies.map((b) => b.length), [100, 50]);
      expect(bodies.first.first, '1248100998');
      expect(statuses.map((s) => s.number).take(2), [
        '1248100998',
        '1000000001',
      ]);
      final first = statuses.first;
      expect(first.isRegistered, isTrue);
      expect(first.state, BusinessState.active);
      expect(first.taxType, BusinessTaxType.general);
      expect(first.closedForUnitTaxation, isFalse);
      expect(first.taxTypeChangedOn, DateTime.utc(2020));
      expect(first.invoiceAppliedOn, isNull);
      expect(first.previousTaxType, isNull);
      expect(first.previousTaxTypeLabel, '해당없음');
    });

    test('reads an unregistered number and a closed one', () async {
      final service = BusinessStatusService(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient(
            (request) async => _json({
              'status_code': 'OK',
              'match_cnt': 1,
              'request_cnt': 2,
              'data': [
                {
                  'b_no': '0000000000',
                  'b_stt': '',
                  'b_stt_cd': '',
                  'tax_type': '국세청에 등록되지 않은 사업자등록번호입니다.',
                  'tax_type_cd': '',
                  'end_dt': '',
                  'utcc_yn': '',
                  'tax_type_change_dt': '',
                  'invoice_apply_dt': '',
                  'rbf_tax_type': '',
                  'rbf_tax_type_cd': '',
                },
                {
                  'b_no': '1111111111',
                  'b_stt': '폐업자',
                  'b_stt_cd': '03',
                  'tax_type': '부가가치세 간이과세자',
                  'tax_type_cd': '02',
                  'end_dt': '20240630',
                  'utcc_yn': 'N',
                  'rbf_tax_type_cd': '01',
                },
              ],
            }),
          ),
        ),
      );

      final [unknown, closed] = await service.check([
        '0000000000',
        '1111111111',
      ]);
      expect(unknown.isRegistered, isFalse);
      expect(unknown.state, isNull);
      expect(unknown.taxTypeLabel, startsWith('국세청에 등록되지 않은'));
      expect(closed.state, BusinessState.closed);
      expect(closed.closedOn, DateTime.utc(2024, 6, 30));
      expect(closed.taxType, BusinessTaxType.simplified);
      expect(closed.previousTaxType, BusinessTaxType.general);
    });

    test('rejects malformed numbers before sending', () async {
      var calls = 0;
      final service = BusinessStatusService(
        DataGoKrClient(
          serviceKey: 'key',
          client: MockClient((request) async {
            calls++;
            return _json({'status_code': 'OK', 'data': <Object>[]});
          }),
        ),
      );
      await expectLater(service.check(['123']), throwsArgumentError);
      expect(calls, 0);
    });

    test('validates the checksum', () {
      expect(BusinessStatusService.isValidNumber('124-81-00998'), isTrue);
      expect(BusinessStatusService.isValidNumber('1248100997'), isFalse);
      expect(BusinessStatusService.isValidNumber('12481009'), isFalse);
    });
  });
}

/// Never answers, and completes [aborted] when a request's trigger fires.
class _AbortRecordingClient extends http.BaseClient {
  _AbortRecordingClient(this.aborted);

  final Completer<void> aborted;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final result = Completer<http.StreamedResponse>();
    if (request case http.Abortable(:final abortTrigger?)) {
      abortTrigger.then((_) {
        if (!aborted.isCompleted) aborted.complete();
        result.completeError(http.RequestAbortedException(request.url));
      });
    }
    return result.future;
  }
}

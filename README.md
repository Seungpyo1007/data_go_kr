<p align="center">
  <img src="https://raw.githubusercontent.com/Seungpyo1007/data_go_kr/main/assets/data_go_kr-logo.png" alt="data_go_kr logo: a data store with an arrow leaving it" width="128">
</p>

<h1 align="center">data_go_kr</h1>

<p align="center">
  <a href="https://pub.dev/packages/data_go_kr"><img src="https://img.shields.io/pub/v/data_go_kr" alt="pub version"></a>
  <a href="https://pub.dev/packages/data_go_kr/score"><img src="https://img.shields.io/pub/points/data_go_kr" alt="pub points"></a>
  <a href="https://github.com/Seungpyo1007/data_go_kr/actions/workflows/ci.yml"><img src="https://github.com/Seungpyo1007/data_go_kr/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Seungpyo1007/data_go_kr/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

Call open APIs from the Korean public data portal
([data.go.kr](https://www.data.go.kr)) without rewriting the same plumbing for
every service: the service key encoding, two answer formats, three error
shapes, paging, and retries. Typed helpers cover KMA weather forecasts, public
holidays, AirKorea air quality, and the National Tax Service business status
lookup.

This is an unofficial package. It is not affiliated with, or endorsed by, the
portal or any agency publishing data on it.

```dart
final client = DataGoKrClient(serviceKey: '<your decoded key>');

final forecast = await client.get(
  'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst',
  query: {'base_date': '20260916', 'base_time': '0500', 'nx': 60, 'ny': 127},
);

print(forecast.totalCount);        // 809
print(forecast.items.first);       // {baseDate: 20260916, category: TMP, ...}

client.close();
```

## What it handles for you

- **Service key encoding.** Decoded keys contain `+`, `/`, and `=`, which break
  inside a query string and cause `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`. Pass
  the decoded key; an already encoded key is used unchanged.
- **JSON and XML.** Some services answer only in XML, and some ignore
  `dataType=JSON`. Both are parsed into the same rows.
- **`items` shape.** Services send a list for several rows, a bare object for
  one row, and an empty string when nothing matched. All three become a list.
- **Three error shapes.** The `OpenAPI_ServiceResponse` envelope (XML and
  JSON), the `resultCode` in a normal envelope, and the
  `{"code": -4, "msg": "..."}` used by `api.odcloud.kr`.
- **Errors sent with HTTP 200.** The body is parsed first, so a failure is
  still an exception.
- **Paging.** `paginate` follows `totalCount` and yields every row, using
  `pageNo`/`numOfRows` on `apis.data.go.kr` and `page`/`perPage` on
  `api.odcloud.kr`.
- **No data is not an error.** `resultCode` `03` returns an empty page.
- **KMA grid cells.** `KmaGrid` converts a latitude and longitude to the
  `nx`/`ny` cell that weather services ask for.
- **KMA publish times.** `KmaBaseTime.latest` picks a `base_date` and
  `base_time` the service has actually published, and `KmaSky`,
  `KmaPrecipitation`, and `kmaCategory` turn the codes into readable values.
- **KMA forecasts as hours.** `KmaForecast.fromItems` groups the one-row-per-
  category answer into typed hours, reads classes such as `1mm 미만` and the
  qualitative codes of the five-day forecast, and drops the missing marker.
- **Retries and timeouts.** Dropped connections, timeouts, server errors, and
  rate limits are retried with exponential backoff, and a request still
  running at its timeout is aborted, not left open.
- **POST.** `post` sends a JSON body, for services such as the National Tax
  Service lookups on `api.odcloud.kr`.
- **Typed services.** `KoreanHolidays`, `AirKorea`, and
  `BusinessStatusService` return typed results for three popular services.

## Platform support

Pure Dart on top of `package:http` and `package:xml`: Dart VM, Flutter on
Android, iOS, Windows, macOS, Linux, and the web.

In a browser, CORS decides what works. `api.odcloud.kr` sends
`Access-Control-Allow-Origin: *`. `apis.data.go.kr` answers CORS preflight
requests, but its error answers, such as an unregistered key, come without
CORS headers, so the browser hides them and they surface as `http_error`
without the portal's message. A key in a web build is also visible to anyone:
put it behind your own backend for public sites.

## Installation

```yaml
dependencies:
  data_go_kr: ^0.1.0
```

Get a service key from [data.go.kr](https://www.data.go.kr) by applying for the
service you want, then use the **decoded** key. Pass it only to
`DataGoKrClient`: a `serviceKey` in the endpoint or `query` throws an
`ArgumentError`, since the request would carry two keys.

## Usage

Read every row of a service without writing a paging loop:

```dart
final client = DataGoKrClient(serviceKey: key, numOfRows: 500);

await for (final row in client.paginate(
  'https://apis.data.go.kr/1613000/RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev',
  query: {'LAWD_CD': '11110', 'DEAL_YMD': '202608', 'dataType': 'XML'},
)) {
  print('${row['aptNm']} ${row['dealAmount']}');
}
```

Handle failures by code:

```dart
try {
  await client.get(endpoint, query: {'nx': 60, 'ny': 127});
} on DataGoKrException catch (error) {
  switch (error.code) {
    case 'unauthorized_key':
      print('Key is wrong, not yet active, or used from an unlisted IP');
    case 'rate_limit':
      print('Daily request limit reached');
    case 'invalid_parameter':
      print('The service rejected a parameter: $error');
    default:
      print('${error.code}: $error (reason ${error.reasonCode})');
  }
}
```

| Code | Meaning |
| --- | --- |
| `unauthorized_key` | Key unknown, expired, suspended, missing, or IP not registered |
| `rate_limit` | Request quota exceeded |
| `invalid_parameter` | Missing or invalid request parameter |
| `unknown_service` | No such service for that endpoint |
| `service_error` | The service reported an internal failure |
| `http_error` | The connection failed, or the server answered with an HTTP error and no readable body |
| `timeout` | The request, or the service behind the gateway, did not answer in time |
| `invalid_response` | The answer was not usable JSON or XML |

The message holds the portal's own reason, for example
`SERVICE_KEY_IS_NOT_REGISTERED_ERROR (등록되지 않은 서비스키)`. When the body
says nothing usable, the HTTP status decides the code: 401 and 403 are
`unauthorized_key`, 429 is `rate_limit`, and other failures `http_error`.

### Weather grid cells

KMA forecast services take a grid cell, not a coordinate. The country is
covered by 5 km cells on a Lambert conformal conic projection, 149 columns by
253 rows.

```dart
final cell = KmaGrid.fromLatLon(37.5665, 126.9780); // Seoul City Hall
print('${cell.nx} ${cell.ny}');  // 60 127
print(cell.isInKorea);           // true

final center = cell.toLatLon();  // (lat: 37.5799, lon: 126.9894)
```

### Publish times and codes

A KMA service rejects a `base_time` it has not published yet, and each service
has its own schedule: the village forecast publishes at 02, 05, 08, 11, 14, 17,
20, and 23, ten minutes after each slot; the nowcast every hour, ten minutes
past; the ultra short forecast every half hour slot, 45 minutes past the hour.
These follow KMA's own guide (기상청41_단기예보 조회서비스 오픈API활용가이드,
October 2026). `KmaBaseTime` picks the newest published slot, in Korea Standard
Time whatever the device time zone is. Pass `now` as an instant, such as
`DateTime.now()` or a UTC time; a `DateTime` built from Korean wall-clock
values on a device in another zone names a different instant.

Services sometimes publish a minute or two late. Pass a longer `delay` to stay
clear of the edge, or step back with `previous` when a slot answers no data:

```dart
var base = KmaBaseTime.latest(
  KmaService.village,
  delay: const Duration(minutes: 15),
);
var page = await client.get(endpoint, query: {/* base.date, base.time, ... */});
if (page.isEmpty) base = base.previous(KmaService.village);
```

### Reading a forecast

The forecast services send one row per category and time. `KmaForecast` groups
them into hours with typed values:

```dart
final base = KmaBaseTime.latest(KmaService.village);
final page = await client.get(
  'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst',
  query: {
    'base_date': base.date,
    'base_time': base.time,
    'nx': cell.nx,
    'ny': cell.ny,
  },
  rows: 1000,
);

final forecast = KmaForecast.fromItems(page.items);
for (final hour in forecast.hours) {
  print('${hour.date} ${hour.hourText} '
      '${hour.temperature}℃ ${hour.sky?.label} '
      '비 ${hour.precipitationProbability}% ${hour.precipitation?.raw} '
      '바람 ${hour.compass?.label} ${hour.windSpeed?.raw}');
}
for (final day in forecast.days) {
  print('${day.date} 최저 ${day.low} 최고 ${day.high}');
}
final now = forecast.at(DateTime.now());
```

It follows the October 2026 KMA guide:

- `PCP`, `RN1`, and `SNO` come as classes, read by `KmaAmount`: `강수없음` and
  `0` are none, `1mm 미만` is below 1, `6.2mm` exact, `30.0~50.0mm` a range,
  and `50.0mm 이상` at least 50. `value` is set only for exact amounts.
- The village forecast covers five days. Its last day (글피 for slots up to
  14:00, 그글피 for 17:00 and later) is three-hourly, and there `PCP`, `SNO`,
  and `WSD` are qualitative codes: `KmaAmount.intensity` says, for example,
  `KmaIntensity.moderateRain` (3 to 15 mm an hour). `KmaForecastHour.isExtended`
  marks those hours.
- Values of `+900` and above or `-900` and below mean "missing", such as over
  the sea; they become `null`.
- The ultra short forecast sends `POP` since June 23, 2026.
- `TMN` and `TMX` go to `days`; only slots published at 02:00 carry today's
  low.
- `compass` turns `VEC` into one of 16 points with the guide's formula.
- Nowcast rows (`getUltraSrtNcst`, `obsrValue`) work too, placed at their base
  time.

### Public holidays

`KoreanHolidays` reads the Korea Astronomy and Space Science Institute's
special day service (한국천문연구원 특일 정보). Apply for it on data.go.kr
first.

```dart
final holidays = KoreanHolidays(client);

for (final day in await holidays.restDays(2026, month: 10)) {
  print('${day.date} ${day.name}');  // 2026-10-03 개천절, ...
}
print(await holidays.isRestDay(DateTime(2026, 10, 9)));  // true

await holidays.nationalDays(2026);   // includes 제헌절, isHoliday false
await holidays.solarTerms(2026);     // 24절기, with time and sunLongitude
```

Leave out `month` for the whole year. The institute adds each year about two
years ahead and temporary holidays within a day of being declared.

### Air quality

`AirKorea` reads real-time measurements from AirKorea (한국환경공단 에어코리아
대기오염정보), with version 1.5 of the operations: PM10, PM2.5, their 24-hour
averages and one-hour grades, and the gases.

```dart
final air = AirKorea(client);

final [latest, ...] = await air.station('종로구');
print('PM10 ${latest.pm10} ㎍/㎥ ${latest.pm10Grade?.label}');  // 35 보통
print('PM2.5 ${latest.pm25} ${latest.pm25Grade1h?.label}');

final seoul = await air.province('서울');  // latest at every station
```

`-` and empty values become `null`, and the `*Flag` fields say why
(점검및교정, 장비점검, ...). `dataTime` is the UTC instant; AirKorea writes
midnight as `24:00`.

### Business registration status

`BusinessStatusService` asks the National Tax Service whether a business is
open, suspended, or closed (국세청 사업자등록정보 상태조회). Apply for it on
data.go.kr first; it lives on `api.odcloud.kr` and takes POST requests.

```dart
final service = BusinessStatusService(client);

final [status] = await service.check(['124-81-00998']);
print(status.state?.label);    // 계속사업자
print(status.taxType?.label);  // 부가가치세 일반과세자
print(status.closedOn);        // null

BusinessStatusService.isValidNumber('124-81-00998');  // checksum, offline
```

More than 100 numbers are split into several requests. A number the service
does not know comes back with `isRegistered` false.

### Retries, timeouts, and POST

Every attempt has `timeout` (10 seconds by default). A request still running
then is aborted through `package:http`'s `Abortable` requests, so the
connection does not stay open. Failures that can pass on their own are
retried: dropped connections, timeouts, HTTP 5xx, the portal's `05` (service
timeout), and HTTP 429 rate limits. Key and parameter errors fail at once,
and so does the portal's `22`, which means the daily quota is used up.

```dart
final client = DataGoKrClient(
  serviceKey: key,
  timeout: const Duration(seconds: 5),
  retry: const RetryPolicy(
    maxRetries: 3,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 8),
  ),
);
// Or never retry: retry: RetryPolicy.none.
```

`post` sends a JSON body and is retried only when marked `idempotent`:

```dart
final response = await client.post(
  'https://api.odcloud.kr/api/nts-businessman/v1/status',
  json: {'b_no': ['1248100998']},
  idempotent: true,
);
```

## Limitations

- Rows are flat maps. XML values come back as strings, and nested elements
  inside an `<item>` are not expanded: their text is joined.
- Bodies are decoded in the declared charset when `dart:convert` knows it,
  otherwise as UTF-8. EUC-KR is not supported.
- A newly issued key can take time to activate, and the portal then answers
  `unauthorized_key`.
- Services differ in parameter names and casing (`LAWD_CD`, `base_date`), so
  pass what each service's document says.
- The portal counts requests per service per day; `paginate` uses one request
  per page, and each retry is another request.
- `KoreanHolidays`, `AirKorea`, and `BusinessStatusService` were checked
  against each service's published specification, not with an approved key;
  the raw row stays in `raw` for fields they do not model.

## Flutter example

```dart
FutureBuilder<DataGoKrResponse>(
  future: client.get(endpoint, query: {'nx': 60, 'ny': 127}),
  builder: (context, snapshot) {
    final rows = snapshot.data?.items;
    if (rows == null) return const LinearProgressIndicator();
    return ListView(
      children: [for (final row in rows) ListTile(title: Text('$row'))],
    );
  },
)
```

## Related packages

Pure Dart clients from the same publisher:

| Package | What it covers |
| --- | --- |
| [neis_plus](https://pub.dev/packages/neis_plus) | NEIS school data: schools, meals, timetables, academic calendars |
| [rdap](https://pub.dev/packages/rdap) | Domain registration data, including Korean `.kr` and `.한국` names |

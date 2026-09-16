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
shapes, and paging.

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
- **Paging.** `paginate` follows `totalCount` and yields every row.
- **No data is not an error.** `resultCode` `03` returns an empty page.
- **KMA grid cells.** `KmaGrid` converts a latitude and longitude to the
  `nx`/`ny` cell that weather services ask for.
- **KMA publish times.** `KmaBaseTime.latest` picks a `base_date` and
  `base_time` the service has actually published, and `KmaSky`,
  `KmaPrecipitation`, and `kmaCategory` turn the codes into readable values.

## Platform support

Pure Dart on top of `package:http` and `package:xml`: Dart VM, Flutter on
Android, iOS, Windows, macOS, Linux, and the web. The portal sends CORS
headers, so browser calls work — but a key in a web build is visible to anyone,
so put it behind your own backend for public sites.

## Installation

```yaml
dependencies:
  data_go_kr: ^0.0.1
```

Get a service key from [data.go.kr](https://www.data.go.kr) by applying for the
service you want, then use the **decoded** key.

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
| `unauthorized_key` | Key unknown, expired, blocked, or IP not registered |
| `rate_limit` | Request quota exceeded |
| `invalid_parameter` | Missing or invalid request parameter |
| `unknown_service` | No such service for that endpoint |
| `service_error` | The service reported an internal failure |
| `http_error` | The request did not reach the service |
| `timeout` | The service did not answer in time |
| `invalid_response` | The answer was not usable JSON or XML |

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
20, and 23, ten minutes after each slot; the nowcast every hour at 40 minutes
past; the ultra short forecast every hour at 45 minutes past. `KmaBaseTime`
picks the newest published slot, in Korea Standard Time whatever the device
time zone is.

```dart
final base = KmaBaseTime.latest(KmaService.village);

final forecast = await client.get(
  'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst',
  query: {
    'base_date': base.date,  // 20260916
    'base_time': base.time,  // 0500
    'nx': cell.nx,
    'ny': cell.ny,
  },
);

for (final row in forecast.items) {
  final category = '${row['category']}';
  final value = '${row['fcstValue']}';
  print(switch (category) {
    'SKY' => '하늘: ${KmaSky.fromCode(value)?.label}',
    'PTY' => '강수: ${KmaPrecipitation.fromCode(value)?.label}',
    _ => '${kmaCategory(category)?.label ?? category}: '
        '$value${kmaCategory(category)?.unit ?? ''}',
  });
}
```

## Limitations

- Rows are flat maps. XML values come back as strings, and nested elements
  inside an `<item>` are not expanded.
- A newly issued key can take time to activate, and the portal then answers
  `unauthorized_key`.
- Services differ in parameter names and casing (`LAWD_CD`, `base_date`,
  `pageNo` vs `page`), so pass what each service's document says.
- The portal counts requests per service per day; `paginate` uses one request
  per page.

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

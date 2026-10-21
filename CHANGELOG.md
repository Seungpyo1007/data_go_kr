## 0.0.3

* Fix `paginate` repeating the first page on `api.odcloud.kr`, which pages with
  `page` and `perPage`. Requests to that host now use those names, and no
  longer get `dataType`.
* Fix `paginate` reading one page over and over when `query` sets `pageNo`;
  paging parameters in `query` are replaced, and a `numOfRows` there is used
  as the page size. A paging parameter set to `null` gets its default.
* Error messages now carry the portal's reason and description, for example
  `SERVICE_KEY_IS_NOT_REGISTERED_ERROR (등록되지 않은 서비스키)`, and older
  gateways that answer `SERVICE ERROR` report the reason instead.
* Fix the HTTP status being ignored for unreadable bodies: 401 and 403 are
  `unauthorized_key`, 429 `rate_limit`, and other failures, such as a 503 HTML
  page, `http_error`.
* Map more reason codes: `21` (suspended key) and odcloud `-401` (missing key)
  to `unauthorized_key`, odcloud `-3` to `unknown_service`, `05` to `timeout`,
  and `04` to `http_error`.
* Read JSON that sends `header` and `body` without a `response` wrapper.
* Fix XML rows: only the `<item>` children of `<items>` are rows, and page
  fields such as `totalCount` are no longer read from inside a row.
* Fix TLS errors such as `HandshakeException` escaping as themselves; every
  failure is now a `DataGoKrException`.
* Trim spaces and line breaks around the service key, and throw an
  `ArgumentError` when the endpoint or `query` carries a `serviceKey` too.
* Keep `returnType` instead of adding `dataType`, and decode bodies in their
  declared charset when `dart:convert` supports it.
* `KmaBaseTime.latest` returns the nowcast ten minutes past the hour instead
  of 40, following KMA's October 2026 guide.
* Fix the README and example appending `mm` to precipitation values that
  already include it, such as `1mm 미만`. Correct the browser (CORS) notes and
  the install version, and link related packages.

## 0.0.2

* Add `KmaBaseTime.latest`, which returns the newest `base_date` and
  `base_time` a KMA service has published. Each service has its own schedule:
  the village forecast publishes eight times a day ten minutes after each slot,
  the nowcast every hour at 40 minutes past, and the ultra short forecast every
  hour at 45 minutes past. Times are computed in Korea Standard Time whatever
  the device time zone is.
* Add `KmaSky` and `KmaPrecipitation` for the `SKY` and `PTY` codes, including
  the codes only the ultra short forecast uses.
* Add `kmaCategory`, which describes category codes such as `TMP` and `POP`
  with their Korean label and unit.

## 0.0.1

* Initial release.
* `DataGoKrClient.get` calls any data.go.kr open API, percent-encodes the
  service key, adds paging parameters, and parses both JSON and XML answers.
* `DataGoKrClient.paginate` streams rows across pages, following `totalCount`.
* `DataGoKrResponse` exposes rows, `totalCount`, `pageNo`, `numOfRows`, and the
  service result code.
* `DataGoKrException` reports `unauthorized_key`, `rate_limit`,
  `invalid_parameter`, `unknown_service`, `service_error`, `http_error`,
  `timeout`, and `invalid_response`, covering the portal's XML and JSON error
  envelopes as well as the `api.odcloud.kr` shape.
* `KmaGrid` converts a latitude and longitude to the weather forecast grid
  cell (`nx`, `ny`) that KMA services require, and back to the cell center.

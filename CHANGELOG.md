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

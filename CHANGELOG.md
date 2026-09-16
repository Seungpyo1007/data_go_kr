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

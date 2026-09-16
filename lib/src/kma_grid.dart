import 'dart:math' as math;

/// A cell of the Korea Meteorological Administration forecast grid.
///
/// KMA forecast services take a grid cell (`nx`, `ny`) instead of a latitude
/// and longitude. The country is covered by 5 km cells on a Lambert conformal
/// conic projection, 149 columns by 253 rows.
///
/// ```dart
/// final cell = KmaGrid.fromLatLon(37.5665, 126.9780); // Seoul City Hall
/// print('${cell.nx} ${cell.ny}'); // 60 127
/// ```
class KmaGrid {
  /// Creates a grid cell from its coordinates.
  const KmaGrid(this.nx, this.ny);

  /// Converts a latitude and longitude to the cell that contains it.
  ///
  /// Throws an [ArgumentError] when [lat] or [lon] is outside the globe.
  /// Coordinates outside Korea return a cell outside the published grid, which
  /// services answer with no data.
  factory KmaGrid.fromLatLon(double lat, double lon) {
    if (lat.isNaN || lat < -90 || lat > 90) {
      throw ArgumentError.value(lat, 'lat', 'Must be between -90 and 90.');
    }
    if (lon.isNaN || lon < -180 || lon > 180) {
      throw ArgumentError.value(lon, 'lon', 'Must be between -180 and 180.');
    }

    final ra =
        _re * _sf / math.pow(math.tan(_quarterPi + lat * _degrad / 2), _sn);
    var theta = lon * _degrad - _olon;
    if (theta > math.pi) theta -= 2 * math.pi;
    if (theta < -math.pi) theta += 2 * math.pi;
    theta *= _sn;

    return KmaGrid(
      (ra * math.sin(theta) + _xo + 0.5).floor(),
      (_ro - ra * math.cos(theta) + _yo + 0.5).floor(),
    );
  }

  /// Grid column, 1 to 149 inside Korea.
  final int nx;

  /// Grid row, 1 to 253 inside Korea.
  final int ny;

  /// Whether the cell is inside the published grid.
  bool get isInKorea => nx >= 1 && nx <= 149 && ny >= 1 && ny <= 253;

  /// The latitude and longitude at the center of this cell.
  ({double lat, double lon}) toLatLon() {
    final xn = nx - _xo;
    final yn = _ro - ny + _yo;
    var ra = math.sqrt(xn * xn + yn * yn);
    if (_sn < 0) ra = -ra;

    final alat =
        2 * math.atan(math.pow(_re * _sf / ra, 1 / _sn)) - _quarterPi * 2;
    final double theta;
    if (xn == 0) {
      theta = 0;
    } else if (yn == 0) {
      theta = xn < 0 ? -math.pi / 2 : math.pi / 2;
    } else {
      theta = math.atan2(xn, yn);
    }

    return (lat: alat / _degrad, lon: (theta / _sn + _olon) / _degrad);
  }

  @override
  bool operator ==(Object other) =>
      other is KmaGrid && other.nx == nx && other.ny == ny;

  @override
  int get hashCode => Object.hash(nx, ny);

  @override
  String toString() => 'KmaGrid($nx, $ny)';
}

// Projection constants published by KMA: 5 km grid, standard parallels at 30N
// and 60N, origin at 126E 38N, and origin cell (43, 136).
const _degrad = math.pi / 180;
const _quarterPi = math.pi / 4;
const _gridKm = 5.0;
const _earthRadiusKm = 6371.00877;
const _xo = 43;
const _yo = 136;

final double _re = _earthRadiusKm / _gridKm;
final double _olon = 126.0 * _degrad;
final double _sn = _computeSn();
final double _sf = _computeSf();
final double _ro = _computeRo();

double _computeSn() {
  const slat1 = 30.0 * _degrad;
  const slat2 = 60.0 * _degrad;
  final ratio =
      math.tan(_quarterPi + slat2 / 2) / math.tan(_quarterPi + slat1 / 2);
  return math.log(math.cos(slat1) / math.cos(slat2)) / math.log(ratio);
}

double _computeSf() {
  const slat1 = 30.0 * _degrad;
  final scale =
      math.pow(math.tan(_quarterPi + slat1 / 2), _sn) * math.cos(slat1) / _sn;
  return scale.toDouble();
}

double _computeRo() {
  const olat = 38.0 * _degrad;
  return _re * _sf / math.pow(math.tan(_quarterPi + olat / 2), _sn);
}

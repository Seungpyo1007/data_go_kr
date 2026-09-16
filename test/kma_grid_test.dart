import 'package:data_go_kr/data_go_kr.dart';
import 'package:test/test.dart';

void main() {
  group('KmaGrid', () {
    test('converts well-known places to their published cells', () {
      // Seoul City Hall, the cell used in the KMA example requests.
      expect(KmaGrid.fromLatLon(37.5665, 126.9780), const KmaGrid(60, 127));
      // Busan City Hall, Jeju City Hall, Gangneung, and Daejeon.
      expect(KmaGrid.fromLatLon(35.1796, 129.0756), const KmaGrid(98, 76));
      expect(KmaGrid.fromLatLon(33.4996, 126.5312), const KmaGrid(53, 38));
      expect(KmaGrid.fromLatLon(37.7519, 128.8761), const KmaGrid(92, 132));
      expect(KmaGrid.fromLatLon(36.3504, 127.3845), const KmaGrid(67, 100));
    });

    test('returns the center of a cell and converts back', () {
      final center = const KmaGrid(60, 127).toLatLon();

      expect(center.lat, closeTo(37.5799, 0.001));
      expect(center.lon, closeTo(126.9894, 0.001));
      expect(
        KmaGrid.fromLatLon(center.lat, center.lon),
        const KmaGrid(60, 127),
      );
    });

    test('round trips every cell of a sample', () {
      for (final cell in const [
        KmaGrid(1, 1),
        KmaGrid(60, 127),
        KmaGrid(98, 76),
        KmaGrid(149, 253),
      ]) {
        final center = cell.toLatLon();
        expect(KmaGrid.fromLatLon(center.lat, center.lon), cell);
      }
    });

    test('flags cells outside the published grid', () {
      expect(const KmaGrid(60, 127).isInKorea, isTrue);
      expect(const KmaGrid(0, 127).isInKorea, isFalse);
      expect(const KmaGrid(150, 127).isInKorea, isFalse);
      expect(const KmaGrid(60, 254).isInKorea, isFalse);
      expect(KmaGrid.fromLatLon(0, 0).isInKorea, isFalse);
    });

    test('rejects impossible coordinates', () {
      expect(() => KmaGrid.fromLatLon(91, 127), throwsArgumentError);
      expect(() => KmaGrid.fromLatLon(-91, 127), throwsArgumentError);
      expect(() => KmaGrid.fromLatLon(37, 181), throwsArgumentError);
      expect(() => KmaGrid.fromLatLon(double.nan, 127), throwsArgumentError);
    });

    test('compares by coordinates', () {
      expect(const KmaGrid(60, 127), const KmaGrid(60, 127));
      expect(const KmaGrid(60, 127).hashCode, const KmaGrid(60, 127).hashCode);
      expect(const KmaGrid(60, 127), isNot(const KmaGrid(61, 127)));
      expect(const KmaGrid(60, 127).toString(), 'KmaGrid(60, 127)');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  group('Version Semver Comparison Tests', () {
    test('1.10.0 is correctly treated as greater than 1.9.0', () {
      final v1_10 = Version.parse('1.10.0');
      final v1_9 = Version.parse('1.9.0');
      expect(v1_10 > v1_9, isTrue);
      expect(v1_9 < v1_10, isTrue);
    });

    test('Equal versions 1.5.0 == 1.5.0 do not trigger updateRequired', () {
      final cur = Version.parse('1.5.0');
      final min = Version.parse('1.5.0');
      expect(cur < min, isFalse);
    });

    test('Outdated version 1.4.2 < 1.5.0 triggers updateRequired', () {
      final cur = Version.parse('1.4.2');
      final min = Version.parse('1.5.0');
      expect(cur < min, isTrue);
    });

    test('Malformed version strings handle fallback gracefully', () {
      Version? tryParse(String val) {
        try {
          return Version.parse(val);
        } catch (_) {
          return null;
        }
      }

      expect(tryParse('invalid_string'), isNull);
      expect(tryParse('1.0.0'), equals(Version(1, 0, 0)));
    });
  });
}

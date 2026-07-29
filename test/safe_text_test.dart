import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/util/safe_text.dart';

void main() {
  test('repairs unpaired surrogates and preserves valid pairs', () {
    expect(sanitizeUtf16('a\uD800b\uDC00c'), 'a\uFFFDb\uFFFDc');
    expect(sanitizeUtf16('look \uD83D\uDC57'), 'look 👗');
  });

  test('repairs strings recursively without changing other values', () {
    final result =
        sanitizeUtf16Deep({
              'cards': [
                {'title': 'Office \uD800 look', 'count': 3},
              ],
              'success': true,
            })
            as Map;

    expect(result['cards'][0]['title'], 'Office \uFFFD look');
    expect(result['cards'][0]['count'], 3);
    expect(result['success'], isTrue);
    expect(result, isA<Map<String, dynamic>>());
    expect(result['cards'][0], isA<Map<String, dynamic>>());
  });

  test('truncates by scalar value without splitting emoji', () {
    expect(truncateSafeText('123👗567', 4, suffix: '…'), '123👗…');
    expect(truncateSafeText('short', 40, suffix: '…'), 'short');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';

void main() {
  test('account switch clears the previous wardrobe before a new fetch', () {
    expect(
      shouldClearWardrobeForAccountSwitchForTesting('user-a', 'user-b'),
      isTrue,
    );
    expect(
      shouldClearWardrobeForAccountSwitchForTesting('user-a', 'user-a'),
      isFalse,
    );
  });

  test('anonymous session invalidation clears the wardrobe immediately', () {
    expect(
      shouldClearWardrobeForSessionForTesting(null),
      isTrue,
    );
    expect(
      shouldClearWardrobeForSessionForTesting('user-a'),
      isFalse,
    );
  });
}

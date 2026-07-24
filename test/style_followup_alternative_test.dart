import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';

void main() {
  test('1 & 2. alternative-look phrases are detected', () {
    expect(isAlternativeLookPhrase('show me another look'), isTrue);
    expect(isAlternativeLookPhrase('more looks'), isTrue);
    expect(isAlternativeLookPhrase('try another'), isTrue);
    expect(isAlternativeLookPhrase('give me another option'), isTrue);
    expect(isAlternativeLookPhrase('something else'), isTrue);
    expect(isAlternativeLookPhrase('show me another wardrobe look'), isTrue);
  });

  test('3. ordinary style questions are not detected', () {
    expect(isAlternativeLookPhrase('would this work for dinner?'), isFalse);
    expect(isAlternativeLookPhrase('make it more formal'), isFalse);
    expect(isAlternativeLookPhrase('suggest an outfit for party'), isFalse);
  });

  test('6. rendered item IDs are extracted from the carried style_state', () {
    final ids = renderedItemIdsFrom({
      'board_items': [
        {'item_id': 'a'},
        {'id': 'b'},
        {r'$id': 'c'},
        {'name': 'no-id'},
      ],
    });
    expect(ids, containsAll(<String>['a', 'b', 'c']));
    expect(ids.length, 3); // the id-less item is dropped
  });

  test('4/5/7/8. routes through the structured path with the canonical action', () {
    final src =
        File('lib/widgets/ahvi_stylist_chat.dart').readAsStringSync();
    // (8) canonical action is sent
    expect(src, contains('action: isAlternativeLook'));
    expect(src, contains("'create_alternative_board'"));
    // (4/5) the carried style_state (occasion/source/items) is sent; the
    // backend derives occasion, source and item-ID exclusion from it
    expect(src, contains('styleState: _latestStyleState.isEmpty'));
    // (7) gated on an existing rendered board, NOT on board_id
    expect(src, contains('_latestStyleState.isNotEmpty'));
    expect(src, isNot(contains('isAlternativeLook &&\n          board_id')));
  });
}

// Works Well With must score against the COMPLETE wardrobe, and must never
// return a same-role garment.
//
// Both halves were real release findings on the current account:
//
//  * The wardrobe read used a bare Query.limit(100). The account holds 141
//    rows, so 41 items were invisible to the grid AND to everything fed from
//    _wardrobe, including PairingEngine.worksWellWith. wardrobe.dart now pages
//    with Query.cursorAfter; these tests pin the behaviour that depends on it.
//
//  * A same-role shirt was reported as a complementary result for a top. The
//    engine already excludes Tops->Tops (pairing_engine.dart _compatibleCategories),
//    and a read-only trace of all 141 live rows confirmed every category is
//    canonical, so the report came from a stale build. Pinned here so a future
//    change to the compatibility map cannot silently reintroduce it.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/pairing_engine.dart';

WardrobeItem _item(
  String id, {
  required String name,
  required String category,
  List<String> occasions = const [],
}) => WardrobeItem(
  id: id,
  name: name,
  cat: category,
  occasions: occasions,
);

void main() {
  test('a complementary item beyond index 100 is still reachable', () {
    final anchor = _item(
      'anchor',
      name: 'White Plain Top',
      category: 'Tops',
      occasions: const ['Work'],
    );

    // 130 filler tops keep the anchor's own bucket busy and push the only
    // complementary garment past the old 100-row truncation point.
    final pool = <WardrobeItem>[
      anchor,
      for (var i = 0; i < 130; i++)
        _item('filler-$i', name: 'Filler Top $i', category: 'Tops'),
      _item(
        'trousers-late',
        name: 'Black Night Trousers',
        category: 'Bottoms',
        occasions: const ['Work'],
      ),
    ];
    expect(pool.length, 132, reason: 'complementary item sits past index 100');

    final result = PairingEngine.worksWellWith(anchor, pool);
    expect(
      result.map((i) => i.id),
      contains('trousers-late'),
      reason:
          'an item beyond the old Query.limit(100) cap must still be pairable; '
          'if this fails the wardrobe read has been re-truncated',
    );
  });

  test('a Tops anchor never returns another Tops item', () {
    final anchor = _item(
      'anchor',
      name: 'White Plain Top',
      category: 'Tops',
      occasions: const ['Casual'],
    );
    final sameRole = _item(
      'same-role',
      name: 'White Textured Short Sleeve Shirt',
      category: 'Tops',
      occasions: const ['Casual'],
    );
    final bottom = _item(
      'bottom',
      name: 'White Pleated Trousers',
      category: 'Bottoms',
      occasions: const ['Casual'],
    );
    final shoe = _item(
      'shoe',
      name: 'Black And White Loafers',
      category: 'Footwear',
      occasions: const ['Casual'],
    );

    final ids = PairingEngine.worksWellWith(anchor, [
      anchor,
      sameRole,
      bottom,
      shoe,
    ]).map((i) => i.id).toSet();

    expect(
      ids,
      isNot(contains('same-role')),
      reason: 'a shirt is a Top; a Top must never complement a Top',
    );
    expect(ids, containsAll(<String>['bottom', 'shoe']));
  });

  test('sub_category wording does not override the canonical bucket', () {
    // "Trousers" as a sub-category must not demote the item out of Bottoms:
    // the live account has White Pleated Trousers stored exactly this way.
    final anchor = _item('anchor', name: 'White Plain Top', category: 'Tops');
    final trousers = _item(
      'trousers',
      name: 'White Pleated Trousers',
      category: 'Trousers',
    );
    final ids = PairingEngine.worksWellWith(anchor, [
      anchor,
      trousers,
    ]).map((i) => i.id);
    expect(ids, contains('trousers'));
  });
}

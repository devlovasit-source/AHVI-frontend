import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/pairing_engine.dart';

WardrobeItem _item(
  String id, {
  required String name,
  required String category,
  List<String> occasions = const [],
  String notes = '',
}) => WardrobeItem(
  id: id,
  name: name,
  cat: category,
  occasions: occasions,
  notes: notes,
);

void main() {
  test('Works Well With excludes non-fashion wardrobe rows', () {
    final selected = _item(
      'selected',
      name: 'Navy Blazer',
      category: 'outerwear',
      occasions: ['Work'],
    );
    final result = PairingEngine.worksWellWith(selected, [
      selected,
      _item(
        'charger',
        name: 'Phone Charger',
        category: 'accessory',
        occasions: ['Work'],
      ),
      _item(
        'loafers',
        name: 'Black Loafers',
        category: 'footwear',
        occasions: ['Work'],
      ),
    ]);

    expect(result.map((item) => item.id), ['loafers']);
  });

  test('non-fashion anchor returns no pairing results', () {
    final charger = _item('charger', name: 'Phone Charger', category: 'accessory');
    final shirt = _item('shirt', name: 'White Shirt', category: 'top');

    final result = PairingEngine.worksWellWith(charger, [charger, shirt]);

    expect(result, isEmpty);
  });

  test('mixed wardrobe rejects obvious non-fashion items', () {
    final shirt = _item('shirt', name: 'White Shirt', category: 'top');
    final nonFashion = [
      _item('cable', name: 'USB Cable', category: 'accessory'),
      _item('power-bank', name: 'Power Bank', category: 'accessory'),
      _item('bottle', name: 'Water Bottle', category: 'accessory'),
      _item('laptop', name: 'Laptop', category: 'accessory'),
      _item('mouse', name: 'Computer Mouse', category: 'accessory'),
      _item('keyboard', name: 'Keyboard', category: 'accessory'),
      _item('remote', name: 'Remote', category: 'accessory'),
      _item('speaker', name: 'Speaker', category: 'accessory'),
    ];

    final result = PairingEngine.worksWellWith(shirt, [shirt, ...nonFashion]);

    expect(result, isEmpty);
  });

  test('real fashion accessories remain eligible', () {
    final dress = _item('dress', name: 'Black Dress', category: 'dresses');
    final accessories = [
      _item('watch', name: 'Black Watch', category: 'accessory'),
      _item('necklace', name: 'Gold Necklace', category: 'accessory'),
      _item('bag', name: 'Leather Handbag', category: 'accessory'),
      _item('belt', name: 'Tan Belt', category: 'accessory'),
      _item('sunglasses', name: 'Sunglasses', category: 'accessory'),
      _item('earrings', name: 'Silver Earrings', category: 'accessory'),
    ];

    final result = PairingEngine.worksWellWith(dress, [dress, ...accessories]);
    final resultIds = result.map((i) => i.id).toSet();

    for (final expected in accessories) {
      expect(resultIds, contains(expected.id));
    }
  });

  test('broad substring words do not falsely reject real fashion names', () {
    final bottleGreenShirt = _item(
      'shirt',
      name: 'Bottle Green Shirt',
      category: 'top',
    );
    final boxPleatSkirt = _item(
      'skirt',
      name: 'Box Pleat Skirt',
      category: 'bottom',
    );
    final wireFrameSunglasses = _item(
      'sunglasses',
      name: 'Wire Frame Sunglasses',
      category: 'accessory',
    );

    final shirtResults = PairingEngine.worksWellWith(bottleGreenShirt, [
      bottleGreenShirt,
      boxPleatSkirt,
      wireFrameSunglasses,
    ]);
    final skirtResults = PairingEngine.worksWellWith(boxPleatSkirt, [
      bottleGreenShirt,
      boxPleatSkirt,
      wireFrameSunglasses,
    ]);
    final sunglassesResults = PairingEngine.worksWellWith(
      wireFrameSunglasses,
      [bottleGreenShirt, boxPleatSkirt, wireFrameSunglasses],
    );

    expect(shirtResults.map((i) => i.id), contains('skirt'));
    expect(shirtResults.map((i) => i.id), contains('sunglasses'));
    expect(skirtResults.map((i) => i.id), contains('shirt'));
    expect(sunglassesResults.map((i) => i.id), contains('shirt'));
  });

  test('non-fashion phrase in notes does not reject a fashion item', () {
    final shirt = _item('shirt', name: 'White Shirt', category: 'top');
    final jacket = _item(
      'jacket',
      name: 'Travel Jacket',
      category: 'outerwear',
      notes: 'Has a water bottle pocket for travel.',
    );

    final result = PairingEngine.worksWellWith(shirt, [shirt, jacket]);

    expect(result.map((i) => i.id), contains('jacket'));
  });
}

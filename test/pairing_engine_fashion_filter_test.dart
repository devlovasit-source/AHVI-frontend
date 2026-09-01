import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/pairing_engine.dart';

WardrobeItem _item(
  String id, {
  required String name,
  required String category,
  List<String> occasions = const [],
}) => WardrobeItem(id: id, name: name, cat: category, occasions: occasions);

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
}

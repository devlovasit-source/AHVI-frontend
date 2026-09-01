import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/pairing_engine.dart';

WardrobeItem makeItem({
  required String id,
  required String name,
  required String cat,
  List<String> occasions = const ['Casual'],
  String notes = '',
}) {
  return WardrobeItem(
    id: id,
    name: name,
    cat: cat,
    occasions: occasions,
    notes: notes,
  );
}

void main() {
  group('PairingEngine worksWellWith fashion admission', () {
    test('Phone Charger is rejected even when category is Accessories', () {
      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final charger = makeItem(
        id: 'charger',
        name: 'Phone Charger',
        cat: 'Accessories',
      );

      final results = PairingEngine.worksWellWith(shirt, [shirt, charger]);

      expect(results.any((result) => result.id == 'charger'), isFalse);
    });

    test('Black Watch remains eligible as an accessory', () {
      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final watch = makeItem(
        id: 'watch',
        name: 'Black Watch',
        cat: 'Accessories',
      );

      final results = PairingEngine.worksWellWith(shirt, [shirt, watch]);

      expect(results.any((result) => result.id == 'watch'), isTrue);
    });

    test('Gold Necklace remains eligible as an accessory', () {
      final dress = makeItem(id: 'dress', name: 'Black Dress', cat: 'Dresses');

      final necklace = makeItem(
        id: 'necklace',
        name: 'Gold Necklace',
        cat: 'Accessories',
      );

      final results = PairingEngine.worksWellWith(dress, [dress, necklace]);

      expect(results.any((result) => result.id == 'necklace'), isTrue);
    });

    test('mixed wardrobe excludes non-fashion items and keeps valid items', () {
      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final charger = makeItem(
        id: 'charger',
        name: 'Phone Charger',
        cat: 'Accessories',
      );

      final cable = makeItem(
        id: 'cable',
        name: 'USB Cable',
        cat: 'Accessories',
      );

      final powerBank = makeItem(
        id: 'power-bank',
        name: 'Power Bank',
        cat: 'Accessories',
      );

      final watch = makeItem(
        id: 'watch',
        name: 'Black Watch',
        cat: 'Accessories',
      );

      final belt = makeItem(id: 'belt', name: 'Tan Belt', cat: 'Accessories');

      final trousers = makeItem(
        id: 'trousers',
        name: 'Black Trousers',
        cat: 'Bottoms',
      );

      final shoes = makeItem(id: 'shoes', name: 'White Shoes', cat: 'Footwear');

      final results = PairingEngine.worksWellWith(shirt, [
        shirt,
        charger,
        cable,
        powerBank,
        watch,
        belt,
        trousers,
        shoes,
      ]);

      final resultIds = results.map((result) => result.id).toSet();

      expect(resultIds, isNot(contains('charger')));
      expect(resultIds, isNot(contains('cable')));
      expect(resultIds, isNot(contains('power-bank')));

      expect(resultIds, contains('watch'));
      expect(resultIds, contains('belt'));
      expect(resultIds, contains('trousers'));
      expect(resultIds, contains('shoes'));
    });

    test('handbags and jewelry remain eligible', () {
      final dress = makeItem(id: 'dress', name: 'Black Dress', cat: 'Dresses');

      final bag = makeItem(
        id: 'bag',
        name: 'Leather Handbag',
        cat: 'Accessories',
      );

      final earrings = makeItem(
        id: 'earrings',
        name: 'Silver Earrings',
        cat: 'Accessories',
      );

      final sunglasses = makeItem(
        id: 'sunglasses',
        name: 'Sunglasses',
        cat: 'Accessories',
      );

      final results = PairingEngine.worksWellWith(dress, [
        dress,
        bag,
        earrings,
        sunglasses,
      ]);

      final resultIds = results.map((result) => result.id).toSet();

      expect(resultIds, contains('bag'));
      expect(resultIds, contains('earrings'));
      expect(resultIds, contains('sunglasses'));
    });

    test('occasion/category normalization remains unchanged', () {
      final shirt = makeItem(
        id: 'shirt',
        name: 'Training Shirt',
        cat: 'top',
        occasions: const ['office', 'upload_occasion_workout', 'Gym'],
      );

      expect(PairingEngine.normalizeCategory(shirt.cat), 'Tops');

      expect(PairingEngine.bestFor(shirt), ['Work', 'Sport', 'Gym']);
    });
  });
}

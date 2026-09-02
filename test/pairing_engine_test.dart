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

    test('non-fashion anchor returns no pairing results', () {
      final charger = makeItem(
        id: 'charger',
        name: 'Phone Charger',
        cat: 'Accessories',
      );

      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final results = PairingEngine.worksWellWith(charger, [charger, shirt]);

      expect(results, isEmpty);
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

      final bottle = makeItem(
        id: 'bottle',
        name: 'Water Bottle',
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
        bottle,
        watch,
        belt,
        trousers,
        shoes,
      ]);

      final resultIds = results.map((result) => result.id).toSet();

      expect(resultIds, isNot(contains('charger')));
      expect(resultIds, isNot(contains('cable')));
      expect(resultIds, isNot(contains('power-bank')));
      expect(resultIds, isNot(contains('bottle')));

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

    test('valid fashion names are not rejected by broad words', () {
      final shirt = makeItem(
        id: 'shirt',
        name: 'Bottle Green Shirt',
        cat: 'Tops',
      );

      final skirt = makeItem(
        id: 'skirt',
        name: 'Box Pleat Skirt',
        cat: 'Bottoms',
      );

      final sunglasses = makeItem(
        id: 'sunglasses',
        name: 'Wire Frame Sunglasses',
        cat: 'Accessories',
      );

      final shirtResults = PairingEngine.worksWellWith(shirt, [
        shirt,
        skirt,
        sunglasses,
      ]);

      final skirtResults = PairingEngine.worksWellWith(skirt, [
        shirt,
        skirt,
        sunglasses,
      ]);

      final sunglassesResults = PairingEngine.worksWellWith(sunglasses, [
        shirt,
        skirt,
      ]);

      expect(shirtResults.map((item) => item.id), contains('skirt'));

      expect(skirtResults.map((item) => item.id), contains('shirt'));

      expect(sunglassesResults.map((item) => item.id), contains('shirt'));
    });

    test('plural non-fashion variants are rejected', () {
      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final batteries = makeItem(
        id: 'batteries',
        name: 'Batteries',
        cat: 'Accessories',
      );

      final boxes = makeItem(
        id: 'boxes',
        name: 'Storage Boxes',
        cat: 'Accessories',
      );

      final results = PairingEngine.worksWellWith(shirt, [
        shirt,
        batteries,
        boxes,
      ]);

      final resultIds = results.map((item) => item.id).toSet();

      expect(resultIds, isNot(contains('batteries')));
      expect(resultIds, isNot(contains('boxes')));
    });

    test('single-word non-fashion names are rejected', () {
      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final nonFashionItems = [
        makeItem(id: 'charger', name: 'Charger', cat: 'Accessories'),
        makeItem(id: 'cable', name: 'Cable', cat: 'Accessories'),
        makeItem(id: 'adapter', name: 'Adapter', cat: 'Accessories'),
        makeItem(id: 'laptop', name: 'Laptop', cat: 'Accessories'),
        makeItem(id: 'camera', name: 'Camera', cat: 'Accessories'),
        makeItem(id: 'keyboard', name: 'Keyboard', cat: 'Accessories'),
        makeItem(id: 'mouse', name: 'Mouse', cat: 'Accessories'),
        makeItem(id: 'speaker', name: 'Speaker', cat: 'Accessories'),
        makeItem(id: 'remote', name: 'Remote', cat: 'Accessories'),
      ];

      final results = PairingEngine.worksWellWith(shirt, [
        shirt,
        ...nonFashionItems,
      ]);

      final resultIds = results.map((item) => item.id).toSet();

      for (final item in nonFashionItems) {
        expect(resultIds, isNot(contains(item.id)));
      }
    });

    test('non-fashion phrase in notes does not reject a fashion item', () {
      final shirt = makeItem(id: 'shirt', name: 'White Shirt', cat: 'Tops');

      final jacket = makeItem(
        id: 'jacket',
        name: 'Travel Jacket',
        cat: 'Outerwear',
        notes: 'Has a water bottle pocket for travel.',
      );

      final results = PairingEngine.worksWellWith(shirt, [shirt, jacket]);

      expect(results.any((item) => item.id == 'jacket'), isTrue);
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

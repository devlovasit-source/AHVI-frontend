import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/pairing_engine.dart';

WardrobeItem _item(
  String id, {
  required String name,
  required String cat,
  List<String> occasions = const [],
}) =>
    WardrobeItem(id: id, name: name, cat: cat, occasions: occasions);

void main() {
  group('canonicalizeOccasion — semantic aliases', () {
    test('office -> Work', () {
      expect(canonicalizeOccasion('office'), 'Work');
    });

    test('work -> Work', () {
      expect(canonicalizeOccasion('work'), 'Work');
    });

    test('date -> Dinner', () {
      expect(canonicalizeOccasion('date'), 'Dinner');
    });

    test('dinner -> Dinner', () {
      expect(canonicalizeOccasion('dinner'), 'Dinner');
    });

    test('is case-insensitive (Casual)', () {
      expect(canonicalizeOccasion('CASUAL'), 'Casual');
      expect(canonicalizeOccasion('Casual'), 'Casual');
      expect(canonicalizeOccasion('casual'), 'Casual');
    });

    test('Wedding/Festive/Party/Travel are preserved', () {
      expect(canonicalizeOccasion('wedding'), 'Wedding');
      expect(canonicalizeOccasion('festive'), 'Festive');
      expect(canonicalizeOccasion('party'), 'Party');
      expect(canonicalizeOccasion('travel'), 'Travel');
    });

    test('upload_occasion_ prefix is stripped before aliasing, same as humanizeOccasion', () {
      expect(canonicalizeOccasion('upload_occasion_office'), 'Work');
      expect(canonicalizeOccasion('upload_occasion_everyday'), 'Everyday');
    });

    test('unknown snake_case values humanize instead of being discarded', () {
      expect(canonicalizeOccasion('client_meeting'), 'Client Meeting');
      expect(canonicalizeOccasion('business_lunch'), 'Business Lunch');
      // Never returns an empty/raw token for a non-empty input.
      expect(canonicalizeOccasion('client_meeting'), isNot('client_meeting'));
    });

    test('private-wear tokens format plainly and never alias to a public chip', () {
      const publicChips = {'Work', 'Dinner', 'Travel', 'Party', 'Festive', 'Wedding'};
      for (final token in ['home', 'private', 'lounge', 'base layer']) {
        final result = canonicalizeOccasion(token);
        expect(publicChips.contains(result), isFalse, reason: token);
      }
    });
  });

  group('review chip preselection uses canonicalizeOccasion', () {
    const chips = [
      'Everyday',
      'Casual',
      'Work',
      'Dinner',
      'Travel',
      'Sport',
      'Party',
      'Festive',
      'Wedding',
    ];

    bool chipActive(List<String> occasions, String chip) => occasions.any(
          (o) => canonicalizeOccasion(o).toLowerCase() == chip.toLowerCase(),
        );

    test('backend office activates only the Work chip', () {
      expect(chipActive(['office'], 'Work'), isTrue);
      for (final other in chips.where((c) => c != 'Work')) {
        expect(chipActive(['office'], other), isFalse, reason: other);
      }
    });

    test('backend date activates only the Dinner chip', () {
      expect(chipActive(['date'], 'Dinner'), isTrue);
      for (final other in chips.where((c) => c != 'Dinner')) {
        expect(chipActive(['date'], other), isFalse, reason: other);
      }
    });

    test('backend casual/wedding/festive/party/travel already worked and still do', () {
      expect(chipActive(['casual'], 'Casual'), isTrue);
      expect(chipActive(['wedding'], 'Wedding'), isTrue);
      expect(chipActive(['festive'], 'Festive'), isTrue);
      expect(chipActive(['party'], 'Party'), isTrue);
      expect(chipActive(['travel'], 'Travel'), isTrue);
    });

    test('private-wear occasions activate no public review chip', () {
      for (final chip in chips) {
        expect(chipActive(['Home', 'Private', 'Lounge'], chip), isFalse, reason: chip);
      }
    });
  });

  group('PairingEngine.worksWellWith occasion overlap is case/vocabulary safe', () {
    test('casual overlaps Casual', () {
      final item = _item('a', name: 'Test Top', cat: 'Tops', occasions: ['casual']);
      final matches = _item(
        'b',
        name: 'Test Bottom Match',
        cat: 'Bottoms',
        occasions: ['Casual'],
      );
      final noOverlap = _item(
        'c',
        name: 'Test Bottom Plain',
        cat: 'Bottoms',
        occasions: const [],
      );

      final result = PairingEngine.worksWellWith(item, [matches, noOverlap]);

      expect(result.first.id, 'b');
    });

    test('office overlaps Work', () {
      final item = _item('a', name: 'Test Top', cat: 'Tops', occasions: ['office']);
      final matches = _item(
        'b',
        name: 'Test Bottom Match',
        cat: 'Bottoms',
        occasions: ['Work'],
      );
      final noOverlap = _item(
        'c',
        name: 'Test Bottom Plain',
        cat: 'Bottoms',
        occasions: const [],
      );

      final result = PairingEngine.worksWellWith(item, [matches, noOverlap]);

      expect(result.first.id, 'b');
    });

    test('date overlaps Dinner', () {
      final item = _item('a', name: 'Test Top', cat: 'Tops', occasions: ['date']);
      final matches = _item(
        'b',
        name: 'Test Bottom Match',
        cat: 'Bottoms',
        occasions: ['Dinner'],
      );
      final noOverlap = _item(
        'c',
        name: 'Test Bottom Plain',
        cat: 'Bottoms',
        occasions: const [],
      );

      final result = PairingEngine.worksWellWith(item, [matches, noOverlap]);

      expect(result.first.id, 'b');
    });
  });
}

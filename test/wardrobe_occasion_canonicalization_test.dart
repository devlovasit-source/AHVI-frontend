import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/wardrobe.dart';

void main() {
  group('canonicalizeOccasion', () {
    test('maps backend tokens whose wording differs from the review chips', () {
      expect(canonicalizeOccasion('office'), 'Work');
      expect(canonicalizeOccasion('work'), 'Work');
      expect(canonicalizeOccasion('date'), 'Dinner');
      expect(canonicalizeOccasion('dinner'), 'Dinner');
    });

    test(
      'is a no-op (beyond formatting) for tokens that already match a chip',
      () {
        expect(canonicalizeOccasion('casual'), 'Casual');
        expect(canonicalizeOccasion('travel'), 'Travel');
        expect(canonicalizeOccasion('party'), 'Party');
        expect(canonicalizeOccasion('festive'), 'Festive');
        expect(canonicalizeOccasion('wedding'), 'Wedding');
      },
    );

    test('is case-insensitive on the raw input', () {
      expect(canonicalizeOccasion('Office'), 'Work');
      expect(canonicalizeOccasion('WEDDING'), 'Wedding');
    });

    test('strips the upload_occasion_ prefix before aliasing', () {
      expect(canonicalizeOccasion('upload_occasion_office'), 'Work');
      expect(canonicalizeOccasion('upload_occasion_festive'), 'Festive');
    });

    test(
      'falls through to humanizeOccasion formatting for unmapped values',
      () {
        // These are intentionally NOT guessed at — private-wear and validator
        // tokens outside the review-chip vocabulary get plain formatting only.
        expect(canonicalizeOccasion('client_meeting'), 'Client Meeting');
        expect(canonicalizeOccasion('business_lunch'), 'Business Lunch');
        expect(canonicalizeOccasion('home'), 'Home');
        expect(canonicalizeOccasion('private'), 'Private');
        expect(canonicalizeOccasion('lounge'), 'Lounge');
      },
    );
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

    test('backend-derived office activates the Work chip', () {
      expect(chipActive(['office'], 'Work'), isTrue);
      for (final other in chips.where((c) => c != 'Work')) {
        expect(chipActive(['office'], other), isFalse, reason: other);
      }
    });

    test('backend-derived date activates the Dinner chip', () {
      expect(chipActive(['date'], 'Dinner'), isTrue);
    });

    test(
      'backend-derived casual/wedding/festive/party/travel already worked and still do',
      () {
        expect(chipActive(['casual'], 'Casual'), isTrue);
        expect(chipActive(['wedding'], 'Wedding'), isTrue);
        expect(chipActive(['festive'], 'Festive'), isTrue);
        expect(chipActive(['party'], 'Party'), isTrue);
        expect(chipActive(['travel'], 'Travel'), isTrue);
      },
    );
  });
}

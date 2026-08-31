import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/util/occasion_normalizer.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/pairing_engine.dart';

void main() {
  test('known backend occasion aliases humanize to preset labels', () {
    expect(humanizeOccasion('upload_occasion_everyday'), 'Everyday');
    expect(humanizeOccasion('office'), 'Work');
    expect(humanizeOccasion('work'), 'Work');
    expect(humanizeOccasion('upload_occasion_workout'), 'Sport');
  });

  test('unknown values remain custom and human-readable', () {
    expect(humanizeOccasion('upload_occasion_loungewear'), 'Loungewear');
    expect(isPresetOccasion('upload_occasion_loungewear'), isFalse);
    expect(humanizeOccasion('Gym'), 'Gym');
    expect(humanizeOccasion('Beach'), 'Beach');
    expect(isPresetOccasion('Gym'), isFalse);
  });

  test(
    'semantic matching and toggle remove aliases instead of duplicating',
    () {
      expect(occasionMatches('office', 'Work'), isTrue);
      expect(toggleOccasion(['office'], 'Work'), isEmpty);
      expect(toggleOccasion(['office', 'Gym'], 'Work'), ['Gym']);
      expect(toggleOccasion(['office', 'Gym'], 'Dinner'), [
        'office',
        'Gym',
        'Dinner',
      ]);
    },
  );

  test('PairingEngine uses the same occasion labels as Wardrobe Review', () {
    final item = WardrobeItem(
      id: 'item-1',
      name: 'Training shoes',
      cat: 'Footwear',
      occasions: const ['office', 'upload_occasion_workout', 'Gym'],
    );
    expect(PairingEngine.bestFor(item), ['Work', 'Sport', 'Gym']);
  });
}

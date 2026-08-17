import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';

void main() {
  String _wearOutfitSource() {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    return source.substring(
      source.indexOf('Future<void> _wearOutfit'),
      source.indexOf('/// Notify HomeCardSummaryProvider'),
    );
  }

  test('tapping Wear Today sends a backend wearToday request', () {
    final section = _wearOutfitSource();

    expect(section, contains('BackendService().wearToday('));
    expect(section, contains('await BackendService().wearToday('));
  });

  test('exact board id is passed to wearToday', () {
    final section = _wearOutfitSource();

    expect(section, contains("boardId: (outfit['id'] ?? '').toString()"));
  });

  test('exact item ids are passed to wearToday', () {
    final section = _wearOutfitSource();

    expect(section, contains('itemIds: ids'));
    expect(section, contains('_wearableItemIds(outfit)'));
  });

  test('success marks UI worn only after backend confirms', () {
    final section = _wearOutfitSource();

    final ok = section.indexOf('final ok = await BackendService().wearToday(');
    final markWorn = section.indexOf(
      'setState(() => _wornOutfitId = outfitId)',
    );

    expect(ok, greaterThanOrEqualTo(0));
    // The worn state is set after the request is awaited, not before it.
    expect(markWorn, greaterThan(ok));
  });

  test('failure does not mark the outfit worn locally', () {
    final section = _wearOutfitSource();
    final failureBranch = section.substring(
      section.indexOf('if (!ok) {'),
      section.indexOf('setState(() => _wornOutfitId = outfitId);'),
    );

    expect(failureBranch, contains('daily_wear_toast_update_failed'));
    expect(failureBranch, contains('return;'));
    expect(failureBranch, isNot(contains('_wornOutfitId')));
  });

  test('wear request is skipped entirely when no wearable ids are found', () {
    final section = _wearOutfitSource();

    final ids = section.indexOf('final ids = _wearableItemIds(outfit);');
    final guard = section.indexOf('if (ids == null) return;');
    final call = section.indexOf('await BackendService().wearToday(');

    expect(ids, greaterThanOrEqualTo(0));
    expect(guard, greaterThan(ids));
    expect(call, greaterThan(guard));
  });

  test('same button cannot fire two concurrent wear requests', () {
    final section = _wearOutfitSource();

    expect(section, contains('if (_isRecordingWear) return;'));
    expect(section, contains('setState(() => _isRecordingWear = true)'));
    expect(section, contains('setState(() => _isRecordingWear = false)'));
  });

  test('Home is only notified after a confirmed wear', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final wearOutfit = source.substring(
      source.indexOf('Future<void> _wearOutfit'),
      source.indexOf('/// Notify HomeCardSummaryProvider'),
    );

    final markWorn = wearOutfit.indexOf(
      'setState(() => _wornOutfitId = outfitId)',
    );
    final pushHome = wearOutfit.indexOf('_pushWearToHome(outfit);');

    expect(markWorn, greaterThanOrEqualTo(0));
    expect(pushHome, greaterThan(markWorn));
  });

  test('Wear Today button widget and sizing are unchanged by this feature', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final optCard = source.substring(
      source.indexOf('Widget _buildOptCard'),
      source.indexOf('Widget _buildOptCard') + 9000,
    );

    // Same button widget, same 115px card height, same disabled-when-worn
    // wiring — this feature only changes when _wornOutfitId flips, not the
    // widget tree or layout constraints around it.
    expect(optCard, contains('height: 115'));
    expect(optCard, contains("isWorn ? null : () => _wearOutfit(outfitId)"));
  });

  group('wearableItemIdsForOutfit source precedence', () {
    test('demo outfits without any real item ids are never recorded', () {
      expect(wearableItemIdsForOutfit({'id': 'o1'}), isNull);
      expect(wearableItemIdsForOutfit({'id': 'o1', 'items': []}), isNull);
    });

    test('malformed or missing item identity does not record a fake wear', () {
      final ids = wearableItemIdsForOutfit({
        'id': 'o1',
        'items': [
          {'id': 'a'},
          {'name': 'displayed item without id'},
        ],
      });

      expect(ids, isNull);
    });

    test('A: empty items falls through to used_wardrobe_items', () {
      final ids = wearableItemIdsForOutfit({
        'id': 'o1',
        'items': [],
        'used_wardrobe_items': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      });

      expect(ids, unorderedEquals(['a', 'b']));
    });

    test(
      'B: populated but partial items fails safely without falling back',
      () {
        final ids = wearableItemIdsForOutfit({
          'id': 'o1',
          'items': [
            {'id': 'a'},
            {'name': 'displayed item without id'},
          ],
          'used_wardrobe_items': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        });

        // Must NOT fall back to used_wardrobe_items just because items is
        // present-but-broken — that could record a different outfit than
        // what was actually displayed.
        expect(ids, isNull);
      },
    );

    test('C: valid populated items wins over used_wardrobe_items', () {
      final ids = wearableItemIdsForOutfit({
        'id': 'o1',
        'items': [
          {'id': 'a'},
        ],
        'used_wardrobe_items': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      });

      expect(ids, equals(['a']));
    });

    test('D: legacy item_ids still works when items sources are absent', () {
      final ids = wearableItemIdsForOutfit({
        'id': 'o1',
        'item_ids': ['a', 'b', 'a', ' ', ''],
      });

      expect(ids, unorderedEquals(['a', 'b']));
    });
  });
}

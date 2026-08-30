import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';

void main() {
  group('Daily Wear Board Item Precedence Tests', () {
    test('board_items takes top precedence over items', () {
      final outfit = {
        'items': [
          {'id': 'item_raw', 'name': 'Raw Top', 'image_url': 'http://raw.png'}
        ],
        'board_items': [
          {'id': 'board_1', 'name': 'Enriched Top', 'image_url': 'http://board.png'}
        ],
      };

      final items = DailyWearScreen.firstNonEmptyBoardItems(outfit);
      expect(items.length, 1);
      expect(items.first['id'], 'board_1');
    });

    test('empty items list does not mask board_items', () {
      final outfit = {
        'items': <dynamic>[],
        'board_items': [
          {'id': 'board_2', 'name': 'Enriched Pants', 'image_url': 'http://pants.png'}
        ],
      };

      final items = DailyWearScreen.firstNonEmptyBoardItems(outfit);
      expect(items.length, 1);
      expect(items.first['id'], 'board_2');
    });

    test('composition_items used when board_items is missing/empty', () {
      final outfit = {
        'items': [
          {'id': 'item_raw', 'name': 'Raw Top', 'image_url': 'http://raw.png'}
        ],
        'board_items': <dynamic>[],
        'composition_items': [
          {'id': 'comp_1', 'name': 'Composition Dress', 'image_url': 'http://comp.png'}
        ],
      };

      final items = DailyWearScreen.firstNonEmptyBoardItems(outfit);
      expect(items.length, 1);
      expect(items.first['id'], 'comp_1');
    });

    test('used_wardrobe_items used when board_items and composition_items are empty', () {
      final outfit = {
        'items': [
          {'id': 'item_raw', 'name': 'Raw Top', 'image_url': 'http://raw.png'}
        ],
        'board_items': <dynamic>[],
        'composition_items': <dynamic>[],
        'used_wardrobe_items': [
          {'id': 'wardrobe_1', 'name': 'Wardrobe Shoes', 'image_url': 'http://shoes.png'}
        ],
      };

      final items = DailyWearScreen.firstNonEmptyBoardItems(outfit);
      expect(items.length, 1);
      expect(items.first['id'], 'wardrobe_1');
    });

    test('items fallback used only when higher priority lists are empty', () {
      final outfit = {
        'board_items': <dynamic>[],
        'composition_items': <dynamic>[],
        'used_wardrobe_items': <dynamic>[],
        'items': [
          {'id': 'item_fallback', 'name': 'Fallback Hat', 'image_url': 'http://hat.png'}
        ],
      };

      final items = DailyWearScreen.firstNonEmptyBoardItems(outfit);
      expect(items.length, 1);
      expect(items.first['id'], 'item_fallback');
    });
  });

  // NOTE: PR #41's own test file also included a second group covering
  // Daily Wear Share/Save/CTA wiring (_shareOutfit, _saveOutfitToBoards,
  // bookmark icons, _PressScaleButton). Those UI features were deliberately
  // NOT ported in this pass (see RC3 report) -- daily_wear.dart's Share/Save
  // buttons remain unwired pending a focused follow-up, since wiring them
  // correctly requires touching the same functions that also carry PR #41's
  // protected-contract violations (canonical chat routing, StyleBoardItem
  // parsing, board renderer, demo fallback). Only the already-shipped
  // precedence-helper group above reflects real ported code.
}

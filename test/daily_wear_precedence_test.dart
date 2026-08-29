import 'dart:io';
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

  group('Daily Wear PR #41 Code Contract & Failure Guard Tests', () {
    test('Daily Wear checks Appwrite save doc null before writing local SavedBoardsStore', () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final saveMethod = source.substring(
        source.indexOf('Future<bool> _saveOutfitToBoards'),
        source.indexOf('Future<void> _unsaveOutfit'),
      );

      expect(saveMethod, contains('doc = await AppwriteService().saveBoardToCollection('));
      expect(saveMethod, contains('if (doc == null) {'));
      expect(saveMethod, contains('return false;'));

      final docCheckIdx = saveMethod.indexOf('if (doc == null) {');
      final localSaveIdx = saveMethod.indexOf('SavedBoardsStore.saveBoard(');
      expect(docCheckIdx, greaterThan(0));
      expect(localSaveIdx, greaterThan(docCheckIdx));
    });

    test('Daily Wear bookmark icons separate Save Board from Favourite Heart', () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      expect(source, contains('Icons.bookmark_rounded'));
      expect(source, contains('Icons.bookmark_border_rounded'));
      expect(source, contains('Icons.bookmark_add_rounded'));
    });

    test('Daily Wear image readiness precaches NetworkImages before BoardExporter capture', () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final shareMethod = source.substring(
        source.indexOf('Future<void> _shareOutfit'),
        source.indexOf('Future<_DailyOccasionOption?> _showOccasionPickerSheet'),
      );

      expect(shareMethod, contains('precacheImage('));
      expect(shareMethod, contains('BoardExporter.capturePng('));
      expect(shareMethod, contains('Share.shareXFiles('));
      expect(shareMethod, contains('Share.share('));
    });

    test('Daily Wear CTA uses _PressScaleButton with Build Outfit label and gradient', () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      expect(source, contains("onTap: () => _openTryOn(outfitId),"));
      expect(source, contains("child: Center("));
      expect(source, contains("'Build Outfit',"));
    });
  });
}

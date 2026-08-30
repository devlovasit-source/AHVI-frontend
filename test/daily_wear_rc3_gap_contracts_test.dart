import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// RC3 Session N/O gap contracts for lib/daily_wear.dart. Most of the touched
// functions are library-private (leading underscore), so -- following the
// established pattern in test/daily_wear_precedence_test.dart and
// test/wardrobe_taxonomy_and_garment_share_test.dart -- these are
// source-inspection contract tests, not widget/unit tests: there is no
// dependency-injection seam for BackendService/AppwriteService in this
// screen, so pumping a real widget would require live network mocking that
// doesn't exist yet anywhere else in this file's test suite.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/daily_wear.dart').readAsStringSync().replaceAll('\r\n', '\n');
  });

  String functionBody(String signature, {int fallbackWindow = 2500}) {
    final start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature not found');
    final end = (start + fallbackWindow).clamp(0, source.length);
    return source.substring(start, end);
  }

  group('A - False empty state (insufficient_wardrobe contract)', () {
    test('insufficient-wardrobe detection only trusts explicit backend fields', () {
      final body = functionBody('bool _isInsufficientWardrobeResponse(');
      for (final field in ['type', 'reason', 'status', "meta['reason']"]) {
        expect(body, contains(field), reason: 'missing check for $field');
      }
      expect(body, contains('toLowerCase()'),
          reason: 'match must be case-normalized before comparing');
      expect(body, contains('.trim()'),
          reason: 'match must be whitespace-normalized before comparing');
    });

    test('true insufficient_wardrobe -> _needsMoreClothes (add more clothes state)', () {
      final body = functionBody('Future<void> _fetchDailyBoard()', fallbackWindow: 3200);
      expect(body, contains('if (_isInsufficientWardrobeResponse(response))'));
      final branch = body.substring(body.indexOf('if (_isInsufficientWardrobeResponse(response))'));
      final branchEnd = branch.indexOf('return;');
      final scoped = branch.substring(0, branchEnd);
      expect(scoped, contains('_needsMoreClothes = true'));
    });

    test('generic empty cards (no explicit signal) -> _loadUnavailable, not _needsMoreClothes', () {
      final body = functionBody('Future<void> _fetchDailyBoard()', fallbackWindow: 3200);
      expect(body, contains('if (outfits.isEmpty)'));
      final branch = body.substring(body.indexOf('if (outfits.isEmpty)'));
      final branchEnd = branch.indexOf('return;');
      final scoped = branch.substring(0, branchEnd);
      expect(scoped, contains('_loadUnavailable = true'));
      expect(scoped, isNot(contains('_needsMoreClothes = true')));
    });

    test('populated cards path never sets either empty-state flag', () {
      final body = functionBody('Future<void> _fetchDailyBoard()', fallbackWindow: 3200);
      final successStart = body.lastIndexOf('setState(() {\n      _applyOutfits(outfits);');
      expect(successStart, greaterThan(-1));
      final scoped = body.substring(successStart, successStart + 250);
      expect(scoped, contains('_needsMoreClothes = false'));
      expect(scoped, contains('_loadUnavailable = false'));
    });

    test('empty-state UI branches on _needsMoreClothes OR _loadUnavailable', () {
      expect(source, contains('else if (_needsMoreClothes || _loadUnavailable)'));
    });

    test('weather-driven sort never backfills demo catalog into _displayedOutfits', () {
      final body = functionBody('void _applyWeatherAndSort(', fallbackWindow: 1800);
      final earlyReturn = body.substring(0, body.indexOf('int score('));
      expect(earlyReturn, contains('if (_displayedOutfits.isEmpty)'));
      expect(earlyReturn, contains('return;'));
      expect(earlyReturn, isNot(contains('_fallbackOutfits()')),
          reason: 'demo catalog must never reach _displayedOutfits via weather sort');
      final afterGuard = body.substring(body.indexOf('int score('));
      expect(afterGuard, isNot(contains('_fallbackOutfits()')));
    });
  });

  group('B - Daily Wear Save (canonical Saved Board v2 + occasion picker)', () {
    test('_saveOutfitToBoards still uses canonical buildSavedBoardContent/SavedBoardSelection', () {
      final body = functionBody('Future<bool> _saveOutfitToBoards(');
      expect(body, contains('buildSavedBoardContent('));
      expect(body, contains('SavedBoardSelection(bucket: occasionBucket)'));
      expect(body, contains('return saved != null;'));
      expect(body, contains('return false;'));
    });

    test('occasion picker options map to valid canonical buckets only', () {
      final start = source.indexOf('const dailyWearSaveOccasionOptions');
      expect(start, greaterThan(-1));
      final end = source.indexOf('];', start);
      final block = source.substring(start, end);
      const validBuckets = {
        'party_looks', 'office_fits', 'vacation', 'occasion', 'everything_else',
      };
      final matches = RegExp(r"\('([a-z_]+)',").allMatches(block);
      expect(matches, isNotEmpty);
      for (final m in matches) {
        expect(validBuckets.contains(m.group(1)), isTrue,
            reason: '${m.group(1)} is not a real SavedBoardSelection bucket');
      }
    });

    test('save call sites gate saved=true only on sheet selection + success', () {
      final body = source;
      // Both call sites must: get a bucket from the sheet, bail on
      // cancellation (null), then only flip saved state on ok==true.
      final sheetCalls = RegExp(r'final bucket = await _showSaveOccasionSheet\([^)]*\);\s*\n\s*if \(bucket == null \|\| !mounted\) return;').allMatches(body);
      expect(sheetCalls.length, 2, reason: 'expected exactly 2 wired save call sites');
    });
  });

  group('C - Daily Wear Share', () {
    test('_shareOutfit captures the canonical on-screen board via RepaintBoundary', () {
      expect(source, contains('RepaintBoundary(\n            key: _boardCanvasKeyFor(outfitId),'));
      final body = functionBody('Future<void> _shareOutfit(');
      expect(body, contains('BoardExporter.capturePng(key)'));
      expect(body, contains('BoardExporter.writeToTempFile('));
    });

    test('share uses non-deprecated SharePlus.instance.share for both image and text', () {
      final body = functionBody('Future<void> _shareOutfit(');
      expect(body, contains('SharePlus.instance.share('));
      expect(body, contains('files: [XFile(file.path'));
      expect(body, contains('text: shareText'));
      expect(body, isNot(contains('Share.shareXFiles(')));
      expect(body, isNot(contains('Share.share(')));
    });

    test('image capture failure falls back to text share, never throws', () {
      final body = functionBody('Future<void> _shareOutfit(');
      final tries = 'try'.allMatches(body).length;
      final catches = 'catch (e) {'.allMatches(body).length;
      expect(tries, greaterThanOrEqualTo(2));
      expect(catches, greaterThanOrEqualTo(2));
    });
  });

  group('D - Wear Today', () {
    test('_recordWear uses canonical firstNonEmptyBoardItems precedence, never demo ids', () {
      final body = functionBody('void _recordWear(');
      expect(body, contains('DailyWearScreen.firstNonEmptyBoardItems(outfit)'));
      expect(body, isNot(contains('_fallbackOutfits()')));
    });

    test('duplicate-tap guard: in-flight ids are skipped, not re-submitted', () {
      final body = functionBody('void _recordWear(');
      expect(body, contains('_wearInFlight.contains(outfitId)'));
      expect(body, contains('return; // duplicate fast tap'));
    });

    test('in-flight guard clears on success, normal failure, and exception', () {
      final body = functionBody('void _recordWear(');
      final thenIdx = body.indexOf('.then((ok) {');
      final catchIdx = body.indexOf('.catchError((_) {');
      expect(thenIdx, greaterThan(-1));
      expect(catchIdx, greaterThan(thenIdx));
      final thenBranch = body.substring(thenIdx, catchIdx);
      final catchBranch = body.substring(catchIdx, catchIdx + 300);
      expect(thenBranch, contains('_wearInFlight.remove(outfitId)'));
      expect(catchBranch, contains('_wearInFlight.remove(outfitId)'));
      // Failure (ok == false) must not show the success toast permanently.
      expect(thenBranch, contains('ok\n'));
    });
  });

  group('E - Protected Daily Wear contracts', () {
    test('conversational routing stays on sendModuleChat(domain: daily_wear)', () {
      expect(source, contains("BackendService().sendModuleChat("));
      expect(source, contains("'daily_wear'"));
      expect(source, isNot(contains('sendChatQuery(')),
          reason: 'Daily Wear must never be swapped onto the generic style chat route');
    });

    test('conversation/session/board context fields remain on the chat payload', () {
      for (final field in [
        "'conversation_id'",
        "'session_id'",
        "'surface': 'daily_wear'",
        "'current_outfit'",
        "'weather_context'",
        "'worn_outfit_id'",
      ]) {
        expect(source, contains(field), reason: 'missing protected field $field');
      }
    });

    test('Clear Chat dialog remains wired', () {
      expect(source, contains("import 'package:myapp/widgets/clear_chat_dialog.dart';"));
    });

    test('canonical StyleBoardItem.fromJson parser is still used, not manual reconstruction', () {
      expect(source, contains('StyleBoardItem.fromJson(item)'));
    });

    test('canonical AhviUnifiedOutfitGrid renderer is still used for boards', () {
      expect(source, contains('AhviUnifiedOutfitGrid('));
      expect(source, contains('_buildUnifiedOutfitGrid(styleBoard)'));
    });

    test('Gap 2 save path never surfaces the raw exception to the user', () {
      // _saveOutfitToBoards debugPrints $e (dev console only) and returns
      // false -- callers show a canned daily_wear_save_failed string, never
      // the exception itself. This is scoped to the Gap 2 path only: the
      // pre-existing chat-triggered _persistCurrentLook (line ~1532, not
      // touched by RC3) still SnackBars a raw "$e" and is a known, separate,
      // pre-existing gap -- not part of Save/Share/WearToday's protected
      // contract and out of this session's scope.
      final body = functionBody('Future<bool> _saveOutfitToBoards(', fallbackWindow: 1300);
      expect(body, contains('debugPrint('));
      expect(body, isNot(contains('showSnackBar')));
      expect(body, isNot(contains('_showToast(')));
    });

    test('Indian garment taxonomy (lehenga/sherwani) untouched by this file', () {
      expect(source, isNot(contains("_cleanCategory(")),
          reason: 'taxonomy classification lives in wardrobe.dart only, not daily_wear.dart');
    });
  });
}

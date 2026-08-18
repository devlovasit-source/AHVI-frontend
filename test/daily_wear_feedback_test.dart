import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/daily_wear.dart';

void main() {
  String _source() => File('lib/daily_wear.dart').readAsStringSync();

  String _section(String source, String startMarker, String endMarker) {
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start);
    return source.substring(start, end);
  }

  String _notForMeSource() => _section(
    _source(),
    'Future<void> _notForMe',
    'Future<void> _changeIt',
  );

  String _changeItSource() => _section(
    _source(),
    'Future<void> _changeIt',
    'Future<String?> _pickItemToChange',
  );

  group('rawItemEntriesForOutfit source precedence', () {
    test('demo outfits without any real items are never usable', () {
      expect(rawItemEntriesForOutfit({'id': 'o1'}), isNull);
      expect(rawItemEntriesForOutfit({'id': 'o1', 'items': []}), isNull);
    });

    test('malformed populated items fails safely, no fallback', () {
      final items = rawItemEntriesForOutfit({
        'id': 'o1',
        'items': [
          {'id': 'a', 'name': 'Shirt'},
          {'name': 'displayed item without id'},
        ],
        'used_wardrobe_items': [
          {'id': 'a', 'name': 'Shirt'},
          {'id': 'b', 'name': 'Pants'},
        ],
      });

      expect(items, isNull);
    });

    test('valid populated items returns full maps, not just ids', () {
      final items = rawItemEntriesForOutfit({
        'id': 'o1',
        'items': [
          {'id': 'a', 'name': 'Shirt', 'category': 'top'},
        ],
      });

      expect(items, hasLength(1));
      expect(items!.first['name'], 'Shirt');
      expect(items.first['category'], 'top');
    });

    test('empty items falls through to used_wardrobe_items', () {
      final items = rawItemEntriesForOutfit({
        'id': 'o1',
        'items': [],
        'used_wardrobe_items': [
          {'id': 'a', 'name': 'Shirt'},
        ],
      });

      expect(items, hasLength(1));
      expect(items!.first['id'], 'a');
    });

    test('legacy item_ids wraps bare strings as minimal maps', () {
      final items = rawItemEntriesForOutfit({
        'id': 'o1',
        'item_ids': ['a', 'b', ''],
      });

      expect(items, hasLength(2));
      expect(items!.map((e) => e['id']), containsAll(['a', 'b']));
    });
  });

  group('Not for me', () {
    test('sends outfit-level dislike feedback with exact identity', () {
      final section = _notForMeSource();

      expect(section, contains("action: 'dislike'"));
      expect(section, contains('itemIds: ids'));
      expect(section, contains("occasion: (outfit['occasion'] ?? '').toString()"));
      expect(section, contains('await BackendService().sendBoardFeedback('));
    });

    test('validates canonical identity before sending, never guesses', () {
      final section = _notForMeSource();

      final ids = section.indexOf('final ids = wearableItemIdsForOutfit(outfit);');
      final guard = section.indexOf('if (ids == null) return;');
      final send = section.indexOf('await BackendService().sendBoardFeedback(');

      expect(ids, greaterThanOrEqualTo(0));
      expect(guard, greaterThan(ids));
      expect(send, greaterThan(guard));
    });

    test('in-flight guard prevents concurrent duplicate submissions', () {
      final section = _notForMeSource();

      expect(section, contains('if (_feedbackInFlightIds.contains(outfitId)) return;'));
      expect(section, contains('_feedbackInFlightIds.add(outfitId)'));
      expect(section, contains('_feedbackInFlightIds.remove(outfitId)'));
    });

    test('failure does not fake a learned/advanced state', () {
      final section = _notForMeSource();
      final failureBranch = section.substring(
        section.indexOf('if (!ok) {'),
        section.indexOf('_showToast(AppLocalizations.t(context, \'daily_wear_toast_not_for_me\'));'),
      );

      expect(failureBranch, contains('daily_wear_toast_update_failed'));
      expect(failureBranch, contains('return;'));
      expect(failureBranch, isNot(contains('_displayedOutfits.removeWhere')));
    });

    test('success advances by removing the rejected outfit from view', () {
      final section = _notForMeSource();

      final ok = section.indexOf('final ok = await BackendService().sendBoardFeedback(');
      final advance = section.indexOf('_displayedOutfits.removeWhere(');

      expect(ok, greaterThanOrEqualTo(0));
      expect(advance, greaterThan(ok));
    });

    test('B: falls back to the existing fetch path only when the board would otherwise be empty', () {
      final section = _notForMeSource();

      final advance = section.indexOf('_displayedOutfits.removeWhere(');
      final emptyCheck = section.indexOf('if (_displayedOutfits.isEmpty && !_isLoading) {');
      final refresh = section.indexOf('await _fetchDailyBoard();');

      expect(advance, greaterThanOrEqualTo(0));
      // Emptiness is checked AFTER the removal, on the post-removal state —
      // not a pre-check that could fire from a different reason.
      expect(emptyCheck, greaterThan(advance));
      expect(refresh, greaterThan(emptyCheck));
      // No new/second recommendation API — reuses the existing initial-load path.
      expect(section, isNot(contains('BackendService().getDailyBoard(')));
    });

    test('A: refresh is gated behind emptiness, so a remaining preloaded outfit skips it', () {
      final section = _notForMeSource();
      // The refresh call is nested inside the isEmpty guard, not unconditional —
      // when another outfit remains after removal, _fetchDailyBoard is skipped.
      // Between the guard and the call there must be nothing but the guard's
      // own opening brace/comment — no other branch/condition in between.
      final guardLine = 'if (_displayedOutfits.isEmpty && !_isLoading) {';
      final guardIdx = section.indexOf(guardLine);
      final refreshIdx = section.indexOf('await _fetchDailyBoard();');
      final between = section.substring(guardIdx + guardLine.length, refreshIdx);

      expect(guardIdx, greaterThanOrEqualTo(0));
      expect(refreshIdx, greaterThan(guardIdx));
      expect(between, isNot(contains('}')));
      expect(between, isNot(contains('if (')));
    });

    test('C: board is untouched until feedback is durably confirmed', () {
      final section = _notForMeSource();
      // Nothing before the `ok` result — no optimistic removal, no fetch —
      // touches _displayedOutfits.
      final preConfirm = section.substring(0, section.indexOf('if (!mounted) return;'));
      expect(preConfirm, isNot(contains('_displayedOutfits')));
    });
  });

  group('Not for me — real board mutability (regression for on-device crash)', () {
    // Reproduces the exact production crash: a live Daily Board fetch
    // (_normalizeDailyBoardCards) hands back a FIXED-LENGTH list
    // (.toList(growable: false)) — asserted here from source directly so
    // this test breaks if that producer's growability assumption changes
    // without the assignment-site fix below being revisited too.
    test('_normalizeDailyBoardCards still returns a fixed-length list (the hazard this guards against)', () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final section = source.substring(
        source.indexOf('List<Map<String, dynamic>> _normalizeDailyBoardCards'),
        source.indexOf('bool _isInsufficientWardrobeResponse'),
      );
      expect(section, contains('.toList(growable: false)'));
    });

    test('_applyOutfits materializes a growable copy before assigning _displayedOutfits', () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final section = source.substring(
        source.indexOf('void _applyOutfits'),
        source.indexOf('Map<String, dynamic> _outfitById'),
      );
      expect(
        section,
        contains('_displayedOutfits = List<Map<String, dynamic>>.from(outfits);'),
      );
    });

    test('a fixed-length board list survives the exact _notForMe/_changeIt mutations that crashed on device', () {
      // Mirrors what _normalizeDailyBoardCards really produces: fixed-length.
      final fixedLengthBoard = <Map<String, dynamic>>[
        {'id': 'o1', 'items': []},
        {'id': 'o2', 'items': []},
      ].toList(growable: false);
      expect(() => fixedLengthBoard.removeWhere((o) => o['id'] == 'o1'), throwsUnsupportedError);

      // The fix applied in _applyOutfits: wrap in List.from(...) before it
      // ever becomes _displayedOutfits.
      final growableCopy = List<Map<String, dynamic>>.from(fixedLengthBoard);

      // _notForMe's exact mutation (daily_wear.dart:1295):
      growableCopy.removeWhere((o) => (o['id'] ?? '').toString() == 'o1');
      expect(growableCopy, hasLength(1));
      expect(growableCopy.single['id'], 'o2');

      // _changeIt's exact mutation (daily_wear.dart index-assign) also
      // still works on the same growable copy:
      final idx = growableCopy.indexWhere((o) => o['id'] == 'o2');
      growableCopy[idx] = {...growableCopy[idx], 'items': ['shoe-3']};
      expect(growableCopy.single['items'], ['shoe-3']);

      // And the single-remaining-card path: rejecting the last card leaves
      // an empty (but still growable/mutable) list, never a crash.
      growableCopy.removeWhere((o) => (o['id'] ?? '').toString() == 'o2');
      expect(growableCopy, isEmpty);
    });
  });

  group('Change it', () {
    test('exact old item id is resolved from user selection, never guessed', () {
      final section = _changeItSource();

      expect(section, contains('final oldItemId = await _pickItemToChange(items);'));
      expect(section, contains('if (oldItemId == null || !mounted) return;'));
    });

    test('calls the exact change-item backend method with from/board identity', () {
      final section = _changeItSource();

      expect(section, contains('await BackendService().changeOutfitItem('));
      expect(section, contains('boardId: outfitId,'));
      expect(section, contains('oldItemId: oldItemId,'));
      expect(section, contains('items: items,'));
    });

    test('never sends a client-picked candidate pool — backend sources eligible replacements from the canonical wardrobe', () {
      final section = _changeItSource();

      expect(section, isNot(contains('candidateItems')));
      expect(section, isNot(contains('_changeItCandidatePool')));
    });

    test('failed mutation does not update the displayed board', () {
      final section = _changeItSource();
      final failureBranch = section.substring(
        section.indexOf("final success = result['success'] == true;"),
        section.indexOf('final data ='),
      );

      expect(failureBranch, contains('daily_wear_toast_change_it_failed'));
      expect(failureBranch, contains('return;'));
      expect(failureBranch, isNot(contains('_displayedOutfits[idx]')));
    });

    test('cancelled selection (no item picked) never calls the backend', () {
      final section = _changeItSource();

      final pick = section.indexOf('final oldItemId = await _pickItemToChange(items);');
      final guard = section.indexOf('if (oldItemId == null || !mounted) return;');
      final call = section.indexOf('await BackendService().changeOutfitItem(');

      expect(pick, greaterThanOrEqualTo(0));
      expect(guard, greaterThan(pick));
      expect(call, greaterThan(guard));
    });

    test('in-flight guard prevents concurrent duplicate change requests', () {
      final section = _changeItSource();

      expect(section, contains('if (_changeItemInFlightIds.contains(outfitId)) return;'));
      expect(section, contains('_changeItemInFlightIds.add(outfitId)'));
      expect(section, contains('_changeItemInFlightIds.remove(outfitId)'));
    });
  });

  group('Shuffle contract (DailyWear has no shuffle affordance)', () {
    test('sendBoardFeedback is only ever called from _notForMe', () {
      final source = _source();

      // DailyWear's only "show more" mechanism is the already-fetched
      // options list and the hero carousel's manual swipe/arrow paging.
      // Proving every call site of sendBoardFeedback lives inside
      // _notForMe's own body (not carousel paging, not _wearOutfit, not
      // anywhere else) proves swiping/paging can never be mistaken for an
      // explicit rejection.
      final totalCalls = 'sendBoardFeedback('.allMatches(source).length;
      final callsInsideNotForMe =
          'sendBoardFeedback('.allMatches(_notForMeSource()).length;

      expect(totalCalls, greaterThan(0));
      expect(callsInsideNotForMe, totalCalls);
    });
  });

  group('Regression: Wear Today unaffected', () {
    test('_wearOutfit still confirms via backend before marking worn', () {
      final source = _source();
      final wearSection = _section(
        source,
        'Future<void> _wearOutfit',
        '/// Notify HomeCardSummaryProvider',
      );

      expect(wearSection, contains('await BackendService().wearToday('));
      expect(wearSection, contains("setState(() => _wornOutfitId = outfitId)"));
    });
  });

  group('Action UX', () {
    test('Not for me and Change it use Flutter icons, never emoji', () {
      final source = _source();

      expect(source, contains('Icons.thumb_down_alt_outlined'));
      expect(source, contains('Icons.checkroom_outlined'));
      // Never the shuffle/refresh-shaped icon, and never the old emoji.
      expect(source, isNot(contains("Icons.autorenew")));
      expect(source, isNot(contains("Icons.loop")));
      expect(source, isNot(contains("_smallIcon('🚫'")));
      expect(source, isNot(contains("_smallIcon('🔁'")));
    });

    test('action buttons expose a Tooltip and Semantics label, not just an icon', () {
      final source = _source();
      final helper = _section(
        source,
        'Widget _smallActionIcon',
        'Widget _smallShare',
      );

      expect(helper, contains('Tooltip('));
      expect(helper, contains('message: label'));
      expect(helper, contains('Semantics('));
      expect(helper, contains('label: label'));
    });

    test('labels come from the existing localization keys, not new literals', () {
      final source = _source();

      expect(source, contains("AppLocalizations.t(context, 'daily_wear_not_for_me')"));
      expect(source, contains("AppLocalizations.t(context, 'daily_wear_change_it')"));
    });
  });

  group('Feedback logging', () {
    test('logs FAIL_STATUS (not a bare SENT) on non-2xx and on network error', () {
      final source = File('lib/services/backend_service.dart').readAsStringSync();
      final section = source.substring(
        source.indexOf('Future<bool> sendBoardFeedback'),
        source.indexOf('Future<Map<String, dynamic>> changeOutfitItem'),
      );

      expect(section, contains('AHVI_BOARD_FEEDBACK_FAIL_STATUS'));
      final sentIdx = section.indexOf("debugPrint('AHVI_BOARD_FEEDBACK_SENT");
      final successCheckIdx = section.indexOf('if (success) {');
      expect(successCheckIdx, greaterThanOrEqualTo(0));
      expect(sentIdx, greaterThan(successCheckIdx));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Daily Wear conversational Style uses canonical continuity contract',
    () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final request = source.substring(
        source.indexOf('Future<void> _callBackendStylist'),
        source.indexOf('void _speakMessage'),
      );

      expect(request, contains('BackendService().sendModuleChat('));
      expect(request, contains("domain: 'daily_wear'"));
      expect(request, isNot(contains("domain: 'style'")));
      expect(request, contains('message: userText'));
      expect(
        request,
        contains('chatHistory: List<Map<String, String>>.from(history)'),
      );
      expect(request, contains("'conversation_id': _currentSessionId"));
      expect(request, contains("'session_id': _currentSessionId"));
      expect(request, contains("'surface': 'daily_wear'"));
      expect(
        request,
        contains("'current_outfit': Map<String, dynamic>.from(currentOutfit)"),
      );
      expect(request, contains("'weather_context': _weatherContext"));
      expect(request, isNot(contains('BackendService().sendChatQuery(')));
      expect(request, isNot(contains("'Current outfit:")));
    },
  );

  test('Daily Board generation retains the style domain', () {
    final source = File('lib/services/backend_service.dart').readAsStringSync();
    final request = source.substring(
      source.indexOf('Future<Map<String, dynamic>?> getDailyBoard'),
      source.indexOf('// --- ACCOUNT & PROFILE ---'),
    );

    expect(request, contains("domain: 'style'"));
    expect(request, contains("'request': 'daily_board'"));
  });

  test('Daily Wear saves use canonical Saved Board v2 content', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final saveSection = source.substring(
      source.indexOf('Future<void> _persistCurrentLook'),
      source.indexOf('void _toggleMic'),
    );

    expect(saveSection, contains('buildSavedBoardContent('));
    expect(saveSection, contains("bucket: 'everything_else'"));
    expect(saveSection, contains("originalOccasion: 'daily'"));
    expect(saveSection, contains('_savedDailyWearItems(board)'));
    expect(saveSection, contains('content: content'));
    for (final deprecated in [
      'outfitDescription:',
      'emoji:',
      'boardCategory:',
      'boardCategoryLabel:',
      'board_payload:',
    ]) {
      expect(saveSection, isNot(contains(deprecated)));
    }
  });

  test('Daily Wear keeps the pending Style loader neutral', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final messages = source.substring(source.indexOf('Widget _chatMessages()'));

    expect(messages, contains('return const _TypingBubble();'));
    expect(
      messages,
      isNot(contains('AhviProcessingContext.styleRecommendation')),
    );
    expect(messages, isNot(contains('Curating your look')));
  });

  test('Daily Wear clears pending state and hides backend errors', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final request = source.substring(
      source.indexOf('Future<void> _callBackendStylist'),
      source.indexOf('void _speakMessage'),
    );

    expect(request, contains('if (!mounted) return;'));
    expect(request, contains('_isTyping = false;'));
    expect(request, isNot(contains('style request failed')));
    expect(request, contains("I'm having a moment - try again."));
  });

  test('Daily Wear board items use canonical StyleBoardItem parsing', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final mapper = source.substring(
      source.indexOf('StyleBoardItem _styleBoardItemFromMap'),
      source.indexOf('/// Builds the Style Board', source.indexOf('StyleBoardItem _styleBoardItemFromMap')),
    );

    expect(mapper, contains('return StyleBoardItem.fromJson(item);'));
    expect(mapper, isNot(contains("item['img']")));
    expect(mapper, isNot(contains("item['photo_url']")));
  });

  test('active Daily Wear visuals delegate to the canonical grid', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('AhviUnifiedOutfitGrid('));
    expect(source, contains("surface: 'style_board_daily_wear_unified_grid'"));
    expect(source, isNot(contains('EditorialBoardCanvas(board: styleBoard)')));
  });

  test('pending loader is independent of prior visual board responses', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final messages = source.substring(source.indexOf('Widget _chatMessages()'));

    expect(messages, contains('_messages.length + (_isTyping ? 1 : 0)'));
    expect(messages, contains('return const _TypingBubble();'));
    expect(messages, isNot(contains('styleBoard')));
  });

  test(
    'Daily Board card normalizer accepts the canonical board_items/composition_items field names',
    () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final normalizer = source.substring(
        source.indexOf('Map<String, dynamic> _normalizeDailyBoardCard'),
        source.indexOf('String _localOutfitImage'),
      );

      // Build 2012: the backend's board contract carries garments under
      // `board_items` (sometimes `composition_items`) — the same field
      // names the canonical chat block parser checks. Reading `items`
      // alone silently dropped every real card, leaving the Daily Wear
      // board permanently blank. Precedence now lives in the centralized
      // DailyWearScreen.firstNonEmptyBoardItems helper (shared with
      // _recordWear) rather than an inline chain here.
      expect(
        normalizer,
        contains('DailyWearScreen.firstNonEmptyBoardItems(card)'),
      );
    },
  );

  test(
    'Daily Board card normalizer prefers board_items over raw items — Build 2013',
    () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final helper = source.substring(
        source.indexOf('static List<dynamic> firstNonEmptyBoardItems'),
        source.indexOf('@override', source.indexOf('static List<dynamic> firstNonEmptyBoardItems')),
      );

      // Build 2013: raw `items` is the pre-enrichment list (name/category/
      // raw photo only) and always resolves to an empty imageUrl once
      // parsed through resolveWardrobeImage, which requires a masked/
      // normalized/cutout field before trusting an image as board-safe.
      // `board_items` is the adapted, enriched field the canonical chat
      // board renderer (ahvi_outfit_board_card.dart) reads first, so the
      // centralized precedence helper must check it before composition_items,
      // used_wardrobe_items, and items (in that order) or every
      // populated-wardrobe card renders as a permanent blank shell.
      final order = ['board_items', 'composition_items', 'used_wardrobe_items', 'items']
          .map((key) => helper.indexOf("'$key'"))
          .toList();
      expect(order, everyElement(greaterThanOrEqualTo(0)));
      expect(order, orderedEquals(List.of(order)..sort()));
    },
  );

  test(
    'Daily Board falls back to the canonical empty-wardrobe UX, never demo garments — Build 2013',
    () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final fetchStart = source.indexOf('Future<void> _fetchDailyBoard');
      final fetch = source.substring(
        fetchStart,
        source.indexOf('void initState() {', fetchStart),
      );

      // Build 2013: when the backend returns zero usable Daily Board cards
      // without explicitly flagging insufficient_wardrobe, the old code
      // fell to _fallbackOutfits() — local demo garments shaped for the
      // retired AR renderer (no `items` field), which _styleBoardFromOutfit
      // always rejects (permanent blank white board), and which also
      // misrepresented demo pieces as belonging to the user's own wardrobe.
      expect(fetch, isNot(contains('_fallbackOutfits()')));
      expect(fetch, contains('_needsMoreClothes = true'));
    },
  );

  test(
    'Daily Wear autoplay never calls animateToPage on an unattached PageController',
    () {
      final source = File('lib/daily_wear.dart').readAsStringSync();
      final autoplay = source.substring(
        source.indexOf('void _startAutoPlay()'),
        source.indexOf('Future<void> _fetchWeather'),
      );

      // Build 2012: _displayedOutfits could go non-empty (weather-driven
      // fallback sort) before the PageView actually mounted, so
      // animateToPage threw "Bad state: No element" on an unattached
      // controller. hasClients is the direct attached-Scrollable signal.
      expect(autoplay, contains('!_pageController.hasClients'));
      expect(autoplay, contains('_displayedOutfits.isEmpty'));
      expect(autoplay, contains('if (!mounted ||'));
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Daily Board card normalizer uses _firstNonEmptyBoardItems', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final normalizer = source.substring(
      source.indexOf('Map<String, dynamic> _normalizeDailyBoardCard'),
      source.indexOf('String _localOutfitImage'),
    );

    expect(normalizer, contains('_firstNonEmptyBoardItems(card)'));
  });

  test('Daily Board visuals render via EditorialBoardCanvas', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    expect(source, contains('EditorialBoardCanvas(board: styleBoard)'));
  });

  test('Daily Wear pending loader uses typing bubble', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final messages = source.substring(source.indexOf('Widget _chatMessages()'));

    expect(messages, contains('_messages.length + (_isTyping ? 1 : 0)'));
    expect(messages, contains('return const _TypingBubble();'));
  });

  test('Daily Wear autoplay never calls animateToPage on an unattached PageController', () {
    final source = File('lib/daily_wear.dart').readAsStringSync();
    final autoplay = source.substring(
      source.indexOf('void _startAutoPlay()'),
      source.indexOf('Future<void> _fetchWeather'),
    );

    expect(autoplay, contains('!_pageController.hasClients'));
    expect(autoplay, contains('_displayedOutfits.isEmpty'));
    expect(autoplay, contains('if (!mounted ||'));
  });
}

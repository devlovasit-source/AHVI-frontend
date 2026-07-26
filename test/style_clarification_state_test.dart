// Source contracts for the clarification-state fix. The clarification logic
// lives inside large stateful chat widgets whose private state is impractical to
// drive in a harness, so these assert the concrete wiring: a rendered board
// resolves the pending clarification, board actions bypass clarification, and a
// fresh clarification re-arms it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _method(String src, String marker) {
  final start = src.indexOf(marker);
  expect(start, isNonNegative, reason: 'missing $marker');
  final open = src.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  fail('unbalanced braces for $marker');
}

void main() {
  final stylist = _read('lib/widgets/ahvi_stylist_chat.dart');
  final chat = _read('lib/chat.dart');

  for (final entry in {
    'ahvi_stylist_chat.dart': stylist,
    'chat.dart': chat,
  }.entries) {
    final name = entry.key;
    final src = entry.value;

    group('$name clarification lifecycle', () {
      test('has a resolved-by-cards flag', () {
        expect(src, contains('bool _clarificationResolvedByCards = false'));
      });

      test('pending clarification is suppressed once cards rendered', () {
        final body = _method(src, 'String _pendingStyleClarificationPrompt()');
        expect(body, contains('if (_clarificationResolvedByCards) return \'\';'));
      });

      test('board-action phrases bypass clarification serialization', () {
        expect(src, contains('_isBoardActionPhrase'));
        // The pending-clarification gate excludes board actions.
        expect(src, contains('!isBoardActionPhrase'));
      });

      test('a rendered board sets the flag; a clarification re-arms it', () {
        expect(src, contains('_clarificationResolvedByCards = true'));
        expect(src, contains('_clarificationResolvedByCards = false'));
      });

      test('board-action detector matches Shuffle / another-look phrases', () {
        final body = _method(src, 'bool _isBoardActionPhrase(String value)');
        expect(body, contains('another look'));
        expect(body.toLowerCase(), contains('shuffle'));
      });
    });
  }

  group('board actions never serialized as clarification_selected', () {
    test('clarification_selected is only used when isClarificationAnswer', () {
      // isClarificationAnswer is false for board-action phrases and after cards,
      // so Shuffle / another-look never carries action=clarification_selected.
      expect(
        stylist,
        contains("isClarificationAnswer ? 'clarification_selected' : null"),
      );
      expect(stylist, contains('!isBoardActionPhrase'));
    });
  });

  group('Save/Like/Dislike/Share are not board-action-phrase / clarification', () {
    test('action-bar labels do not trigger the clarification send path', () {
      // These are OutfitActionBar callbacks, not chat text sends; the phrase
      // detector must not accidentally treat them as board-shuffle prompts.
      final body = _method(stylist, 'bool _isBoardActionPhrase(String value)');
      for (final label in ['save', 'like', 'dislike', 'share']) {
        expect(body.contains("'$label'"), isFalse,
            reason: '$label must not be a board-action phrase');
      }
    });
  });
}

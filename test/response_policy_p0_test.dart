// P0 tests for the canonical response_mode precedence in AhviResponsePolicy.
//
// Covers:
//   1. response_mode field (highest precedence) resolves to the correct
//      canRenderBoards decision for all 10 MVP modes.
//   2. Legacy `mode` and `intent` fields remain the fallback for older
//      backend envelopes that have not yet been stamped with response_mode.
//   3. Unknown / empty response_mode falls back to legacy resolution
//      instead of failing open.
//   4. AhviSessionGenerationGuard.invalidate() correctly orphans an
//      earlier captured token — the primitive the chat _sendMessage change
//      relies on for late-response rejection.
//
// ponytail: no widget rendering, no HTTP mocks. This suite is Dart-only
// so `flutter test test/response_policy_p0_test.dart` runs in seconds.

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/ahvi_response_policy.dart';

void main() {
  group('AhviResponsePolicy response_mode precedence', () {
    test('response_mode text_only suppresses board rendering', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'text_only',
        'visual_directions': [
          {'title': 'Would-be direction'},
        ],
      });
      expect(policy.canRenderBoards({}), isFalse);
      expect(policy.textPrimary, isTrue);
    });

    test('response_mode clarification suppresses board rendering', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'clarification',
      });
      expect(policy.canRenderBoards({}), isFalse);
      expect(policy.textPrimary, isTrue);
    });

    test('response_mode calendar_navigation suppresses Style renderer', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'calendar_navigation',
      });
      expect(policy.canRenderBoards({}), isFalse);
    });

    test('response_mode planner_action suppresses Style renderer', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'planner_action',
      });
      expect(policy.canRenderBoards({}), isFalse);
    });

    test('response_mode visual_inspiration authorizes boards', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'visual_inspiration',
      });
      expect(policy.mayRenderBoards, isTrue);
      // canRenderBoards for non-style_this routes just checks mayRenderBoards.
      expect(policy.canRenderBoards({}), isTrue);
    });

    test('response_mode wardrobe_recommendation authorizes boards', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'wardrobe_recommendation',
      });
      expect(policy.mayRenderBoards, isTrue);
    });

    test('response_mode style_this requires a validated anchor', () {
      final noAnchor = AhviResponsePolicy.fromResponse({
        'response_mode': 'style_this',
      });
      expect(noAnchor.canRenderBoards({}), isFalse,
          reason: 'style_this without an anchor must not render boards');

      final response = <String, dynamic>{
        'response_mode': 'style_this',
        'anchor_item': {'item_id': 'belt-42'},
        'anchor_locked': true,
      };
      final withAnchor = AhviResponsePolicy.fromResponse(response);
      expect(withAnchor.canRenderBoards(response), isTrue);
    });

    test('response_mode build_outfit authorizes boards', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'build_outfit',
      });
      expect(policy.mayRenderBoards, isTrue);
    });

    test('response_mode error suppresses boards', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'error',
      });
      expect(policy.canRenderBoards({}), isFalse);
      expect(policy.textPrimary, isTrue);
    });
  });

  group('AhviResponsePolicy legacy fallback', () {
    test('legacy mode=wardrobe_style still authorizes boards', () {
      final policy = AhviResponsePolicy.fromResponse({
        'mode': 'wardrobe_style',
      });
      expect(policy.mayRenderBoards, isTrue);
    });

    test('legacy intent=style_advice still suppresses boards', () {
      final policy = AhviResponsePolicy.fromResponse({
        'intent': 'style_advice',
      });
      expect(policy.canRenderBoards({}), isFalse);
      expect(policy.textPrimary, isTrue);
    });

    test('empty envelope defaults to text-primary (fail closed)', () {
      final policy = AhviResponsePolicy.fromResponse({});
      expect(policy.canRenderBoards({}), isFalse);
    });

    test('unknown response_mode falls back to legacy resolution', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'junk_value',
        'intent': 'wardrobe_style',
      });
      expect(policy.mayRenderBoards, isTrue,
          reason:
              'unknown response_mode must not lock out an otherwise-valid legacy intent');
    });

    test('response_mode wins over disagreeing legacy intent', () {
      final policy = AhviResponsePolicy.fromResponse({
        'response_mode': 'text_only',
        // Backend accidentally leaked visual_inspiration under legacy field:
        'intent': 'visual_inspiration',
      });
      expect(policy.canRenderBoards({}), isFalse,
          reason:
              'response_mode is the authority; a text_only response must suppress '
              'boards even if a legacy field says otherwise');
    });
  });

  group('AhviSessionGenerationGuard invalidate', () {
    test('invalidate orphans an earlier captured token', () {
      final guard = AhviSessionGenerationGuard();
      final tokenA = guard.capture('session-1');
      expect(guard.accepts(tokenA, 'session-1'), isTrue);

      guard.invalidate();
      expect(guard.accepts(tokenA, 'session-1'), isFalse,
          reason:
              'A response returning after invalidate() must be discarded — '
              'this is the primitive chat._sendMessage relies on for late-response drop');

      final tokenB = guard.capture('session-1');
      expect(guard.accepts(tokenB, 'session-1'), isTrue);
    });

    test('two rapid captures without invalidate share the same generation', () {
      final guard = AhviSessionGenerationGuard();
      final tokenA = guard.capture('session-1');
      final tokenB = guard.capture('session-1');
      // Both accept — the P0 fix is to call invalidate() before capture so
      // the older request is dropped explicitly.
      expect(guard.accepts(tokenA, 'session-1'), isTrue);
      expect(guard.accepts(tokenB, 'session-1'), isTrue);
    });

    test('accepts rejects a foreign session id', () {
      final guard = AhviSessionGenerationGuard();
      final token = guard.capture('session-old');
      expect(guard.accepts(token, 'session-new'), isFalse);
    });
  });
}

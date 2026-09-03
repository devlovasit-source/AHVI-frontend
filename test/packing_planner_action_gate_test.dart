// Packing P0 — planner_action authorization gate.
//
// Root cause: response_mode "planner_action" (what plan_pack maps to) is a
// board-unauthorized route by design (Style Boards must never render for a
// packing response) — but the packing checklist / typed module cards are
// NOT Style Boards, and were incorrectly nulled out by the same
// textOnlyResponse flag that exists to gate board rendering. Fix: in both
// lib/chat.dart and lib/widgets/ahvi_stylist_chat.dart, packing/typed-module
// card population is now gated on AhviResponsePolicy.isSafetySensitive only,
// leaving canRenderBoards/board authorization (and every other suppressed
// route's behavior) completely unchanged.
//
// ponytail: Dart-only + renderer-registry level. The gating logic itself
// lives inline inside the two chat screens' private _sendMessage methods —
// not independently callable — so this suite proves the logical precondition
// (isSafetySensitive false + packingCard non-null for a realistic payload)
// and pins the exact source change, rather than mounting a full fake-backend
// send flow on either screen (no existing precedent/harness for that in this
// codebase; flagged as a manual/physical verification gap in the P0 report).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/ahvi_response_policy.dart';
import 'package:myapp/services/chat_response_renderer_registry.dart';

Map<String, dynamic> _goaPlanPackResponse({String? safetyLevel}) => {
  'response_mode': 'planner_action',
  'intent': 'plan_pack',
  'type': 'checklists',
  'visual_type': 'visual_packing_checklist',
  if (safetyLevel != null) 'safety_level': safetyLevel,
  'visual_sections': [
    {
      'id': 'clothes',
      'title': 'Clothes',
      'items': [
        {'label': 'Linen shirt'},
        {'label': 'Shorts'},
      ],
    },
    {
      'id': 'footwear',
      'title': 'Footwear',
      'items': [
        {'label': 'Sandals'},
      ],
    },
    {
      'id': 'toiletries',
      'title': 'Toiletries',
      'items': [
        {'label': 'Sunscreen'},
        {'label': 'Toothbrush'},
      ],
    },
    {
      'id': 'travel_essentials',
      'title': 'Travel essentials',
      'items': [
        {'label': 'Passport'},
      ],
    },
    {
      'id': 'weather_prep',
      'title': 'Weather prep',
      'items': [
        {'label': 'Umbrella'},
      ],
    },
  ],
};

void main() {
  group('CASE 1/7: planner_action packing response reaches the checklist renderer', () {
    test('policy: canRenderBoards stays false (Style Board authorization is unaffected)', () {
      final policy = AhviResponsePolicy.fromResponse(_goaPlanPackResponse());
      expect(
        policy.canRenderBoards({}),
        isFalse,
        reason: 'planner_action must never authorize Style Board rendering',
      );
    });

    test('policy: not safety-sensitive for a normal Goa packing request', () {
      final policy = AhviResponsePolicy.fromResponse(_goaPlanPackResponse());
      expect(policy.isSafetySensitive, isFalse);
    });

    test('renderer registry: selects the packing checklist for the realistic Goa payload', () {
      final response = _goaPlanPackResponse();
      expect(
        AhviChatResponseRendererRegistry.select(response).kind,
        AhviChatRendererKind.visualPackingChecklist,
      );
      final card = AhviChatResponseRendererRegistry.packingCard(response);
      expect(card, isNotNull);
      final sections = (card!['visual_sections'] as List)
          .cast<Map>()
          .map((s) => s['title'])
          .toList();
      expect(sections, [
        'Clothes',
        'Footwear',
        'Toiletries',
        'Travel essentials',
        'Weather prep',
      ]);
    });
  });

  group('CASE 2: safety-sensitive planner response cannot render a structured card', () {
    test('policy: safety_level=urgent marks the response safety-sensitive', () {
      final policy = AhviResponsePolicy.fromResponse(
        _goaPlanPackResponse(safetyLevel: 'urgent'),
      );
      expect(policy.isSafetySensitive, isTrue);
    });

    test(
      'source contract: both chat surfaces gate packing/typed-module cards on '
      'isSafetySensitive, not on the board-authorization textOnlyResponse flag',
      () {
        final chatSource = File('lib/chat.dart').readAsStringSync();
        final stylistSource =
            File('lib/widgets/ahvi_stylist_chat.dart').readAsStringSync();

        expect(
          stylistSource.contains(
            'final visualPackingCard = responsePolicy.isSafetySensitive',
          ),
          isTrue,
          reason: 'ahvi_stylist_chat.dart visualPackingCard must be gated on isSafetySensitive',
        );
        expect(
          stylistSource.contains(
            'final typedModuleCard = responsePolicy.isSafetySensitive',
          ),
          isTrue,
          reason: 'ahvi_stylist_chat.dart typedModuleCard must be gated on isSafetySensitive',
        );
        expect(
          chatSource.contains(
            'visualPackingCard != null && !responsePolicy.isSafetySensitive',
          ),
          isTrue,
          reason: 'chat.dart moduleCards must carve out packing from the board-authorization gate',
        );
      },
    );
  });

  group('CASE 3: no Style Board leakage from the packing exemption', () {
    test('only plan_pack maps to planner_action — no other route shares the exemption', () {
      // Documents the backend contract this fix relies on (independently
      // confirmed against services/response_contract.py during the audit):
      // response_mode=planner_action is produced exclusively by the
      // plan_pack legacy intent, so narrowly exempting packing/typed-module
      // cards from board-authorization cannot spuriously unlock Style Board
      // rendering for any other flow.
      expect(ahviBoardSuppressedRoutes.contains('planner_action'), isTrue);
      expect(ahviBoardAuthorizedRoutes.contains('planner_action'), isFalse);
    });

    test('a planner_action response with no packing payload renders nothing structured', () {
      final response = {'response_mode': 'planner_action', 'message': 'ok'};
      expect(
        AhviChatResponseRendererRegistry.packingCard(response),
        isNull,
      );
      expect(
        AhviResponsePolicy.fromResponse(response).canRenderBoards({}),
        isFalse,
      );
    });
  });

  group('CASE 4: parser — visual_sections become visual_packing_checklist module cards', () {
    test('selects rich packing before generic module cards (existing coverage, reconfirmed)', () {
      final response = _goaPlanPackResponse();
      final cards = AhviChatResponseRendererRegistry.moduleCards(response);
      expect(cards, hasLength(1));
      expect(cards.single['type'], 'visual_packing_checklist');
    });
  });

  group('Regression: other suppressed routes remain suppressed', () {
    for (final route in [
      'text_only',
      'calendar_navigation',
      'calendar_action',
      'clarification',
      'style_advice',
    ]) {
      test('$route still cannot render Style Boards', () {
        final policy = AhviResponsePolicy.fromResponse({
          'response_mode': route,
        });
        expect(policy.canRenderBoards({}), isFalse);
      });
    }

    test('medical_urgent / diagnosis_request remain safety-sensitive', () {
      expect(
        AhviResponsePolicy.fromResponse({
          'response_mode': 'medical_urgent',
        }).isSafetySensitive,
        isTrue,
      );
      expect(
        AhviResponsePolicy.fromResponse({
          'response_mode': 'diagnosis_request',
        }).isSafetySensitive,
        isTrue,
      );
    });
  });
}

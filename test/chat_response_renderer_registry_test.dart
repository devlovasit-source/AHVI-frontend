import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/chat_response_renderer_registry.dart';

void main() {
  test('selects rich packing before generic module cards', () {
    final response = {
      'type': 'module_response',
      'module': 'planner',
      'visual_sections': [
        {
          'title': 'Tech',
          'items': [
            {'label': 'Charger'},
          ],
        },
      ],
      'card': {'title': 'Generic fallback'},
    };

    expect(
      AhviChatResponseRendererRegistry.select(response).kind,
      AhviChatRendererKind.visualPackingChecklist,
    );
    expect(
      AhviChatResponseRendererRegistry.moduleCards(response),
      hasLength(1),
    );
    expect(
      AhviChatResponseRendererRegistry.moduleCards(response).single['type'],
      'visual_packing_checklist',
    );
  });

  test('maps typed module cards without changing their CTA contract', () {
    final response = {
      'response_type': 'module_card',
      'module': 'medi',
      'card': {
        'title': 'Medicine',
        'open_key': 'medi',
        'rows': [
          {'main': 'Vitamin D', 'done': false},
        ],
      },
    };
    final selection = AhviChatResponseRendererRegistry.select(response);
    final card = AhviChatResponseRendererRegistry.typedModuleCard(response);

    expect(selection.kind, AhviChatRendererKind.moduleCard);
    expect(card, isNotNull);
    expect(card!.openKey, 'medi');
    expect(card.rows.single.main, 'Vitamin D');
  });

  test('preserves existing visual and style renderer precedence', () {
    expect(
      AhviChatResponseRendererRegistry.select({
        'route': 'visual_inspiration',
        'visual_board': {
          'response_type': 'visual_board',
          'board_type': 'diet_plan',
          'sections': [],
        },
      }).kind,
      AhviChatRendererKind.visualBoard,
    );
    expect(
      AhviChatResponseRendererRegistry.select({
        'route': 'visual_inspiration',
        'visual_directions': [
          {'title': 'Soft layers'},
        ],
      }).kind,
      AhviChatRendererKind.visualDirections,
    );
    expect(
      AhviChatResponseRendererRegistry.select({
        'route': 'visual_inspiration',
        'style_boards': [
          {'title': 'Weekend'},
        ],
      }).kind,
      AhviChatRendererKind.styleBoard,
    );
  });

  test('maps typed calendar plan aliases and generic module payloads', () {
    expect(
      AhviChatResponseRendererRegistry.select({
        'intent': 'plan_pack',
        'module': 'calendar',
      }).kind,
      AhviChatRendererKind.calendarPlan,
    );
    for (final module in const ['calendar', 'diet', 'fitness', 'medi']) {
      expect(
        AhviChatResponseRendererRegistry.select({
          'type': 'module_response',
          'module': module,
          'cards': [
            {'title': module},
          ],
        }).kind,
        AhviChatRendererKind.genericModuleCard,
      );
    }
  });

  test('falls back to text for unsupported response contracts', () {
    expect(
      AhviChatResponseRendererRegistry.select({
        'type': 'new_backend_shape',
      }).kind,
      AhviChatRendererKind.text,
    );
  });

  test('suppresses packing cards from the Style board renderer', () {
    final response = {
      'visual_type': 'visual_packing_checklist',
      'cards': [
        {'title': 'Pack chargers'},
      ],
    };

    expect(
      AhviChatResponseRendererRegistry.select(response).kind,
      AhviChatRendererKind.text,
    );
    expect(AhviChatResponseRendererRegistry.moduleCards(response), isEmpty);
  });

  test('keeps the dedicated packing renderer for visual sections', () {
    final response = {
      'intent': 'plan_pack',
      'visual_sections': [
        {
          'title': 'Essentials',
          'items': ['Passport'],
        },
      ],
    };

    expect(
      AhviChatResponseRendererRegistry.select(response).kind,
      AhviChatRendererKind.visualPackingChecklist,
    );
  });

  test('normalizes all supported rich packing payload locations', () {
    final section = {
      'title': 'Essentials',
      'items': [
        {'label': 'Passport'},
      ],
    };
    final shapes = [
      {
        'visual_sections': [section],
      },
      {
        'visualSections': [section],
      },
      {
        'data': {
          'visual_sections': [section],
        },
      },
      {
        'data': {
          'visualSections': [section],
        },
      },
      {
        'card': {
          'visual_sections': [section],
        },
      },
      {
        'card': {
          'visualSections': [section],
        },
      },
      {
        'cards': [
          {
            'visual_sections': [section],
          },
        ],
      },
      {
        'cards': [
          {
            'visualSections': [section],
          },
        ],
      },
      {
        'module_cards': [
          {
            'visual_sections': [section],
          },
        ],
      },
      {
        'moduleCards': [
          {
            'visualSections': [section],
          },
        ],
      },
      {
        'data': {
          'module_cards': [
            {
              'visual_sections': [section],
            },
          ],
        },
      },
      {
        'data': {
          'moduleCards': [
            {
              'visualSections': [section],
            },
          ],
        },
      },
    ];

    for (final response in shapes) {
      final card = AhviChatResponseRendererRegistry.packingCard(response);
      expect(
        AhviChatResponseRendererRegistry.select(response).kind,
        AhviChatRendererKind.visualPackingChecklist,
      );
      expect(card, isNotNull);
      expect(card!['visual_sections'], hasLength(1));
      final cards = AhviChatResponseRendererRegistry.moduleCards(response);
      expect(cards, hasLength(1));
      expect(cards.single['type'], 'visual_packing_checklist');
      expect(cards.single['visual_sections'], hasLength(1));
    }
  });
}

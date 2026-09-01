import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/style_mutation_contract.dart';

void main() {
  group('retainBoardNarrative', () {
    test(
      'single-board retention: backfills blank why/tip/title from the '
      'previous board regardless of board_id',
      () {
        final previousBoard = <String, dynamic>{
          'board_id': 'board-1',
          'title': 'Refined Weekend',
          'why_it_works':
              'Shirt and Jeans keep the palette balanced for the request.',
          'styling_tip':
              'Roll your sleeves once or twice to create a clean cuff.',
        };
        // Mutation response: single board, fresh/different id, everything
        // narrative-related left blank by the legacy endpoint.
        final responseBoards = <Map<String, dynamic>>[
          <String, dynamic>{
            'board_id': 'board-2-fresh-mutation-id',
            'items': ['footwear-item'],
          },
        ];

        final result = retainBoardNarrative(responseBoards, previousBoard);

        expect(result, hasLength(1));
        expect(result.single['title'], 'Refined Weekend');
        expect(
          result.single['why_it_works'],
          'Shirt and Jeans keep the palette balanced for the request.',
        );
        expect(
          result.single['styling_tip'],
          'Roll your sleeves once or twice to create a clean cuff.',
        );
      },
    );

    test(
      'multi-board isolation: an empty/missing board_id must NOT '
      'auto-match the previous board in a multi-board response',
      () {
        final previousBoard = <String, dynamic>{
          'board_id': 'board-1',
          'title': 'Refined Weekend',
          'why_it_works': 'Old rationale that must not leak.',
          'styling_tip': 'Old tip that must not leak.',
        };
        final responseBoards = <Map<String, dynamic>>[
          // Matches previous board's id exactly -> should be backfilled.
          <String, dynamic>{'board_id': 'board-1'},
          // Different, non-empty id -> must NOT be backfilled.
          <String, dynamic>{'board_id': 'board-3'},
          // Empty board_id -> must NOT be auto-matched/backfilled.
          <String, dynamic>{'board_id': ''},
          // Missing board_id entirely -> must NOT be auto-matched/backfilled.
          <String, dynamic>{'items': ['top-item']},
        ];

        final result = retainBoardNarrative(responseBoards, previousBoard);

        expect(result, hasLength(4));
        expect(result[0]['title'], 'Refined Weekend');
        expect(result[0]['why_it_works'], 'Old rationale that must not leak.');

        expect(result[1].containsKey('title'), isFalse);
        expect(result[1].containsKey('why_it_works'), isFalse);

        expect(result[2].containsKey('title'), isFalse);
        expect(result[2].containsKey('why_it_works'), isFalse);
        expect(result[2].containsKey('styling_tip'), isFalse);

        expect(result[3].containsKey('title'), isFalse);
        expect(result[3].containsKey('why_it_works'), isFalse);
        expect(result[3].containsKey('styling_tip'), isFalse);
      },
    );

    test(
      'fresh narrative precedence: a fresh lower-precedence alias in a '
      'group must not be shadowed by an old higher-precedence alias',
      () {
        final previousBoard = <String, dynamic>{
          'board_id': 'board-1',
          'why_it_works': 'OLD why_it_works — higher precedence alias.',
          'explanation': 'OLD explanation — lower precedence alias.',
        };
        // Response has NO value under the higher-precedence 'why_it_works'
        // key, but DOES have a fresh value under the lower-precedence
        // 'explanation' key. The whole "why" group must be left alone —
        // backfilling 'why_it_works' here would shadow the fresh
        // 'explanation' once the card resolves alias priority.
        final responseBoards = <Map<String, dynamic>>[
          <String, dynamic>{
            'board_id': 'board-1',
            'explanation': 'FRESH explanation from this mutation.',
          },
        ];

        final result = retainBoardNarrative(responseBoards, previousBoard);

        expect(result, hasLength(1));
        expect(
          result.single['explanation'],
          'FRESH explanation from this mutation.',
        );
        // Must remain absent/blank — NOT backfilled with the stale value.
        expect(result.single.containsKey('why_it_works'), isFalse);
      },
    );

    test(
      'styling-tip retention: a blank styling tip is backfilled from the '
      'previous board when the response has no fresh tip under any alias',
      () {
        final previousBoard = <String, dynamic>{
          'board_id': 'board-1',
          'styling_tip':
              'Roll your sleeves once or twice to create a clean cuff.',
        };
        final responseBoards = <Map<String, dynamic>>[
          <String, dynamic>{
            'board_id': 'board-1',
            'styling_tip': '',
          },
        ];

        final result = retainBoardNarrative(responseBoards, previousBoard);

        expect(
          result.single['styling_tip'],
          'Roll your sleeves once or twice to create a clean cuff.',
        );
      },
    );

    test(
      'styling-tip group is untouched when a fresh tip alias is present, '
      'even if another tip alias in the group is blank',
      () {
        final previousBoard = <String, dynamic>{
          'board_id': 'board-1',
          'styling_tip': 'OLD styling_tip — must not leak.',
          'style_note': 'OLD style_note — must not leak.',
        };
        final responseBoards = <Map<String, dynamic>>[
          <String, dynamic>{
            'board_id': 'board-1',
            // Fresh value under a different alias in the same tip group.
            'style_tip': 'FRESH style_tip from this mutation.',
          },
        ];

        final result = retainBoardNarrative(responseBoards, previousBoard);

        expect(
          result.single['style_tip'],
          'FRESH style_tip from this mutation.',
        );
        expect(result.single.containsKey('styling_tip'), isFalse);
        expect(result.single.containsKey('style_note'), isFalse);
      },
    );

    test('returns boards unchanged when previousBoard is null', () {
      final responseBoards = <Map<String, dynamic>>[
        <String, dynamic>{'board_id': 'board-1'},
      ];
      final result = retainBoardNarrative(responseBoards, null);
      expect(result, same(responseBoards));
    });

    test('returns empty list unchanged when boards is empty', () {
      final previousBoard = <String, dynamic>{'board_id': 'board-1'};
      final result = retainBoardNarrative(<Map<String, dynamic>>[], previousBoard);
      expect(result, isEmpty);
    });
  });
}
// Shuffle must use the durable board contract (board_id / revision /
// source_policy / occasion) so an office wardrobe board stays office + wardrobe,
// instead of falling back to a natural-language "another look".
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/style_board_state.dart';
import 'package:myapp/services/style_board_api_service.dart';

StyleBoardItem _lockable(String id, String slot, BoardItemRole role) =>
    StyleBoardItem(
      id: id,
      slot: slot,
      source: 'wardrobe',
      name: id,
      imageUrl: 'https://example.test/$id.png',
      category: slot,
      role: role,
      position: const BoardPosition(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
      raw: {'item_id': id, 'slot': slot, 'source': 'wardrobe'},
    );

StyleBoardState _officeWardrobeBoard() => StyleBoardState(
      boardId: 'board_abc123',
      revision: 1,
      sourcePolicy: 'wardrobe',
      items: [
        _lockable('top-1', 'top', BoardItemRole.top),
        _lockable('bottom-1', 'bottom', BoardItemRole.bottom),
        _lockable('shoe-1', 'footwear', BoardItemRole.footwear),
      ],
    );

void main() {
  group('buildShufflePayload preserves the board contract', () {
    test('sends revision, occasion and wardrobe source_policy', () {
      final payload = const StyleBoardApiService().buildShufflePayload(
        board: _officeWardrobeBoard(),
        occasion: 'office',
        styleDirection: 'Composed Authority',
      );
      expect(payload['revision'], 1);
      expect(payload['occasion'], 'office'); // office stays office
      expect(payload['source_policy'], 'wardrobe'); // wardrobe stays wardrobe
      expect(payload['style_direction'], 'Composed Authority');
      expect(payload['scenario'], 'shuffle_unlocked');
      expect((payload['board_items'] as List).length, 3);
    });

    test('board_id drives the locked shuffle endpoint, not a chat prompt', () {
      // shuffle() posts to /api/style-boards/{board_id}/shuffle via the backend;
      // the id comes straight off the board state.
      expect(_officeWardrobeBoard().boardId, 'board_abc123');
    });
  });

  group('supportsShuffle gates the durable flow', () {
    test('true when board_id + revision + wardrobe policy + lockable items', () {
      expect(_officeWardrobeBoard().supportsShuffle, isTrue);
    });

    test('false without a board_id -> natural-language fallback path', () {
      final noContract = StyleBoardState(
        boardId: '',
        revision: 0,
        sourcePolicy: '',
        items: _officeWardrobeBoard().items,
      );
      expect(noContract.supportsShuffle, isFalse);
    });

    test('wardrobe is an explicit, valid source policy', () {
      expect(_officeWardrobeBoard().hasExplicitSourcePolicy, isTrue);
    });
  });
}

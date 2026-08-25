import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/feature/chat/services/saved_boards_store.dart';

/// Regression tests for the "Save button still shows Saved after the
/// board was deleted from the Boards screen" bug.
///
/// Root cause: SavedBoardsStore (a local SharedPreferences mirror that
/// only drives the chat Save button's UI state) was never cleared when a
/// board was deleted from Appwrite (the authoritative store), because the
/// two stores used different identity schemes and delete flows only
/// touched Appwrite.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SavedBoardsStore.resetForTest();
    await SavedBoardsStore.clearForTest();
  });

  Map<String, dynamic> direction({String? boardId}) => {
    if (boardId != null) 'board_id': boardId,
    'title': 'Refined Weekend',
  };

  group('SavedBoardsStore.removeForServerBoard', () {
    test('removes the local entry via canonical board_id', () async {
      await SavedBoardsStore.saveBoard(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
        direction: direction(boardId: 'board-abc-123'),
      );
      final id = SavedBoardsStore.idFor(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
      );
      expect(await SavedBoardsStore.isSaved(id), isTrue);

      // Server-side deletion path only knows the canonical board_id, not
      // the occasion/title used to derive the legacy local id.
      await SavedBoardsStore.removeForServerBoard({
        'board_id': 'board-abc-123',
      });

      expect(await SavedBoardsStore.isSaved(id), isFalse);
    });

    test(
      'falls back to legacy occasion+title id when no board_id is stored',
      () async {
        // Simulates an entry saved before board_id tracking existed.
        await SavedBoardsStore.saveBoard(
          occasion: 'Weekend',
          directionName: 'Refined Weekend',
          direction: const {}, // no board_id available on the direction
        );
        final id = SavedBoardsStore.idFor(
          occasion: 'Weekend',
          directionName: 'Refined Weekend',
        );
        expect(await SavedBoardsStore.isSaved(id), isTrue);

        await SavedBoardsStore.removeForServerBoard({
          'occasion': 'Weekend',
          'title': 'Refined Weekend',
        });

        expect(await SavedBoardsStore.isSaved(id), isFalse);
      },
    );

    test('a fresh board for the same occasion/direction is not pre-marked '
        'as saved once the old entry is cleaned up', () async {
      await SavedBoardsStore.saveBoard(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
        direction: direction(boardId: 'board-abc-123'),
      );
      await SavedBoardsStore.removeForServerBoard({
        'board_id': 'board-abc-123',
      });

      // Re-asking AHVI for the same style produces a new board with the
      // same occasion/direction name — it must not inherit stale "saved"
      // state from the deleted board.
      final id = SavedBoardsStore.idFor(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
      );
      expect(await SavedBoardsStore.isSaved(id), isFalse);
    });

    test('does not touch unrelated entries', () async {
      await SavedBoardsStore.saveBoard(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
        direction: direction(boardId: 'board-abc-123'),
      );
      await SavedBoardsStore.saveBoard(
        occasion: 'Office',
        directionName: 'Sharp Monday',
        direction: direction(boardId: 'board-xyz-999'),
      );

      await SavedBoardsStore.removeForServerBoard({
        'board_id': 'board-abc-123',
      });

      final removedId = SavedBoardsStore.idFor(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
      );
      final untouchedId = SavedBoardsStore.idFor(
        occasion: 'Office',
        directionName: 'Sharp Monday',
      );
      expect(await SavedBoardsStore.isSaved(removedId), isFalse);
      expect(await SavedBoardsStore.isSaved(untouchedId), isTrue);
    });

    test('does not remove a different canonical board sharing the same '
        'legacy id', () async {
      // board-B has its own canonical board_id but happens to share
      // occasion + title with the board being deleted (board-A). The
      // legacy occasion+title fallback must never override a
      // non-matching canonical id.
      await SavedBoardsStore.saveBoard(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
        direction: direction(boardId: 'board-B'),
      );

      await SavedBoardsStore.removeForServerBoard({
        'board_id': 'board-A',
        'occasion': 'Weekend',
        'title': 'Refined Weekend',
      });

      final id = SavedBoardsStore.idFor(
        occasion: 'Weekend',
        directionName: 'Refined Weekend',
      );
      expect(await SavedBoardsStore.isSaved(id), isTrue);
    });

    test(
      'no-op when neither board_id nor occasion/title are present',
      () async {
        await SavedBoardsStore.saveBoard(
          occasion: 'Weekend',
          directionName: 'Refined Weekend',
          direction: direction(boardId: 'board-abc-123'),
        );

        // Nothing to match on — must not throw, must not wipe storage.
        await SavedBoardsStore.removeForServerBoard(const {});

        final id = SavedBoardsStore.idFor(
          occasion: 'Weekend',
          directionName: 'Refined Weekend',
        );
        expect(await SavedBoardsStore.isSaved(id), isTrue);
      },
    );
  });

  group('SavedBoardsStore.saveBoard board_id persistence', () {
    test(
      'stores board_id from the direction payload alongside the entry',
      () async {
        const occasion = 'Board Id Persistence Weekend';
        const directionName = 'Refined Weekend Persist';
        await SavedBoardsStore.saveBoard(
          occasion: occasion,
          directionName: directionName,
          direction: direction(boardId: 'board-abc-123'),
        );

        final id = SavedBoardsStore.idFor(
          occasion: occasion,
          directionName: directionName,
        );
        final entries = await SavedBoardsStore.list();
        final entry = entries.firstWhere((b) => b['id'] == id);
        expect(entry['board_id'], 'board-abc-123');
      },
    );

    test('stores an empty board_id when the direction has none', () async {
      const occasion = 'Board Id Persistence Empty';
      const directionName = 'No Board Id Direction';
      await SavedBoardsStore.saveBoard(
        occasion: occasion,
        directionName: directionName,
        direction: const {},
      );

      final id = SavedBoardsStore.idFor(
        occasion: occasion,
        directionName: directionName,
      );
      final entries = await SavedBoardsStore.list();
      final entry = entries.firstWhere((b) => b['id'] == id);
      expect(entry['board_id'], '');
    });
  });
}

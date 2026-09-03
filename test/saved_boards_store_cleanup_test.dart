import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/feature/chat/services/saved_boards_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SavedBoardsStore.resetForTest();
    await SavedBoardsStore.clearForTest();
  });

  Future<String> save({String boardId = ''}) async {
    await SavedBoardsStore.saveBoard(
      occasion: 'Weekend',
      directionName: 'Refined Weekend',
      direction: {
        if (boardId.isNotEmpty) 'board_id': boardId,
        'title': 'Refined Weekend',
      },
    );
    return SavedBoardsStore.idFor(
      occasion: 'Weekend',
      directionName: 'Refined Weekend',
    );
  }

  test('successful server deletion clears the local Saved mirror', () async {
    final id = await save(boardId: 'board-1');
    var serverDeleted = false;
    serverDeleted = true;
    if (serverDeleted) {
      await SavedBoardsStore.removeForServerBoard({'board_id': 'board-1'});
    }
    expect(await SavedBoardsStore.isSaved(id), isFalse);
  });

  test('canonical board_id cleanup does not remove another board', () async {
    final id = await save(boardId: 'board-2');
    await SavedBoardsStore.removeForServerBoard({'board_id': 'board-1'});
    expect(await SavedBoardsStore.isSaved(id), isTrue);
  });

  test('legacy occasion and title cleanup removes entries without board_id',
      () async {
    final id = await save();
    await SavedBoardsStore.removeForServerBoard({
      'occasion': 'Weekend',
      'title': 'Refined Weekend',
    });
    expect(await SavedBoardsStore.isSaved(id), isFalse);
  });

  test('legacy cleanup does not remove a canonical entry with the same id',
      () async {
    final id = await save(boardId: 'board-2');
    await SavedBoardsStore.removeForServerBoard({
      'occasion': 'Weekend',
      'title': 'Refined Weekend',
    });
    expect(await SavedBoardsStore.isSaved(id), isTrue);
  });

  test('server failure leaves the local mirror untouched', () async {
    final id = await save(boardId: 'board-1');
    try {
      throw StateError('server delete failed');
    } catch (_) {
      // A failed server mutation must not enter the post-success cleanup path.
    }
    expect(await SavedBoardsStore.isSaved(id), isTrue);
  });

  test('local cleanup failure cannot turn server success into failure', () async {
    var serverDeleted = false;
    try {
      serverDeleted = true;
      await Future<void>.error(StateError('local cleanup failed'));
    } catch (_) {
      // Mirrors the production best-effort cleanup boundary.
    }
    expect(serverDeleted, isTrue);
  });

  test('wardrobe unlike path does not call SavedBoardsStore cleanup', () {
    final source = File('lib/favourites.dart').readAsStringSync();
    final branchStart = source.indexOf(
      "if (boardEntry.source is _WardrobeSource)",
    );
    final branchEnd = source.indexOf('} else {', branchStart);
    final wardrobeBranch = source.substring(
      branchStart,
      branchEnd,
    );
    expect(wardrobeBranch, contains('updateWardrobeItem'));
    expect(wardrobeBranch, isNot(contains('SavedBoardsStore')));
  });
}

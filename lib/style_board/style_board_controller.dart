import 'package:flutter/foundation.dart';

import 'package:myapp/services/style_board_api_service.dart';
import 'style_board_state.dart';

typedef StyleBoardShuffleCall =
    Future<StyleBoardShuffleResult> Function(StyleBoardState board);

class StyleBoardController extends ChangeNotifier {
  StyleBoardState _state;
  StyleBoardState? _undo;
  final StyleBoardShuffleCall shuffleCall;
  bool _disposed = false;

  StyleBoardController({
    required StyleBoardState initialState,
    required this.shuffleCall,
  }) : _state = initialState;
  StyleBoardState get state => _state;
  bool get canUndo => _undo != null;

  void toggleLock(String itemId) {
    if (_state.isShuffling) return;
    final item = _state.items
        .where((item) => item.itemId == itemId)
        .firstOrNull;
    if (item == null || !item.isLockable) return;
    final next = {..._state.lockedItemIds};
    next.contains(itemId) ? next.remove(itemId) : next.add(itemId);
    _state = _state.copyWith(
      lockedItemIds: next,
      items: _state.items
          .map(
            (item) => item.itemId == itemId
                ? item.copyWith(isLocked: next.contains(itemId))
                : item,
          )
          .toList(),
    );
    notifyListeners();
  }

  void unlockAll() {
    if (_state.isShuffling) return;
    _state = _state.copyWith(
      lockedItemIds: {},
      items: _state.items
          .map((item) => item.copyWith(isLocked: false))
          .toList(),
    );
    notifyListeners();
  }

  Future<String?> shuffle() async {
    if (_state.isShuffling) return null;
    if (_state.allItemsLocked) return 'ALL_ITEMS_LOCKED';
    final snapshot = _state.deepCopy();
    _state = _state.copyWith(
      isShuffling: true,
      items: _state.items
          .map(
            (item) => item.copyWith(
              isRegenerating: !_state.lockedItemIds.contains(item.itemId),
            ),
          )
          .toList(),
    );
    notifyListeners();
    try {
      final result = await shuffleCall(snapshot);
      _validate(snapshot, result);
      if (_disposed) return null;
      final oldUnlocked = snapshot.items
          .where((item) => !snapshot.lockedItemIds.contains(item.itemId))
          .map((item) => item.itemId);
      final exclusions = <String>[
        ...snapshot.excludedItemIds,
        ...oldUnlocked.where((id) => id.isNotEmpty),
      ];
      _undo = snapshot;
      _state = StyleBoardState(
        boardId: result.boardId,
        revision: result.revision,
        previousRevision: result.previousRevision,
        items: result.items
            .map(
              (item) => item.copyWith(
                isLocked: snapshot.lockedItemIds.contains(item.itemId),
              ),
            )
            .toList(),
        lockedItemIds: snapshot.lockedItemIds,
        excludedItemIds: exclusions.reversed.toSet().take(25).toSet(),
      );
      notifyListeners();
      return null;
    } on StyleBoardApiException catch (error) {
      if (!_disposed) {
        _state = snapshot;
        notifyListeners();
      }
      return error.code;
    } catch (_) {
      if (!_disposed) {
        _state = snapshot;
        notifyListeners();
      }
      return 'UNKNOWN';
    }
  }

  void undo() {
    if (_undo == null || _state.isShuffling) return;
    final previous = _undo!;
    _undo = null;
    _state = previous;
    notifyListeners();
  }

  void _validate(StyleBoardState previous, StyleBoardShuffleResult result) {
    if (result.boardId != previous.boardId ||
        result.revision <= previous.revision ||
        !result.lockedItemsPreserved ||
        result.items.isEmpty) {
      throw const StyleBoardApiException('INVALID_SHUFFLE_RESPONSE');
    }
    final returned = {for (final item in result.items) item.itemId: item};
    for (final old in previous.items.where(
      (item) => previous.lockedItemIds.contains(item.itemId),
    )) {
      final next = returned[old.itemId];
      if (next == null ||
          old.source != next.source ||
          old.slot != next.slot ||
          old.imageUrl != next.imageUrl ||
          old.boardImageUrl != next.boardImageUrl ||
          old.maskedUrl != next.maskedUrl ||
          old.normalizedUrl != next.normalizedUrl ||
          old.position?.toJson().toString() !=
              next.position?.toJson().toString()) {
        throw const StyleBoardApiException('FIXED_ITEM_LOST');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

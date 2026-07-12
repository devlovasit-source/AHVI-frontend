import 'package:myapp/services/backend_service.dart';
import 'package:myapp/style_board/board_models.dart';
import 'package:myapp/style_board/style_board_state.dart';

class StyleBoardApiException implements Exception {
  final String code;
  const StyleBoardApiException(this.code);
}

class StyleBoardShuffleResult {
  final String boardId;
  final int revision;
  final int? previousRevision;
  final bool lockedItemsPreserved;
  final List<String> changedSlots;
  final List<StyleBoardItem> items;

  const StyleBoardShuffleResult({
    required this.boardId,
    required this.revision,
    this.previousRevision,
    required this.lockedItemsPreserved,
    required this.changedSlots,
    required this.items,
  });

  factory StyleBoardShuffleResult.fromJson(Map<String, dynamic> json) {
    if (json['success'] != true) {
      final error = json['error'];
      throw StyleBoardApiException(
        error is Map ? (error['code'] ?? 'UNKNOWN').toString() : 'UNKNOWN',
      );
    }
    final rawItems = json['board_items'];
    if (rawItems is! List) {
      throw const StyleBoardApiException('MALFORMED_RESPONSE');
    }
    return StyleBoardShuffleResult(
      boardId: (json['board_id'] ?? '').toString(),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      previousRevision: (json['previous_revision'] as num?)?.toInt(),
      lockedItemsPreserved: json['locked_items_preserved'] == true,
      changedSlots: (json['changed_slots'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      items: rawItems
          .whereType<Map>()
          .map((e) => StyleBoardItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class StyleBoardApiService {
  final BackendService? backend;
  const StyleBoardApiService([this.backend]);

  Map<String, dynamic> buildShufflePayload({
    required StyleBoardState board,
    String? occasion,
    String? styleDirection,
  }) {
    final locked = board.items.where(
      (item) => board.lockedItemIds.contains(item.itemId),
    );
    final slots = <String>{
      for (final item in board.items)
        if (!board.lockedItemIds.contains(item.itemId))
          item.role == BoardItemRole.accessory && item.accessoryType.isNotEmpty
              ? item.accessoryType
              : item.slot,
    }..removeWhere((slot) => slot.isEmpty);
    return {
      'scenario': 'shuffle_unlocked',
      'revision': board.revision,
      if (occasion?.trim().isNotEmpty == true) 'occasion': occasion!.trim(),
      if (styleDirection?.trim().isNotEmpty == true)
        'style_direction': styleDirection!.trim(),
      'locked_items': locked
          .map((item) => item.copyWith(isLocked: true).toContractJson())
          .toList(),
      'shuffle_slots': slots.toList(),
      'exclude_item_ids': board.excludedItemIds
          .where((id) => !board.lockedItemIds.contains(id))
          .toList(),
      'source_policy': 'inherit',
      'board_items': board.items.map((item) => item.toContractJson()).toList(),
    };
  }

  Future<StyleBoardShuffleResult> shuffle({
    required StyleBoardState board,
    String? occasion,
    String? styleDirection,
  }) async {
    final client = backend;
    if (client == null) {
      throw const StyleBoardApiException('CLIENT_NOT_CONFIGURED');
    }
    return StyleBoardShuffleResult.fromJson(
      await client.shuffleStyleBoard(
        boardId: board.boardId,
        payload: buildShufflePayload(
          board: board,
          occasion: occasion,
          styleDirection: styleDirection,
        ),
      ),
    );
  }
}

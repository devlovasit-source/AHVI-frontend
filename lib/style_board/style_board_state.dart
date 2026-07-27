import 'package:flutter/foundation.dart';

import 'board_models.dart';

@immutable
class StyleBoardState {
  /// Canonical board-level completion-source policies. The policy is an
  /// explicit backend contract - never inferred from item sources.
  static const Set<String> validSourcePolicies = {
    'wardrobe',
    'style_asset',
    'mixed',
  };

  final String boardId;
  final int revision;
  final List<StyleBoardItem> items;
  final Set<String> lockedItemIds;
  final Set<String> excludedItemIds;
  final bool isShuffling;
  final int? previousRevision;
  final String scenario;
  final String sourcePolicy;
  final bool allowWardrobeFallback;

  const StyleBoardState({
    required this.boardId,
    required this.revision,
    required this.items,
    this.lockedItemIds = const {},
    this.excludedItemIds = const {},
    this.isShuffling = false,
    this.previousRevision,
    this.scenario = '',
    this.sourcePolicy = '',
    this.allowWardrobeFallback = false,
  });

  bool get hasExplicitSourcePolicy =>
      validSourcePolicies.contains(sourcePolicy);

  bool get boardIdOk =>
      boardId.trim().isNotEmpty &&
      !boardId.trim().toLowerCase().startsWith('outfit_card_');
  bool get revisionOk => revision >= 1;
  bool get sourcePolicyOk => hasExplicitSourcePolicy;
  bool get stableItemIdsOk =>
      items.isNotEmpty && items.every((item) => item.hasStableIdentity);
  bool get positionsOk =>
      items.isNotEmpty && items.every((item) => item.position?.isUsable ?? false);
  bool get requestCarriedItemsOk =>
      items.isNotEmpty &&
      items.every(
        (item) =>
            item.raw.isNotEmpty &&
            item.source != 'unknown' &&
            item.role != BoardItemRole.unknown,
      );
  bool get canLock =>
      boardIdOk &&
      revisionOk &&
      sourcePolicyOk &&
      stableItemIdsOk &&
      requestCarriedItemsOk;
  bool get canShuffle => canLock;
  bool get supportsShuffle => canShuffle;
  List<String> get failedContractPredicates => [
    if (!boardIdOk) 'board_id',
    if (!revisionOk) 'revision',
    if (!sourcePolicyOk) 'source_policy',
    if (!stableItemIdsOk) 'stable_item_ids',
    if (!requestCarriedItemsOk) 'request_carried_items',
  ];
  bool get allItemsLocked =>
      items.isNotEmpty &&
      items.every((item) => lockedItemIds.contains(item.itemId));

  StyleBoardState copyWith({
    int? revision,
    List<StyleBoardItem>? items,
    Set<String>? lockedItemIds,
    Set<String>? excludedItemIds,
    bool? isShuffling,
    int? previousRevision,
  }) => StyleBoardState(
    boardId: boardId,
    revision: revision ?? this.revision,
    items: List.unmodifiable(items ?? this.items),
    lockedItemIds: Set.unmodifiable(lockedItemIds ?? this.lockedItemIds),
    excludedItemIds: Set.unmodifiable(excludedItemIds ?? this.excludedItemIds),
    isShuffling: isShuffling ?? this.isShuffling,
    previousRevision: previousRevision ?? this.previousRevision,
    scenario: scenario,
    sourcePolicy: sourcePolicy,
    allowWardrobeFallback: allowWardrobeFallback,
  );

  StyleBoardState deepCopy() => copyWith(
    items: items.map((item) => item.copyWith()).toList(),
    lockedItemIds: {...lockedItemIds},
    excludedItemIds: {...excludedItemIds},
  );
}

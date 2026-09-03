import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local saved-boards store backed by SharedPreferences.
///
/// Each saved board records the full editorial payload (cover,
/// direction, badge, owned/missing items, occasion, timestamp) so the
/// "Saved Boards" screen can rehydrate exactly what the user looked at.
///
/// Saves are idempotent: re-calling [saveBoard] with the same
/// canonical id silently updates the existing entry instead of
/// duplicating it.
class SavedBoardsStore {
  static const _kStorageKey = 'ahvi.saved_boards.v1';
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _instance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @visibleForTesting
  static void resetForTest() {
    _prefs = null;
  }

  @visibleForTesting
  static Future<void> clearForTest() async {
    final prefs = await _instance();
    await prefs.remove(_kStorageKey);
  }

  /// Build a stable id from the occasion + direction so the same look
  /// saved twice doesn't double-store.
  static String idFor({required String occasion, required String directionName}) {
    final raw = '${occasion.trim().toLowerCase()}::${directionName.trim().toLowerCase()}';
    return raw.replaceAll(RegExp(r'\s+'), '_');
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await _instance();
    final raw = prefs.getString(_kStorageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
    } catch (_) {/* corrupt cache — wipe quietly */}
    await prefs.remove(_kStorageKey);
    return const [];
  }

  static Future<bool> isSaved(String id) async {
    if (id.isEmpty) return false;
    final current = await list();
    return current.any((b) => b['id'] == id);
  }

  /// Persist a board. Idempotent — keyed on the supplied id (or a
  /// generated one if none).
  static Future<void> saveBoard({
    required String occasion,
    required String directionName,
    required Map<String, dynamic> direction,
    Map<String, dynamic> editorialCover = const {},
  }) async {
    final prefs = await _instance();
    final id = idFor(occasion: occasion, directionName: directionName);
    final payload = <String, dynamic>{
      'id': id,
      'board_id': direction['board_id'] ?? direction['boardId'] ?? '',
      'occasion': occasion,
      'direction_name': directionName,
      'created_at': DateTime.now().toIso8601String(),
      'editorial_cover': editorialCover,
      'direction': direction,
      'adjectives': direction['adjectives'] ?? const [],
      'short_note':
          direction['short_note'] ?? direction['why_it_works'] ?? '',
      'badge': direction['badge'] ?? const {},
      'curated_for': direction['curated_for'] ?? const [],
      'complete_the_look_copy': direction['complete_the_look_copy'] ?? '',
      'owned_items': direction['owned_items'] ?? const [],
      'missing_items': direction['missing_piece'] is Map
          ? [direction['missing_piece']]
          : (direction['missing_items'] ?? const []),
    };

    final current = await list();
    final filtered = current.where((b) => b['id'] != id).toList();
    filtered.insert(0, payload);
    // Bound storage growth so the prefs entry stays well inside platform
    // limits even after months of saves.
    if (filtered.length > 60) filtered.removeRange(60, filtered.length);
    await prefs.setString(_kStorageKey, jsonEncode(filtered));
  }

  static Future<void> remove(String id) async {
    final prefs = await _instance();
    final current = await list();
    final filtered = current.where((b) => b['id'] != id).toList();
    await prefs.setString(_kStorageKey, jsonEncode(filtered));
  }

  /// Removes the local Saved mirror after the corresponding server board was
  /// deleted. Canonical board identity wins; the legacy id is only used for
  /// entries that predate board_id persistence.
  static Future<void> removeForServerBoard(Map<String, dynamic> data) async {
    final boardId = (data['board_id'] ?? data['boardId'] ?? '')
        .toString()
        .trim();
    final occasion = (data['occasion'] ?? data['original_occasion'] ?? '')
        .toString();
    final directionName = (data['title'] ?? data['direction_name'] ?? '')
        .toString();
    final legacyId = occasion.trim().isNotEmpty && directionName.trim().isNotEmpty
        ? idFor(occasion: occasion, directionName: directionName)
        : '';
    if (boardId.isEmpty && legacyId.isEmpty) return;

    final prefs = await _instance();
    final current = await list();
    final filtered = current.where((entry) {
      final entryBoardId = (entry['board_id'] ?? '').toString().trim();
      if (boardId.isNotEmpty) {
        if (entryBoardId.isNotEmpty) return entryBoardId != boardId;
        return legacyId.isEmpty || entry['id'] != legacyId;
      }
      // A legacy server payload can only remove a legacy local entry.
      return entryBoardId.isNotEmpty ||
          legacyId.isEmpty ||
          entry['id'] != legacyId;
    }).toList();
    if (filtered.length != current.length) {
      await prefs.setString(_kStorageKey, jsonEncode(filtered));
    }
  }
}

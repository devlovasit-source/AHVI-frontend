import 'dart:convert';

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

  /// Build a stable id from the occasion + direction so the same look
  /// saved twice doesn't double-store.
  static String idFor({
    required String occasion,
    required String directionName,
  }) {
    final raw =
        '${occasion.trim().toLowerCase()}::${directionName.trim().toLowerCase()}';
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
    } catch (_) {
      /* corrupt cache — wipe quietly */
    }
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
      'occasion': occasion,
      'direction_name': directionName,
      'board_id': direction['board_id'] ?? direction['boardId'] ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'editorial_cover': editorialCover,
      'direction': direction,
      'adjectives': direction['adjectives'] ?? const [],
      'short_note': direction['short_note'] ?? direction['why_it_works'] ?? '',
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

  static Future<void> removeForServerBoard(
    Map<String, dynamic> serverData,
  ) async {
    final prefs = await _instance();
    final current = await list();

    String decodeText(Object? value) {
      return value?.toString().trim() ?? '';
    }

    Map<String, dynamic> decodeMaster(Object? value) {
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }

      if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }

      return const {};
    }

    final master = decodeMaster(serverData['masterGarment']);

    final serverBoardId = decodeText(
      master['board_id'] ?? serverData['boardId'] ?? serverData['board_id'],
    );

    final serverTitle = decodeText(
      master['title'] ?? serverData['title'] ?? serverData['direction_name'],
    );

    final serverOccasion = decodeText(
      master['original_occasion'] ??
          serverData['original_occasion'] ??
          serverData['occasion'],
    );

    final fallbackId = serverTitle.isNotEmpty && serverOccasion.isNotEmpty
        ? idFor(occasion: serverOccasion, directionName: serverTitle)
        : '';

    final filtered = current.where((board) {
      final localBoardId = decodeText(board['board_id']);
      final localId = decodeText(board['id']);

      if (serverBoardId.isNotEmpty &&
          localBoardId.isNotEmpty &&
          localBoardId == serverBoardId) {
        return false;
      }

      if (fallbackId.isNotEmpty && localId == fallbackId) {
        return false;
      }

      return true;
    }).toList();

    await prefs.setString(_kStorageKey, jsonEncode(filtered));
  }

  static Future<void> clearAll() async {
    final prefs = await _instance();
    await prefs.remove(_kStorageKey);
  }
}

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

  /// Drops the cached [SharedPreferences] instance so the next call
  /// re-fetches it. SharedPreferences caches its data in memory once
  /// loaded, so `SharedPreferences.setMockInitialValues(...)` between
  /// tests has no effect on an instance this store already cached —
  /// call this in `setUp()` alongside `setMockInitialValues` to get a
  /// clean store per test.
  @visibleForTesting
  static void resetForTest() {
    _prefs = null;
  }

  /// Wipes this store's data outright. Belt-and-braces alongside
  /// [resetForTest]: `SharedPreferences.getInstance()` caches its own
  /// singleton internally, so even after dropping our [_prefs] reference,
  /// the next `getInstance()` call can hand back an already-loaded
  /// instance whose in-memory cache still has data from a previous test.
  /// Explicitly removing our key guarantees a clean slate regardless of
  /// whichever instance we get back.
  @visibleForTesting
  static Future<void> clearForTest() async {
    final prefs = await _instance();
    await prefs.remove(_kStorageKey);
  }

  /// Build a stable id from the occasion + direction so the same look
  /// saved twice doesn't double-store.

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
      'board_id': direction['board_id'] ?? direction['boardId'] ?? '',
      'occasion': occasion,
      'direction_name': directionName,
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

  /// Clears the local "Saved" mirror for a board that was just deleted on
  /// the server (Appwrite).
  ///
  /// The chat Save button and the Boards screen use two different identity
  /// schemes for the same look: this store keys entries by a hash of
  /// occasion + direction/title, while the server deletion path only knows
  /// the canonical `board_id` (or the Appwrite document id). If the local
  /// mirror is never cleared here, the chat button keeps showing "Saved"
  /// forever for that occasion/direction combo, even after the board is
  /// gone from Appwrite.
  ///
  /// [data] should be the (expanded) saved-board document data — it may
  /// contain `board_id`/`boardId` and/or `occasion`/`title` (or
  /// `direction_name`). Matches on canonical `board_id` first, then falls
  /// back to the legacy occasion+direction id so older local entries saved
  /// before `board_id` was tracked still get cleaned up.
  static Future<void> removeForServerBoard(Map<String, dynamic> data) async {
    final boardId = (data['board_id'] ?? data['boardId'] ?? '')
        .toString()
        .trim();
    final occasion = (data['occasion'] ?? data['original_occasion'] ?? '')
        .toString();
    final directionName = (data['title'] ?? data['direction_name'] ?? '')
        .toString();
    final legacyId =
        (occasion.trim().isNotEmpty && directionName.trim().isNotEmpty)
        ? idFor(occasion: occasion, directionName: directionName)
        : '';

    if (boardId.isEmpty && legacyId.isEmpty) return;

    final prefs = await _instance();
    final current = await list();
    final filtered = current.where((b) {
      final entryBoardId = (b['board_id'] ?? '').toString();
      final entryHasCanonicalId = entryBoardId.isNotEmpty;

      if (boardId.isNotEmpty && entryHasCanonicalId) {
        // Entry has its own canonical id — only an exact board_id match removes it.
        return entryBoardId != boardId;
      }

      // Entry predates board_id tracking (or we have no incoming board_id) —
      // fall back to the legacy occasion+direction id.
      if (legacyId.isNotEmpty && b['id'] == legacyId) return false;
      return true;
    }).toList();

    if (filtered.length == current.length) return;
    await prefs.setString(_kStorageKey, jsonEncode(filtered));
  }
}

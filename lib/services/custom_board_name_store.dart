import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const customBoardNamesStorageKey = 'ahvi.custom_board_names.v1';

List<String> normalizeCustomBoardNames(Iterable<Object?> values) {
  final names = <String>[];
  final seen = <String>{};
  for (final value in values) {
    if (value is! String) continue;
    final name = value.trim();
    final key = name.toLowerCase();
    if (name.isEmpty || !seen.add(key)) continue;
    names.add(name);
  }
  return names;
}

@visibleForTesting
List<String> decodeCustomBoardNames(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return normalizeCustomBoardNames(decoded);
  } catch (_) {
    return const [];
  }
}

class CustomBoardNameStore {
  Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeCustomBoardNames(
        prefs.getString(customBoardNamesStorageKey),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(Iterable<String> names) async {
    final normalized = normalizeCustomBoardNames(names);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(customBoardNamesStorageKey, jsonEncode(normalized));
  }
}

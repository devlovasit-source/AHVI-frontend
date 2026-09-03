const presetOccasionKeys = <String>{
  'everyday',
  'casual',
  'work',
  'dinner',
  'travel',
  'sport',
  'party',
  'festive',
  'wedding',
};

String _occasionToken(String raw) {
  var value = raw.trim().toLowerCase();
  value = value.replaceFirst(
    RegExp(r'^upload_occasion_', caseSensitive: false),
    '',
  );
  return value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Returns a stable semantic key. Unknown values remain custom values; only
/// observed backend aliases are mapped.
String canonicalOccasionKey(String raw) {
  final value = _occasionToken(raw);
  switch (value) {
    case 'everyday':
      return 'everyday';
    case 'work':
    case 'office':
      return 'work';
    case 'workout':
      return 'sport';
    case 'casual':
    case 'dinner':
    case 'travel':
    case 'sport':
    case 'party':
    case 'festive':
    case 'wedding':
      return value;
    default:
      return value.replaceAll(' ', '_');
  }
}

String _titleCaseOccasion(String value) => value
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
    .join(' ');

String humanizeOccasion(String raw) {
  final key = canonicalOccasionKey(raw);
  if (key.isEmpty) return '';
  return _titleCaseOccasion(key.replaceAll('_', ' '));
}

List<String> canonicalOccasions(Iterable<String> values) {
  final seen = <String>{};
  final canonical = <String>[];
  for (final raw in values) {
    final key = canonicalOccasionKey(raw);
    final label = humanizeOccasion(raw);
    if (key.isEmpty || label.isEmpty || !seen.add(key)) continue;
    canonical.add(label);
  }
  return canonical;
}

/// Normalizes known preset aliases while preserving the user's custom value.
/// Manual tags are backend-authoritative metadata, not automatic occasions.
List<String> preserveOccasionValues(Iterable<String> values) {
  final seen = <String>{};
  final preserved = <String>[];
  for (final raw in values) {
    final trimmed = raw.trim();
    final key = canonicalOccasionKey(trimmed);
    if (key.isEmpty || !seen.add(key)) continue;
    preserved.add(isPresetOccasion(trimmed) ? humanizeOccasion(trimmed) : trimmed);
  }
  return preserved;
}

bool occasionMatches(String a, String b) {
  final left = canonicalOccasionKey(a);
  final right = canonicalOccasionKey(b);
  return left.isNotEmpty && left == right;
}

bool isPresetOccasion(String raw) =>
    presetOccasionKeys.contains(canonicalOccasionKey(raw));

/// Toggles a value while removing all raw aliases of the same semantic value.
List<String> toggleOccasion(List<String> existing, String value) {
  final wasSelected = existing.any((item) => occasionMatches(item, value));
  final withoutMatch = existing
      .where((item) => !occasionMatches(item, value))
      .toList(growable: false);
  return wasSelected ? withoutMatch : [...withoutMatch, value.trim()];
}

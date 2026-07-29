String sanitizeUtf16(String value) {
  final output = StringBuffer();
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 < units.length) {
        final low = units[index + 1];
        if (low >= 0xDC00 && low <= 0xDFFF) {
          output.writeCharCode(
            0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00),
          );
          index++;
          continue;
        }
      }
      output.writeCharCode(0xFFFD);
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      output.writeCharCode(0xFFFD);
    } else {
      output.writeCharCode(unit);
    }
  }
  return output.toString();
}

Object? sanitizeUtf16Deep(Object? value) {
  if (value is String) return sanitizeUtf16(value);
  if (value is List) return value.map(sanitizeUtf16Deep).toList();
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        sanitizeUtf16(entry.key.toString()): sanitizeUtf16Deep(entry.value),
    };
  }
  return value;
}

String truncateSafeText(String value, int maxRunes, {String suffix = ''}) {
  final safe = sanitizeUtf16(value);
  if (maxRunes < 1) return suffix;
  final runes = safe.runes.toList(growable: false);
  if (runes.length <= maxRunes) return safe;
  return '${String.fromCharCodes(runes.take(maxRunes))}$suffix';
}

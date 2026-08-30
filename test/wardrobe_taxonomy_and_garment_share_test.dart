import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// PR #41 removed "lehenga" and "sherwani" from _cleanCategory's Dresses
// classification list (lib/wardrobe.dart) as an unintended side effect of
// an unrelated refactor. This is an explicit RC3 protected contract:
// PR #41's Indian-garment taxonomy removal must never be accepted.
//
// _cleanCategory is a library-private top-level function (leading
// underscore), so it isn't callable from a separate test library import --
// this asserts against the source text directly, the same pattern PR #41's
// own test suite already uses elsewhere in this repo for private-function
// contracts (see test/daily_wear_precedence_test.dart's source-inspection
// tests).
void main() {
  group('Indian garment taxonomy preserved (RC3 protected contract)', () {
    late String source;

    setUpAll(() {
      source = File('lib/wardrobe.dart').readAsStringSync().replaceAll('\r\n', '\n');
    });

    String dressesCategoryBlock() {
      final start = source.indexOf("String _cleanCategory(");
      expect(start, greaterThan(-1), reason: '_cleanCategory not found in lib/wardrobe.dart');
      // The Dresses classification list is the first list literal inside
      // the function -- bound the search to a generous window after the
      // function start rather than requiring an exact closing brace match.
      final end = (start + 8000).clamp(0, source.length);
      return source.substring(start, end);
    }

    test('lehenga remains correctly classified as a dress-category garment', () {
      final block = dressesCategoryBlock();
      expect(block, contains("'lehenga'"),
          reason: 'lehenga must remain in the Dresses classification list');
    });

    test('sherwani remains correctly classified as a dress-category garment', () {
      final block = dressesCategoryBlock();
      expect(block, contains("'sherwani'"),
          reason: 'sherwani must remain in the Dresses classification list');
    });
  });

  group('Wardrobe Garment Share (RC3 ported feature)', () {
    late String source;

    setUpAll(() {
      source = File('lib/wardrobe.dart').readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('shareGarmentImage function exists and shares image + metadata', () {
      expect(source, contains('Future<void> shareGarmentImage('));
      final start = source.indexOf('Future<void> shareGarmentImage(');
      var end = source.indexOf('\n}\n', start);
      if (end == -1) end = (start + 1800).clamp(0, source.length);
      final fn = source.substring(start, end);
      expect(fn, contains('Share.shareXFiles('));
      expect(fn, contains('Share.share('));
      expect(fn, contains('Category: \${_cleanCategory(category)}'));
    });

    test('_shareItem delegates to shareGarmentImage with garment metadata', () {
      final start = source.indexOf('Future<void> _shareItem(');
      expect(start, greaterThan(-1));
      var end = source.indexOf('\n  }\n', start);
      if (end == -1) end = (start + 400).clamp(0, source.length);
      final fn = source.substring(start, end);
      expect(fn, contains('shareGarmentImage('));
      expect(fn, contains('imageBytes: item.imageBytes'));
      expect(fn, contains('imageUrl: item.displayUrl'));
    });
  });
}

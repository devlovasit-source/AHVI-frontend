import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/custom_board_name_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Custom board name persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('malformed payload fails safely', () {
      expect(decodeCustomBoardNames('{not-json'), isEmpty);
      expect(decodeCustomBoardNames(jsonEncode({'name': 'Gym'})), isEmpty);
      expect(decodeCustomBoardNames(jsonEncode([null, 42, '  '])), isEmpty);
    });

    test('add persists through a fresh store instance', () async {
      final first = CustomBoardNameStore();
      await first.save(['Gym']);

      final recreated = CustomBoardNameStore();
      expect(await recreated.load(), ['Gym']);
    });

    test('remove persists and duplicate names are safe', () async {
      final store = CustomBoardNameStore();
      await store.save(['Gym', ' gym ', 'Travel']);
      expect(await store.load(), ['Gym', 'Travel']);

      await store.save(['Travel']);
      expect(await CustomBoardNameStore().load(), ['Travel']);
    });

    test('empty stored value preserves the old empty state', () async {
      final store = CustomBoardNameStore();
      expect(await store.load(), isEmpty);
      await store.save(const []);
      expect(await store.load(), isEmpty);
    });
  });
}

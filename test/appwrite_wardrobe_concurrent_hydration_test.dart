// P0.2 REGRESSION: Style This renders a blank board.
//
// AhviOutfitBoardCard._fetchWardrobeForBoard calls
// getWardrobeItems(forceRefresh: true). Every forceRefresh bumps
// _wardrobeGeneration. A chat turn renders MORE THAN ONE board card, and each
// card hydrates itself, so two forceRefresh fetches overlap routinely.
//
// b5dcc9b removed the two graceful fallbacks that used to rescue a superseded
// fetch (return the replacement in-flight future, else the current cache), so
// the loser of that race now throws StateError instead of returning data --
// and its result is never published to _wardrobeCache. The card catches the
// error, releases its retry latch, and re-fetches on the next
// notifyListeners(), which bumps the generation again. The cache spends its
// life unpublished, cachedWardrobeItems returns [], the effective wardrobe map
// is empty, and every garment is dropped: 3 selected items -> 0 rendered.
//
// These tests must FAIL before the fix and pass after.
import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _User extends Fake implements User {
  _User(this.$id);
  @override
  final String $id;
  @override
  String get email => '${$id}@example.test';
}

class _Account extends Fake implements Account {
  String userId = 'A';
  @override
  Future<User> get() async => _User(userId);
}

class _Databases extends Fake implements Databases {
  Future<DocumentList> Function(List<Map<String, dynamic>>) handler =
      (_) async => _page([]);
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listDocuments) {
      calls++;
      final queries = invocation.namedArguments[#queries] as List<String>;
      return handler(
        queries.map((q) => jsonDecode(q) as Map<String, dynamic>).toList(),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

DocumentList _page(List<String> ids, {int? total}) => DocumentList(
  total: total ?? ids.length,
  documents: ids
      .map(
        (id) => Document(
          $id: id,
          $sequence: '1',
          $collectionId: 'outfits',
          $databaseId: 'db',
          $createdAt: '2026-01-01T00:00:00Z',
          $updatedAt: '2026-01-01T00:00:00Z',
          $permissions: [],
          data: {
            'name': id,
            'category': 'Tops',
            'raw_url': 'https://example.test/$id',
            'masked_url': 'https://example.test/wardrobe_$id.png',
          },
        ),
      )
      .toList(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => r'C:\Users\USER\AppData\Local\Temp\opencode',
      );

  late AppwriteService service;
  late _Databases db;

  setUp(() {
    dotenv.loadFromString(
      envString:
          'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test/v1\n'
          'EXPO_PUBLIC_APPWRITE_PROJECT_ID=test\n'
          'EXPO_PUBLIC_APPWRITE_DATABASE_ID=db\n'
          'EXPO_PUBLIC_APPWRITE_COLLECTION_OUTFITS=outfits',
    );
    SharedPreferences.setMockInitialValues({});
    service = AppwriteService();
    service.clearUserCache();
    service.account = _Account();
    db = _Databases();
    service.databases = db;
  });

  tearDown(() => service.clearUserCache());

  // The three garments of a Style This board.
  const board = ['top-1', 'bottom-1', 'shoe-1'];

  test(
    'two board cards hydrating concurrently both receive the wardrobe '
    '(neither is thrown away as "superseded")',
    () async {
      db.handler = (queries) async {
        final isPrimary = queries.firstWhere(
              (q) => q['method'] == 'equal',
            )['attribute'] ==
            'userId';
        // Let both fetches be genuinely in flight at the same time, which is
        // what two cards mounting in one frame produce.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _page(isPrimary ? board : const []);
      };

      final cardA = service.getWardrobeItems(forceRefresh: true);
      final cardB = service.getWardrobeItems(forceRefresh: true);
      final results = await Future.wait([cardA, cardB]);

      for (final r in results) {
        expect(
          r.map((i) => i['id']),
          containsAll(board),
          reason: 'a concurrent hydration must not lose the wardrobe',
        );
      }
    },
  );

  test(
    'the wardrobe cache is published after concurrent forceRefresh '
    'hydration, so cachedWardrobeItems is not empty',
    () async {
      db.handler = (queries) async {
        final isPrimary = queries.firstWhere(
              (q) => q['method'] == 'equal',
            )['attribute'] ==
            'userId';
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _page(isPrimary ? board : const []);
      };

      await Future.wait([
        service.getWardrobeItems(forceRefresh: true),
        service.getWardrobeItems(forceRefresh: true),
      ]);

      expect(
        service.cachedWardrobeItems.map((i) => i['id']),
        containsAll(board),
        reason:
            'an empty cache here is exactly what blanks the Style board: the '
            'effective wardrobe map has no records, so every garment drops',
      );
    },
  );

  test(
    'three cards (a realistic carousel) still publish the wardrobe',
    () async {
      db.handler = (queries) async {
        final isPrimary = queries.firstWhere(
              (q) => q['method'] == 'equal',
            )['attribute'] ==
            'userId';
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _page(isPrimary ? board : const []);
      };

      await Future.wait([
        service.getWardrobeItems(forceRefresh: true),
        service.getWardrobeItems(forceRefresh: true),
        service.getWardrobeItems(forceRefresh: true),
      ]);

      expect(service.cachedWardrobeItems.map((i) => i['id']), containsAll(board));
    },
  );
}

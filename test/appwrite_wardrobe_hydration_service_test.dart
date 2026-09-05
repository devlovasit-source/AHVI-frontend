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
  Future<User> Function()? read;
  final deleting = Completer<void>();
  final deleted = Completer<void>();

  @override
  Future<User> get() => read?.call() ?? Future.value(_User(userId));

  @override
  Future<dynamic> deleteSessions() async {
    deleting.complete();
    await deleted.future;
  }
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
      return handler(queries.map((q) => jsonDecode(q) as Map<String, dynamic>).toList());
    }
    return super.noSuchMethod(invocation);
  }
}

DocumentList _page(List<String> ids, {int? total}) => DocumentList(
  total: total ?? ids.length,
  documents: ids.map((id) => Document(
    $id: id,
    $sequence: '1',
    $collectionId: 'outfits',
    $databaseId: 'db',
    $createdAt: '2026-01-01T00:00:00Z',
    $updatedAt: '2026-01-01T00:00:00Z',
    $permissions: [],
    data: {'name': id, 'category': 'Tops', 'raw_url': 'https://example.test/$id'},
  )).toList(),
);

String _field(List<Map<String, dynamic>> queries) =>
    queries.firstWhere((q) => q['method'] == 'equal')['attribute'] as String;

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => r'C:\Users\USER\AppData\Local\Temp\opencode',
      );
  late AppwriteService service;
  late _Account account;
  late _Databases db;
  late List<List<Map<String, dynamic>>> writes;

  setUp(() {
    dotenv.loadFromString(envString:
      'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test/v1\n'
      'EXPO_PUBLIC_APPWRITE_PROJECT_ID=test\n'
      'EXPO_PUBLIC_APPWRITE_DATABASE_ID=db\n'
      'EXPO_PUBLIC_APPWRITE_COLLECTION_OUTFITS=outfits');
    SharedPreferences.setMockInitialValues({});
    service = AppwriteService();
    service.clearUserCache();
    account = _Account();
    db = _Databases();
    service.account = account;
    service.databases = db;
    writes = [];
    service.attachOfflineWriteThrough(onWardrobe: writes.add);
  });

  tearDown(() {
    service.attachOfflineWriteThrough();
    service.clearUserCache();
  });

  test('N paginates both owner fields and deduplicates selected item beyond 100', () async {
    final primary = List.generate(205, (i) => 'item-$i');
    final legacy = [...primary.take(100), 'legacy-selected'];
    db.handler = (queries) async {
      final ids = _field(queries) == 'userId' ? primary : legacy;
      final cursors = queries.where((q) => q['method'] == 'cursorAfter');
      final start = cursors.isEmpty ? 0 : ids.indexOf(cursors.single['values'][0] as String) + 1;
      return _page(ids.skip(start).take(100).toList(), total: ids.length);
    };
    final items = await service.getWardrobeItems();
    expect(items.length, 206);
    expect(items.map((i) => i['id']), containsAll(['item-204', 'legacy-selected']));
    expect(db.calls, 5);
    expect(writes.single, hasLength(206));
  });

  test('empty successful wardrobe is cached, not treated as failure', () async {
    expect(await service.getWardrobeItems(), isEmpty);
    expect(await service.getWardrobeItems(), isEmpty);
    expect(db.calls, 2);
    expect(writes, hasLength(1));
  });

  test('explicit missing legacy attribute permits primary schema hydration', () async {
    db.handler = (queries) async {
      if (_field(queries) == 'user_id') {
        throw AppwriteException('Invalid query: Attribute not found in schema: user_id',
            400, 'general_query_invalid');
      }
      return _page(['primary']);
    };
    expect((await service.getWardrobeItems()).single['id'], 'primary');
  });

  for (final failedFields in [1, 2]) {
    test('failed $failedFields owner queries reject without partial/empty write-through', () async {
      db.handler = (queries) async {
        if (failedFields == 2 || _field(queries) == 'user_id') {
          throw AppwriteException('Service unavailable', 503);
        }
        return _page(['selected']);
      };
      await expectLater(service.getWardrobeItems(), throwsA(isA<AppwriteException>()));
      expect(service.cachedWardrobeItems, isEmpty);
      expect(writes, isEmpty);
      db.handler = (_) async => _page(['recovered']);
      expect((await service.getWardrobeItems()).single['id'], 'recovered');
    });
  }

  test('later page failure never publishes a truncated selected board input', () async {
    db.handler = (queries) async {
      if (_field(queries) == 'user_id') return _page([]);
      if (queries.any((q) => q['method'] == 'cursorAfter')) {
        throw AppwriteException('Service unavailable', 503);
      }
      return _page(List.generate(100, (i) => 'item-$i'), total: 101);
    };
    await expectLater(service.getWardrobeItems(), throwsA(isA<AppwriteException>()));
    expect(writes, isEmpty);
  });

  test('O coalesced callers reject old session and leave new cache intact', () async {
    final pending = Completer<DocumentList>();
    db.handler = (_) => pending.future;
    final first = service.getWardrobeItems();
    final joined = service.getWardrobeItems();
    final firstCheck = expectLater(first, throwsStateError);
    final joinedCheck = expectLater(joined, throwsStateError);
    await _tick();
    service.clearUserCache();
    account.userId = 'B';
    db.handler = (_) async => _page(['B-item']);
    await service.getWardrobeItems();
    pending.complete(_page(['A-item']));
    await Future.wait([firstCheck, joinedCheck]);
    expect(service.cachedWardrobeItems.single['id'], 'B-item');
    expect(writes, hasLength(1));
  });

  test('F invalidation rejects all callers without replacement', () async {
    final pending = Completer<DocumentList>();
    db.handler = (_) => pending.future;
    final first = expectLater(service.getWardrobeItems(), throwsStateError);
    final joined = expectLater(service.getWardrobeItems(), throwsStateError);
    await _tick();
    service.invalidateWardrobeCache();
    pending.complete(_page(['obsolete']));
    await Future.wait([first, joined]);
    expect(writes, isEmpty);
  });

  test('F replacement forwarding stays session guarded', () async {
    final old = Completer<DocumentList>();
    final replacement = Completer<DocumentList>();
    db.handler = (_) => old.future;
    final first = expectLater(service.getWardrobeItems(), throwsStateError);
    await _tick();
    service.invalidateWardrobeCache();
    db.handler = (_) => replacement.future;
    final second = expectLater(service.getWardrobeItems(), throwsStateError);
    await _tick();
    old.complete(_page(['obsolete']));
    await _tick();
    service.clearUserCache();
    replacement.complete(_page(['old-session']));
    await Future.wait([first, second]);
    expect(writes, isEmpty);
  });

  test('O pending identity read cannot repopulate identity after scope switch', () async {
    final pending = Completer<User>();
    account.read = () => pending.future;
    final old = service.getCurrentUser();
    service.clearUserCache();
    account.read = null;
    account.userId = 'B';
    await service.cacheCurrentUser();
    pending.complete(_User('A'));
    expect(await old, isNull);
    expect(service.currentUserId, 'B');
    expect(await service.getCachedUserId(), 'B');
  });

  test('O logout clears immediately and refuses reads while SDK deletion waits', () async {
    db.handler = (_) async => _page(['A-item']);
    await service.getWardrobeItems();
    final logout = service.logout();
    final immediateCache = service.cachedWardrobeItems;
    await account.deleting.future;
    final readCheck = expectLater(service.getWardrobeItems(), throwsStateError);
    account.deleted.complete();
    await logout;
    await readCheck;
    expect(immediateCache, isEmpty);
    expect(service.cachedWardrobeItems, isEmpty);
    expect(service.currentUserId, isNull);
  });
}

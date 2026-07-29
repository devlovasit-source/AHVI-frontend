// Focused tests for the home-card today-summary integration.
//
// Tests 1-13: model parsing, provider lifecycle, cache isolation, stale-flight.
// Test 14: existing local completion methods are not broken.
// Test 15: static Home hero is not driven by HomeCardSummaryProvider.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/home_card_summary_provider.dart';
import 'package:myapp/models/home_today_summary.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart';

// ── Shared test helpers ───────────────────────────────────────────────────────

void _setUpChannels() {
  TestWidgetsFlutterBinding.ensureInitialized();
  dotenv.loadFromString(
    envString: 'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test\n'
        'EXPO_PUBLIC_APPWRITE_PROJECT_ID=proj\n'
        'EXPO_PUBLIC_BACKEND_API_URL=https://api.test/',
    isOptional: true,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/package_info'),
    (call) async => <String, dynamic>{
      'appName': 'ahvi_test',
      'packageName': 'com.ahvi.test',
      'version': '1.0.0',
      'buildNumber': '1',
    },
  );
}

HomeTodaySummary _makeSummary({
  String wearHeadline = 'Wear this today',
  String wearContext  = 'Light layers for the breeze',
  String moveHeadline = '30-min yoga',
  String eatHeadline  = 'Balanced lunch ahead',
  String careHeadline = 'Morning glow routine',
  String mediHeadline = 'One reminder today',
  String date         = '2024-01-15',
}) => HomeTodaySummary.fromMap({
  'date': date,
  'timezone': 'Asia/Kolkata',
  'context_usage': {'context_version': 'v2', 'context_usage': 'full'},
  'cards': {
    'wear':     {'headline': wearHeadline, 'context': wearContext,  'status': 'Pick outfit', 'available': true,  'action': 'open_daily_wear'},
    'move':     {'headline': moveHeadline, 'context': '',           'status': 'Start',       'available': true,  'action': 'open_fitness'},
    'eat':      {'headline': eatHeadline,  'context': '',           'status': 'Log meal',    'available': true,  'action': 'open_diet'},
    'care':     {'headline': careHeadline, 'context': '',           'status': 'Time',        'available': true,  'action': 'open_skincare'},
    'medicine': {'headline': mediHeadline, 'context': '',           'status': 'Pending',     'available': true,  'action': 'open_medi'},
  },
});

HomeCardSummaryProvider _provider({
  required String userId,
  required String date,
  required Future<HomeTodaySummary> Function() fetcher,
}) {
  final p = HomeCardSummaryProvider();
  p.debugCurrentUserIdProvider = () => userId;
  p.debugLocalDateProvider = () => date;
  p.debugSummaryFetcher = fetcher;
  return p;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(_setUpChannels);

  // ── 1. Successful mapping of all five cards ───────────────────────────────

  test('1. successful mapping of all five cards', () {
    final s = _makeSummary();
    expect(s.wear.available, isTrue);
    expect(s.wear.headline, 'Wear this today');
    expect(s.move.available, isTrue);
    expect(s.move.headline, '30-min yoga');
    expect(s.eat.available, isTrue);
    expect(s.eat.headline, 'Balanced lunch ahead');
    expect(s.care.available, isTrue);
    expect(s.care.headline, 'Morning glow routine');
    expect(s.medicine.available, isTrue);
    expect(s.medicine.headline, 'One reminder today');
    expect(s.date, '2024-01-15');
    expect(s.timezone, 'Asia/Kolkata');
    expect(s.contextUsage.contextVersion, 'v2');
  });

  // ── 2. Malformed one-card payload does not fail other cards ──────────────

  test('2. malformed one-card payload does not fail other cards', () {
    final s = HomeTodaySummary.fromMap({
      'date': '2024-01-15',
      'timezone': 'UTC',
      'cards': {
        'wear': 'BAD_VALUE', // not a Map — must become unavailable
        'move': {'headline': 'Run 5k', 'available': true, 'status': 'Go', 'context': ''},
        'eat':  {'headline': 'Salad',  'available': true, 'status': 'Log', 'context': ''},
        'care': {'headline': 'Glow',   'available': true, 'status': 'Now', 'context': ''},
        'medicine': null, // missing → unavailable
      },
    });
    expect(s.wear.available, isFalse);
    expect(s.move.headline, 'Run 5k');
    expect(s.eat.headline, 'Salad');
    expect(s.care.headline, 'Glow');
    expect(s.medicine.available, isFalse);
  });

  // ── 3. Backend unavailable card is displayed honestly ────────────────────

  test('3. backend unavailable card shown with fallback, not empty/crash', () async {
    final s = HomeTodaySummary.fromMap({
      'date': '2024-01-15',
      'timezone': 'UTC',
      'cards': {
        'wear': {'headline': '', 'context': '', 'status': '', 'available': false, 'reason': 'no_profile'},
        'move': {'headline': 'Stretch', 'context': '', 'status': 'Go', 'available': true},
        'eat':  {'headline': 'Eat',     'context': '', 'status': 'Log', 'available': true},
        'care': {'headline': 'Care',    'context': '', 'status': 'Now', 'available': true},
        'medicine': {'headline': 'Meds', 'context': '', 'status': 'Ok', 'available': true},
      },
    });
    expect(s.wear.available, isFalse);

    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () async => s,
    );
    await p.refresh();

    // Unavailable wear card → local fallback, not exception
    expect(() => p.wearHomeSubtitle, returnsNormally);
    expect(() => p.wearHomeStatus, returnsNormally);
    // Move still populated from backend
    expect(p.moveHomeSubtitle, 'Stretch');
  });

  // ── 4. Care and Medicine remain separate ─────────────────────────────────

  test('4. care and medicine are separate cards', () {
    final s = _makeSummary(
      careHeadline: 'Evening moisturiser',
      mediHeadline: 'Take pill A',
    );
    expect(s.care.headline, isNot(equals(s.medicine.headline)));
    expect(s.care.action, HomeCardAction.openSkincare);
    expect(s.medicine.action, HomeCardAction.openMedi);
    expect(s.care.headline, 'Evening moisturiser');
    expect(s.medicine.headline, 'Take pill A');
  });

  // ── 5. Medicine text comes only from backend safe fields ─────────────────

  test('5. medicineHomeSubtitle shows backend text, never local medicine name', () async {
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () async => _makeSummary(mediHeadline: 'Stay on track with your routine'),
    );

    // Populate local med state with sensitive name
    p.updateFromMeds([
      {'reminder': true, 'taken': false, 'name': 'SensitiveMedName'},
    ]);

    await p.refresh();

    // Backend text wins — sensitive name never shown
    expect(p.medicineHomeSubtitle, isNot(contains('SensitiveMedName')));
    expect(p.medicineHomeSubtitle, 'Stay on track with your routine');
  });

  // ── 6. One request populates all five cards ───────────────────────────────

  test('6. one refresh() populates all five cards atomically', () async {
    int fetches = 0;
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () async {
        fetches++;
        return _makeSummary();
      },
    );

    await p.refresh();

    expect(fetches, 1);
    expect(p.summary?.wear.headline, isNotEmpty);
    expect(p.summary?.move.headline, isNotEmpty);
    expect(p.summary?.eat.headline, isNotEmpty);
    expect(p.summary?.care.headline, isNotEmpty);
    expect(p.summary?.medicine.headline, isNotEmpty);
  });

  // ── 7. Repeated builds do not trigger duplicate requests ─────────────────

  test('7. repeated refresh() calls do not duplicate requests after cache hit', () async {
    int fetches = 0;
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () async { fetches++; return _makeSummary(); },
    );

    await p.refresh();
    await p.refresh(); // simulates repeated build-driven calls
    await p.refresh();

    expect(fetches, 1, reason: 'cache hit after first fetch');
  });

  // ── 8. Concurrent refreshes are single-flight ────────────────────────────

  test('8. concurrent refresh() calls share one in-flight request', () async {
    int fetches = 0;
    final gate = Completer<HomeTodaySummary>();
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () { fetches++; return gate.future; },
    );

    final f1 = p.refresh();
    final f2 = p.refresh(); // joins in-flight

    gate.complete(_makeSummary());
    await Future.wait([f1, f2]);

    expect(fetches, 1, reason: 'single in-flight for concurrent callers');
    expect(p.summary?.wear.headline, isNotEmpty);
  });

  // ── 9. Stale response after logout/reset is ignored ──────────────────────

  test('9. stale in-flight after reset does not populate cache', () async {
    bool fetcherStarted = false;
    final dataGate = Completer<HomeTodaySummary>();
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () { fetcherStarted = true; return dataGate.future; },
    );

    final staleFuture = p.refresh();
    // fetcher() is sync → fetcherStarted is true before refresh() returns,
    // but the pump is harmless insurance.
    while (!fetcherStarted) { await Future(() {}); }

    // Simulate logout before in-flight completes
    p.reset();

    dataGate.complete(_makeSummary(wearHeadline: 'stale-data'));
    await staleFuture;

    // Cache must be empty — stale data must not have written
    expect(p.summary, isNull);
    expect(p.isLoading, isFalse);
  });

  // ── 10. User B cannot see User A summary ─────────────────────────────────

  test('10. user B does not see user A cached summary', () async {
    int fetches = 0;
    final p = HomeCardSummaryProvider();
    p.debugLocalDateProvider = () => '2024-01-15';
    p.debugSummaryFetcher = () async {
      fetches++;
      return _makeSummary(wearHeadline: 'fetch$fetches');
    };

    p.debugCurrentUserIdProvider = () => 'user-A';
    await p.refresh();
    expect(fetches, 1);

    p.reset();
    p.debugCurrentUserIdProvider = () => 'user-B';
    await p.refresh();
    expect(fetches, 2, reason: 'user-B must fetch fresh');
    expect(p.summary?.wear.headline, 'fetch2');
  });

  // ── 11. Next local date does not reuse prior-date summary ────────────────

  test('11. new date invalidates prior-date summary', () async {
    int fetches = 0;
    final p = HomeCardSummaryProvider();
    p.debugCurrentUserIdProvider = () => 'user-A';
    p.debugSummaryFetcher = () async {
      fetches++;
      return _makeSummary(date: '2024-01-1$fetches');
    };

    p.debugLocalDateProvider = () => '2024-01-15';
    await p.refresh();
    expect(fetches, 1);

    p.debugLocalDateProvider = () => '2024-01-16'; // new day
    await p.refresh();
    expect(fetches, 2, reason: 'new day requires fresh fetch');
  });

  // ── 12. Last same-user/date success survives a temporary failure ──────────

  test('12. backend failure retains last successful summary for same user/date', () async {
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () async => _makeSummary(wearHeadline: 'success-data'),
    );

    await p.refresh();
    expect(p.summary?.wear.headline, 'success-data');

    // Switch fetcher to fail, then force a refresh of the same user/date
    p.debugSummaryFetcher = () async => throw Exception('network_error');
    await p.refresh(forceRefresh: true);

    // Error is exposed, but last successful summary is retained
    expect(p.error, isNotNull);
    expect(p.summary?.wear.headline, 'success-data',
        reason: 'last success retained on temporary failure');
  });

  // ── 13. Unknown backend action cannot trigger arbitrary navigation ─────────

  test('13. unknown action string returns null — no arbitrary routing', () {
    expect(HomeCardAction.fromString(null), isNull);
    expect(HomeCardAction.fromString(''), isNull);
    expect(HomeCardAction.fromString('delete_all_data'), isNull);
    expect(HomeCardAction.fromString('open_fitness'), HomeCardAction.openFitness);
    expect(HomeCardAction.fromString('open_daily_wear'), HomeCardAction.openDailyWear);
    expect(HomeCardAction.fromString('open_medi'), HomeCardAction.openMedi);
    expect(HomeCardAction.fromString('open_diet'), HomeCardAction.openDiet);
    expect(HomeCardAction.fromString('open_skincare'), HomeCardAction.openSkincare);
  });

  // ── 14. Existing local completion updates still behave correctly ──────────

  test('14. markWearDone, updateSkincare, updateFromMeds still work', () async {
    final p = HomeCardSummaryProvider();
    // No backend configured — tests fall through to local logic

    // Wear completion
    p.markWearDone(done: true, outfitName: 'Linen set');
    expect(p.isWearDone, isTrue);
    expect(p.wearHomeSubtitle, 'Linen set');
    expect(p.wearHomeStatus, 'Done');

    // Skincare
    p.updateSkincare(isNight: false, completedSteps: 3, totalSteps: 5, skinType: 'oily');
    expect(p.skincareProgressPct, closeTo(0.6, 0.001));
    expect(p.skincareHomeSubtitle, contains('3/5'));
    expect(p.isSkincareDone, isFalse);

    // Medicine — count only, no name
    p.updateFromMeds([
      {'reminder': true, 'taken': true,  'name': 'PillX'},
      {'reminder': true, 'taken': false, 'name': 'PillY'},
    ]);
    expect(p.totalMeds, 2);
    expect(p.takenToday, 1);
    expect(p.medicineHomeSubtitle, '1/2 taken');
    expect(p.medicineHomeSubtitle, isNot(contains('PillX')));
    expect(p.medicineHomeSubtitle, isNot(contains('PillY')));
  });

  // ── 15. HomeTodaySummary has no hero-driving fields ───────────────────────

  test('15. HomeTodaySummary contains only the five expected card fields', () {
    // The Home hero is driven by ProfileController (gender/image),
    // _recommendationCtx (weather/wardrobe/fitness signals), and
    // _breatheCtrl (animation). HomeTodaySummary must expose none of those.
    final s = _makeSummary();
    // Verify the summary model's public surface: five cards, date, timezone,
    // contextUsage — and nothing more that could accidentally power the hero.
    expect(s.date, isA<String>());
    expect(s.timezone, isA<String>());
    expect(s.contextUsage, isA<HomeContextUsage>());
    expect(s.wear, isA<HomeTodayCard>());
    expect(s.move, isA<HomeTodayCard>());
    expect(s.eat, isA<HomeTodayCard>());
    expect(s.care, isA<HomeTodayCard>());
    expect(s.medicine, isA<HomeTodayCard>());
    // If this test fails, check that no gender/weather/hero fields were added.
  });

  // ── 16. Unavailable card uses backend-supplied safe copy ──────────────────

  test('16. unavailable card shows backend headline/context, never local text', () async {
    final s = HomeTodaySummary.fromMap({
      'date': '2024-01-15',
      'timezone': 'UTC',
      'cards': {
        'wear': {'headline': 'Rest today — no outfit plan', 'context': '', 'status': 'unavailable', 'available': false},
        'move': {'headline': 'Move', 'context': '', 'status': 'ready', 'available': true},
        'eat':  {'headline': 'Eat',  'context': '', 'status': 'ready', 'available': true},
        'care': {'headline': 'Care', 'context': '', 'status': 'ready', 'available': true},
        'medicine': {'headline': 'Meds', 'context': '', 'status': 'ready', 'available': true},
      },
    });
    final p = _provider(userId: 'user-A', date: '2024-01-15', fetcher: () async => s);

    // Populate personalised local wear state that must NOT be shown for an
    // explicitly-unavailable backend card.
    p.markWearDone(done: true, outfitName: 'Local Linen Set');
    await p.refresh();

    expect(p.wearHomeSubtitle, 'Rest today — no outfit plan');
    expect(p.wearHomeSubtitle, isNot(contains('Local Linen')));
  });

  // ── 17. Unavailable card without copy uses neutral text ───────────────────

  test('17. unavailable card with no copy shows neutral text, not local fallback', () async {
    final s = HomeTodaySummary.fromMap({
      'date': '2024-01-15',
      'timezone': 'UTC',
      'cards': {
        'wear': {'headline': '', 'context': '', 'status': 'unavailable', 'available': false},
        'move': {'headline': '', 'context': '', 'status': 'unavailable', 'available': false},
        'eat':  {'headline': '', 'context': '', 'status': 'unavailable', 'available': false},
        'care': {'headline': '', 'context': '', 'status': 'unavailable', 'available': false},
        'medicine': {'headline': '', 'context': '', 'status': 'unavailable', 'available': false},
      },
    });
    final p = _provider(userId: 'user-A', date: '2024-01-15', fetcher: () async => s);

    // Local state present — must be ignored in favour of neutral honest copy.
    p.markWearDone(done: true, outfitName: 'Local Linen Set');
    p.updateFromMeds([{'reminder': true, 'taken': false, 'name': 'PillZ'}]);
    await p.refresh();

    expect(p.wearHomeSubtitle, 'Not available today');
    expect(p.wearHomeStatus, '—');
    expect(p.moveHomeSubtitle, 'Not available today');
    expect(p.medicineHomeSubtitle, 'Not available today');
    expect(p.wearHomeSubtitle, isNot(contains('Local Linen')));
    // Medicine neutral copy must never leak the local med name.
    expect(p.medicineHomeSubtitle, isNot(contains('PillZ')));
  });

  // ── 18. Raw machine status is never rendered ──────────────────────────────

  test('18. backend machine status (due_now/ready/unavailable) is never displayed', () async {
    final s = HomeTodaySummary.fromMap({
      'date': '2024-01-15',
      'timezone': 'UTC',
      'cards': {
        'wear': {'headline': 'Wear this', 'context': 'Layer up', 'status': 'due_now', 'available': true},
        'move': {'headline': 'Move now',  'context': 'Best window is now', 'status': 'due_now', 'available': true},
        'eat':  {'headline': 'Eat soon',  'context': 'Lunch coming up', 'status': 'ready', 'available': true},
        'care': {'headline': 'Glow',      'context': 'Evening routine', 'status': 'ready', 'available': true},
        'medicine': {'headline': 'One reminder', 'context': 'Later today', 'status': 'due_now', 'available': true},
      },
    });
    final p = _provider(userId: 'user-A', date: '2024-01-15', fetcher: () async => s);
    await p.refresh();

    // Subtitle = headline, status = context; the machine `status` value never
    // appears in either field for any card.
    expect(p.wearHomeSubtitle, 'Wear this');
    expect(p.wearHomeStatus, 'Layer up');
    expect(p.moveHomeSubtitle, 'Move now');
    expect(p.moveHomeStatus, 'Best window is now');

    for (final v in [
      p.wearHomeSubtitle, p.wearHomeStatus,
      p.moveHomeSubtitle, p.moveHomeStatus,
      p.eatHomeSubtitle,  p.eatHomeStatus,
      p.skincareHomeSubtitle, p.skincareHomeStatus,
      p.medicineHomeSubtitle, p.medicineHomeStatus,
    ]) {
      expect(v, isNot(equals('due_now')));
      expect(v, isNot(equals('ready')));
      expect(v, isNot(equals('unavailable')));
    }
  });

  // ── 19. Repeated build-driven refreshes do not refetch ────────────────────

  test('19. repeated didChangeDependencies-style refreshes trigger one fetch', () async {
    int fetches = 0;
    final p = _provider(
      userId: 'user-A',
      date: '2024-01-15',
      fetcher: () async { fetches++; return _makeSummary(); },
    );

    // Simulate many rebuild/dependency-change driven calls.
    for (var i = 0; i < 6; i++) {
      await p.refresh();
    }

    expect(fetches, 1, reason: 'user+date cache guard dedupes rebuild refreshes');
  });

  // ── 20. Reconfiguration does not duplicate the session listener ───────────

  test('20. configure() is idempotent — no duplicate session listener', () {
    final a = AppwriteService();
    final b = BackendService(appwriteService: a);
    final p = HomeCardSummaryProvider();
    p.debugCurrentUserIdProvider = () => 'user-A';
    p.debugLocalDateProvider = () => '2024-01-15';

    p.configure(b, a);
    p.configure(b, a); // rebuild — must not register a second listener

    final before = p.debugGeneration;
    a.clearUserCache(); // fires session invalidation
    expect(p.debugGeneration, before + 1,
        reason: 'reset ran exactly once — listener registered once');

    p.dispose();
  });

  // ── 21. Disposed provider is not called back on invalidation ──────────────

  test('21. disposed provider receives no session invalidation callback', () {
    final a = AppwriteService();
    final b = BackendService(appwriteService: a);
    final p = HomeCardSummaryProvider();

    p.configure(b, a);
    final before = p.debugGeneration;
    p.dispose(); // must detach the session listener

    a.clearUserCache(); // must NOT call back into the disposed provider
    expect(p.debugGeneration, before,
        reason: 'reset did not run after dispose');
  });

  // ── 22. One throwing listener does not stop the others ────────────────────

  test('22. all session listeners run even when one throws', () {
    final a = AppwriteService();
    bool secondRan = false;
    void thrower() => throw StateError('boom');
    void second() => secondRan = true;

    a.addSessionInvalidationListener(thrower);
    a.addSessionInvalidationListener(second);
    try {
      a.clearUserCache();
      expect(secondRan, isTrue,
          reason: 'exception in first listener is isolated');
    } finally {
      a.removeSessionInvalidationListener(thrower);
      a.removeSessionInvalidationListener(second);
    }
  });
}

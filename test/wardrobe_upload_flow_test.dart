// Regression coverage for the unified wardrobe upload/review/save flow
// (camera -> detecting -> reviewing -> saving -> success/error) introduced
// to replace the old Ahvi3StepUploadModal + separate edit-item dialog.
//
// The modal owns a real camera controller and picks images via the
// image_picker plugin, neither of which run in `flutter test`. Camera
// initialization is already wrapped in try/catch in production code, so it
// silently no-ops here. Image picking is driven through a fake
// ImagePickerPlatform, and network calls through a fake BackendService
// (both swapped in per-test), which lets these tests exercise the real
// widget/state machine instead of only source-level assertions.
//
// The detecting/saving steps contain indeterminate (repeating) animations,
// so `pumpAndSettle()` would hang on them — tests instead pump in small
// fixed steps until a step-specific Key appears.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/wardrobe.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

// Minimal valid 1x1 transparent PNG — the "detecting" step briefly renders
// the captured/picked bytes via Image.memory, so they must decode cleanly.
final Uint8List _onePxPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform(this.files);
  final List<XFile> files;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    return files;
  }
}

/// Stands in for BackendService's network layer. `onAnalyze`/`onSave` are
/// swapped per test; every save call is recorded verbatim in [saveCalls] so
/// tests can inspect the exact backend payload (e.g. to prove privacy
/// normalization survived an inline edit).
class _FakeBackendService extends BackendService {
  Map<String, dynamic> Function(List<Uint8List> images)? onAnalyze;
  Map<String, dynamic> Function(List<Map<String, dynamic>> payloads)? onSave;

  int analyzeCallCount = 0;
  int saveCallCount = 0;
  final List<List<Map<String, dynamic>>> saveCalls = [];
  // When set, saveWardrobeLabels suspends until this completes, so a test
  // can deterministically observe the in-flight "saving" step instead of
  // racing a save call that resolves within the same pump.
  Completer<void>? saveGate;

  @override
  Future<Map<String, dynamic>?> analyzeImage(
    Uint8List imageBytes, {
    bool autoSave = false,
    bool saveDuplicates = false,
  }) async {
    analyzeCallCount++;
    return onAnalyze?.call([imageBytes]) ?? const {'items': []};
  }

  @override
  Future<Map<String, dynamic>?> analyzeImagesBatch(
    List<Uint8List> images, {
    bool autoSave = false,
    bool saveDuplicates = false,
  }) async {
    analyzeCallCount++;
    return onAnalyze?.call(images) ?? const {'items': []};
  }

  @override
  Future<Map<String, dynamic>?> saveWardrobeLabels(
    List<Map<String, dynamic>> detectedItems,
  ) async {
    saveCallCount++;
    saveCalls.add(detectedItems);
    if (saveGate != null) await saveGate!.future;
    return onSave?.call(detectedItems) ??
        {'saved_count': detectedItems.length};
  }

  // Sequential upload batch: the review/save flow now calls these instead of
  // saveWardrobeLabels(). Adapted onto the SAME onSave/saveGate/saveCallCount
  // test hooks, called once per item (matching the real sequential contract)
  // rather than once per batch.
  @override
  Future<Map<String, dynamic>?> createOrResumeUploadBatch({
    required String clientBatchRequestId,
    required int totalItems,
  }) async => {
    'success': true,
    'batch_id': clientBatchRequestId,
    'resumed': false,
  };

  @override
  Future<Map<String, dynamic>?> processUploadBatchItem({
    required String batchId,
    required String clientUploadItemId,
    required Uint8List imageBytes,
    Map<String, dynamic>? metadata,
    bool overrideDuplicate = false,
  }) async {
    saveCallCount++;
    final payload = [
      {'item_id': clientUploadItemId, ...?metadata},
    ];
    saveCalls.add(payload);
    if (saveGate != null) await saveGate!.future;
    final result = onSave?.call(payload) ?? {'saved_count': 1};
    final savedCountRaw = result['saved_count'];
    final savedCount = savedCountRaw is int
        ? savedCountRaw
        : int.tryParse(savedCountRaw?.toString() ?? '') ?? 0;
    if (savedCount > 0) {
      return {
        'success': true,
        'status': 'ADDED_TO_WARDROBE',
        'wardrobe_item_id': 'w_$clientUploadItemId',
      };
    }
    return {
      'success': false,
      'status': 'FAILED',
      'error_code': 'PERSISTENCE_FAILED',
    };
  }

  @override
  Future<Map<String, dynamic>?> getUploadBatchStatus(String batchId) async => {
    'success': true,
    'batch_id': batchId,
    'status': 'COMPLETED',
    'total_items': saveCallCount,
    'added_count': saveCallCount,
    'needs_review_count': 0,
    'rejected_count': 0,
    'failed_count': 0,
  };
}

Map<String, dynamic> _detectedItemJson({
  String id = 'det-1',
  String name = 'Blue Cotton Shirt',
  String category = 'top',
  String subCategory = 'Shirt',
  List<String> occasions = const ['upload_occasion_everyday'],
  String validationStatus = 'ok',
}) => {
  'item_id': id,
  'name': name,
  'category': category,
  'sub_category': subCategory,
  'color_name': 'Blue',
  'pattern': 'plain',
  'occasions': occasions,
  'validation_status': validationStatus,
  'selected_by_default': true,
  'confidence': 0.92,
};

/// Pumps a host screen with [backend] wired via Provider, opens the upload
/// modal, and drives a single-image gallery pick whose analyze response is
/// `items`. Leaves the tester parked on whatever step the flow reaches
/// (normally "reviewing") — callers assert from there.
Future<void> _openReview(
  WidgetTester tester, {
  required _FakeBackendService backend,
  required List<Map<String, dynamic>> items,
  double? textScale,
}) async {
  backend.onAnalyze = (_) => {'items': items};
  ImagePickerPlatform.instance = _FakeImagePickerPlatform([
    XFile.fromData(_onePxPng, mimeType: 'image/png', name: 'pick.png'),
  ]);

  // Provider wraps the whole MaterialApp (not just `home`): the upload
  // dialog opens with `useRootNavigator: true`, so its route is a sibling
  // overlay entry on the app's root Navigator rather than a descendant of
  // `home` — a Provider placed inside `home` would not be visible to it.
  await tester.pumpWidget(
    Provider<BackendService>.value(
      value: backend,
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: [AppThemeTokens.light(_accent)],
        ),
        builder: textScale == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAddToWardrobeModal(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pump();

  await tester.tap(find.byIcon(Icons.photo_library_outlined));
  await _pumpUntilKeyFound(tester, const [
    'review',
    'wardrobe-error',
  ]);
}

/// Repeatedly pumps small, bounded frames (never `pumpAndSettle`, which
/// hangs on the detecting/saving steps' indeterminate animations) until one
/// of `keys` appears in the tree.
Future<void> _pumpUntilKeyFound(
  WidgetTester tester,
  List<String> keys, {
  int maxTries = 100,
}) async {
  for (var i = 0; i < maxTries; i++) {
    for (final key in keys) {
      if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail(
    'Timed out waiting for one of $keys. '
    'Exception: ${tester.takeException()}',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!dotenv.isInitialized) {
      dotenv.loadFromString(
        envString:
            'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://example.test/v1\n'
            'EXPO_PUBLIC_APPWRITE_PROJECT_ID=test-project\n',
      );
    }
  });

  // ------------------------------------------------------------------
  // Static/source-contract checks: things that are impractical to drive
  // through camera + network plugins in a widget test, but which are exact,
  // load-bearing invariants worth pinning against regressions.
  // ------------------------------------------------------------------

  group('source contract', () {
    late String source;
    setUpAll(() {
      source = File('lib/wardrobe.dart').readAsStringSync();
    });

    test('2: no reference to the old Ahvi3StepUploadModal route remains', () {
      expect(source.contains('Ahvi3StepUploadModal'), isFalse);
      expect(source.contains('ahvi_3step_upload_flow'), isFalse);
      expect(source.contains('_launchThreeStepReview'), isFalse);
    });

    test('3: no separate Edit Item route/dialog remains', () {
      expect(source.contains('_saveEditedItem'), isFalse);
      expect(source.contains('_editItem'), isFalse);
      expect(
        RegExp(r'enum _ModalStep \{[^}]*\}').firstMatch(source)!.group(0),
        'enum _ModalStep { camera, detecting, reviewing, saving, success, results, error }',
      );
    });

    test(
      '13: no new mojibake outside pre-existing "//" section-header comments',
      () {
        final start = source.indexOf('class _DetectedItem {');
        final end = source.indexOf('class _CamControlBtn');
        expect(start, greaterThan(0));
        expect(end, greaterThan(start));
        final region = source.substring(start, end);
        final offenders = region
            .split('\n')
            .where((line) => !line.trim().startsWith('//'))
            .where(
              (line) =>
                  line.contains('Ã') || line.contains('â€') || line.contains('Γ'),
            )
            .toList();
        expect(
          offenders,
          isEmpty,
          reason: 'Corrupted bytes found outside comments: $offenders',
        );
      },
    );

    test(
      '16: catalog_pending scheduling is preserved for saved items',
      () {
        expect(
          source.contains(
            "if ((item['catalogStatus'] ?? '').toString() == 'catalog_pending') {",
          ),
          isTrue,
        );
        expect(source.contains('_pendingCatalogIds.add(localItem.id)'), isTrue);
        expect(source.contains('_scheduleCatalogRefresh()'), isTrue);
      },
    );

    test(
      '17: each saved item is inserted into the live wardrobe list on save',
      () {
        expect(source.contains('_wardrobe.insert(0, localItem)'), isTrue);
      },
    );
  });

  // ------------------------------------------------------------------
  // Widget-driven behavior: exercised through the real state machine via a
  // fake image picker + fake backend.
  // ------------------------------------------------------------------

  testWidgets('1: detected items land on one unified review page', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);
    expect(find.byKey(const ValueKey('review')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe-confirm-cta')), findsOneWidget);
  });

  testWidgets('4 & 14: exactly one Add CTA, single- and multi-item', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(
      tester,
      backend: backend,
      items: [
        _detectedItemJson(id: 'a', name: 'Blue Shirt'),
        _detectedItemJson(id: 'b', name: 'Black Jeans', category: 'pant'),
      ],
    );
    expect(find.byKey(const ValueKey('wardrobe-confirm-cta')), findsOneWidget);
    expect(find.textContaining('Add 2 items to wardrobe'), findsOneWidget);
  });

  testWidgets('6: saving state exposes zero actionable save controls', (
    tester,
  ) async {
    // Gate the save call so it stays in-flight until we've inspected the
    // saving step — otherwise a same-frame-resolving fake can race past it.
    final backend = _FakeBackendService()..saveGate = Completer<void>();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await tester.pump();
    expect(find.byKey(const ValueKey('wardrobe-saving')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe-confirm-cta')), findsNothing);
    expect(find.byKey(const ValueKey('wardrobe-retry-cta')), findsNothing);
    backend.saveGate!.complete();
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
  });

  testWidgets('5: rapid repeated taps produce exactly one save call', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);
    // Invoke the button's onTap closure directly, twice, back-to-back with
    // no pump in between — this is the exact race a real double-tap would
    // create (both calls land before the first rebuild can remove the
    // button), without depending on how the test binding schedules/defers
    // gesture-arena callbacks for two separate WidgetTester.tap() calls.
    final onTap = tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('wardrobe-confirm-cta')),
        )
        .onTap!;
    onTap();
    onTap();
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
    expect(backend.saveCallCount, 1);
  });

  testWidgets('7: saved_count=0 shows a persistent Error + Retry', (
    tester,
  ) async {
    final backend = _FakeBackendService()
      ..onSave = (_) => const {'saved_count': 0};
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-error']);
    expect(find.byKey(const ValueKey('wardrobe-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe-retry-cta')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe-confirm-cta')), findsNothing);
  });

  testWidgets('8: retry re-enters save exactly once more', (tester) async {
    var call = 0;
    final backend = _FakeBackendService()
      ..onSave = (_) {
        call++;
        return {'saved_count': call == 1 ? 0 : 1};
      };
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-error']);
    expect(backend.saveCallCount, 1);

    await tester.tap(find.byKey(const ValueKey('wardrobe-retry-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
    expect(backend.saveCallCount, 2);
  });

  testWidgets('9: saved_count == requested renders a truthful full success', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
    expect(find.text('Added to your wardrobe!'), findsOneWidget);
    expect(find.textContaining('of 1 items'), findsNothing);
  });

  testWidgets(
    '10: partial save (requested=3, saved=1) never claims all 3 saved',
    (tester) async {
      // Sequential per-item contract: item "b" fails, "a"/"c" are added. A
      // genuine mix routes to the per-item results screen, never a single
      // "all saved" success message.
      final backend = _FakeBackendService()
        ..onSave = (payload) =>
            {'saved_count': payload.single['item_id'] == 'b' ? 0 : 1};
      await _openReview(
        tester,
        backend: backend,
        items: [
          _detectedItemJson(id: 'a', name: 'Item A'),
          _detectedItemJson(id: 'b', name: 'Item B'),
          _detectedItemJson(id: 'c', name: 'Item C'),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
      await _pumpUntilKeyFound(tester, const ['wardrobe-results']);
      expect(find.text('Added 3 items to your wardrobe!'), findsNothing);
      expect(find.textContaining('Added 2 of 3 items'), findsOneWidget);
      expect(backend.saveCallCount, 3, reason: 'each item is its own sequential call');
    },
  );

  testWidgets(
    '11: a private-wear inline edit is normalized in the save payload',
    (tester) async {
      final backend = _FakeBackendService();
      await _openReview(
        tester,
        backend: backend,
        items: [
          _detectedItemJson(
            name: 'Grey Shorts',
            category: 'bottom',
            subCategory: 'Shorts',
            occasions: const ['upload_occasion_everyday'],
          ),
        ],
      );

      final subCatField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'e.g. Shirt, Saree, Sneakers',
      );
      expect(subCatField, findsOneWidget);
      await tester.enterText(subCatField, 'Boxer Briefs');
      await tester.pump();

      // Reactivity: the private-wear banner appears immediately, without a
      // separate confirm step.
      expect(
        find.textContaining("marked as private wear"),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
      await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

      expect(backend.saveCallCount, 1);
      final payload = backend.saveCalls.single.single;
      expect(payload['category'], 'Innerwear');
      expect(payload['sub_category'], 'Private Wear');
      expect(payload['occasions'], ['Home', 'Private', 'Lounge']);
    },
  );

  testWidgets('12: raw upload_occasion_* keys are never shown in the UI', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(
      tester,
      backend: backend,
      items: [
        _detectedItemJson(occasions: const ['upload_occasion_everyday']),
      ],
    );
    expect(find.textContaining('upload_occasion'), findsNothing);
    // The humanized chip ("Everyday") should read as selected/active.
    expect(find.text('Everyday'), findsOneWidget);
  });

  testWidgets('15: empty detection still leaves an actionable Cancel', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: const []);
    expect(find.byKey(const ValueKey('review')), findsOneWidget);
    expect(find.text('cancel'), findsOneWidget);
    // No confirm CTA when there is nothing selectable to save.
    expect(find.byKey(const ValueKey('wardrobe-confirm-cta')), findsNothing);
  });

  testWidgets(
    '18: large text scale renders the review page without overflow',
    (tester) async {
      final backend = _FakeBackendService();
      await _openReview(
        tester,
        backend: backend,
        textScale: 2.0,
        items: [
          _detectedItemJson(
            name:
                'An Extremely Long Detected Item Name That Could Wrap '
                'Awkwardly Across Several Lines Of The Review Card Layout',
          ),
        ],
      );
      expect(find.byKey(const ValueKey('review')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

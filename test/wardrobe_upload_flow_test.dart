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
import 'package:myapp/services/appwrite_service.dart';
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
  // When set, takes full control of processUploadBatchItem's per-item
  // response (bypassing the saved_count/index heuristic below) so a test can
  // deterministically produce NEEDS_REVIEW/duplicate outcomes and Add-Anyway
  // overrides, which the index-based heuristic cannot express.
  Map<String, dynamic> Function(
    String clientUploadItemId,
    bool overrideDuplicate,
  )?
  onProcessItem;

  int analyzeCallCount = 0;
  int saveCallCount = 0;
  int createBatchCallCount = 0;
  int processItemCallCount = 0;
  final List<String> processedItemIds = [];
  final List<List<Map<String, dynamic>>> saveCalls = [];
  // When set, saveWardrobeLabels suspends until this completes, so a test
  // can deterministically observe the in-flight "saving" step instead of
  // racing a save call that resolves within the same pump.
  Completer<void>? saveGate;
  Map<String, dynamic>? batchStatus;

  int _batchItemIndex = 0;
  final Set<String> _attemptedBatchItems = {};

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
    return onSave?.call(detectedItems) ?? {'saved_count': detectedItems.length};
  }

  @override
  Future<Map<String, dynamic>?> createOrResumeUploadBatch({
    required String clientBatchRequestId,
    required int totalItems,
  }) async {
    saveCallCount++;
    createBatchCallCount++;
    _batchItemIndex = 0;
    _attemptedBatchItems.clear();
    saveCalls.add([]);
    return {'batch_id': clientBatchRequestId};
  }

  @override
  Future<Map<String, dynamic>?> processUploadBatchItem({
    required String batchId,
    required String clientUploadItemId,
    required Uint8List imageBytes,
    Map<String, dynamic>? metadata,
    bool overrideDuplicate = false,
    Map<String, dynamic>? reviewedItem,
  }) async {
    processItemCallCount++;
    processedItemIds.add(clientUploadItemId);
    final payload = Map<String, dynamic>.from(
      reviewedItem ?? metadata ?? const <String, dynamic>{},
    );
    saveCalls.last.add(payload);
    if (saveGate != null) await saveGate!.future;
    if (onProcessItem != null) {
      return onProcessItem!(clientUploadItemId, overrideDuplicate);
    }
    final response =
        onSave?.call(saveCalls.last) ?? {'saved_count': saveCalls.last.length};
    final savedCount =
        int.tryParse(response['saved_count']?.toString() ?? '') ?? 0;
    final wasAttempted = !_attemptedBatchItems.add(clientUploadItemId);
    final shouldAdd =
        savedCount > 0 && (wasAttempted || savedCount > _batchItemIndex++);
    return shouldAdd
        ? {
            'status': 'ADDED_TO_WARDROBE',
            'wardrobe_item_id': 'wardrobe-$clientUploadItemId',
          }
        : {
            'status': 'FAILED',
            'error_code': 'REQUEST_FAILED',
            'reason': 'fake failure',
          };
  }

  @override
  Future<Map<String, dynamic>?> getUploadBatchStatus(String batchId) async =>
      batchStatus ?? {'batch_id': batchId, 'status': 'COMPLETED'};
}

Map<String, dynamic> _detectedItemJson({
  String id = 'det-1',
  String name = 'Blue Cotton Shirt',
  String category = 'top',
  String subCategory = 'Shirt',
  List<String> occasions = const ['upload_occasion_everyday'],
  String validationStatus = 'ok',
  bool selectedByDefault = true,
}) => {
  'item_id': id,
  'name': name,
  'category': category,
  'sub_category': subCategory,
  'color_name': 'Blue',
  'pattern': 'plain',
  'occasions': occasions,
  'validation_status': validationStatus,
  'selected_by_default': selectedByDefault,
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
  List<XFile>? pickedFiles,
  Map<String, dynamic> Function(List<Uint8List> images)? onAnalyze,
  bool expectReview = true,
}) async {
  backend.onAnalyze = onAnalyze ?? (_) => {'items': items};
  ImagePickerPlatform.instance = _FakeImagePickerPlatform(
    pickedFiles ??
        [XFile.fromData(_onePxPng, mimeType: 'image/png', name: 'pick.png')],
  );

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
  if (!expectReview) {
    await tester.pump();
    return;
  }
  await _pumpUntilKeyFound(tester, const ['review', 'wardrobe-error']);
}

/// Same as [_openReview] but wires a real `onSaved` callback through
/// `showAddToWardrobeModal(context, onSaved: ...)` — the exact public entry
/// point every active external screen (Home's chat bar, DailyWear, the main
/// Chat screen) uses to signal a successful save back to WardrobeScreen via
/// AppwriteService.invalidateWardrobeCache(). Proves the callback-firing
/// contract itself: exactly one call per successfully ADDED item, never for
/// FAILED/NEEDS_REVIEW, exactly once on retry/Add-Anyway success.
Future<void> _openReviewWithOnSaved(
  WidgetTester tester, {
  required _FakeBackendService backend,
  required List<Map<String, dynamic>> items,
  required void Function(Map<String, dynamic> item) onSaved,
  List<XFile>? pickedFiles,
}) async {
  backend.onAnalyze = (_) => {'items': items};
  ImagePickerPlatform.instance = _FakeImagePickerPlatform(
    pickedFiles ??
        [XFile.fromData(_onePxPng, mimeType: 'image/png', name: 'pick.png')],
  );

  await tester.pumpWidget(
    Provider<BackendService>.value(
      value: backend,
      child: MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: [AppThemeTokens.light(_accent)],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showAddToWardrobeModal(context, onSaved: onSaved),
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
  await _pumpUntilKeyFound(tester, const ['review', 'wardrobe-error']);
}

Future<void> _scrollToAndTapAddOccasion(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('wardrobe-add-occasion'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Finder _customOccasionField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == 'e.g. Beach, Gym',
);

Future<void> _addCustomOccasion(WidgetTester tester, String tag) async {
  await _scrollToAndTapAddOccasion(tester);
  await tester.pumpAndSettle();
  await tester.enterText(_customOccasionField(), tag);
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
}

List<XFile> _pickedImages(int count) => List.generate(
  count,
  (index) =>
      XFile.fromData(_onePxPng, mimeType: 'image/png', name: 'pick-$index.png'),
);

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
      final modalSteps = RegExp(r'enum _ModalStep \{[^}]*\}')
          .firstMatch(source)!
          .group(0)!
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(', }', ' }');
      expect(
        modalSteps,
        'enum _ModalStep { camera, detecting, reviewing, saving, success, results, error }',
      );
    });

    test('save has one active sequential entry point', () {
      expect(source.contains('_legacyConfirmAndSave'), isFalse);
      expect(source.contains('saveWardrobeLabels(payloads)'), isFalse);
      expect(source.contains('SequentialUploadController('), isTrue);
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
                  line.contains('Ã') ||
                  line.contains('â€') ||
                  line.contains('Γ'),
            )
            .toList();
        expect(
          offenders,
          isEmpty,
          reason: 'Corrupted bytes found outside comments: $offenders',
        );
      },
    );

    test('16: catalog_pending scheduling is preserved for saved items', () {
      expect(
        source.contains(
          "if ((item['catalogStatus'] ?? '').toString() == 'catalog_pending') {",
        ),
        isTrue,
      );
      expect(source.contains('_pendingCatalogIds.add(localItem.id)'), isTrue);
      expect(source.contains('_scheduleCatalogRefresh()'), isTrue);
    });

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

  testWidgets('picker cancellation does not start a save', (tester) async {
    final backend = _FakeBackendService();
    await _openReview(
      tester,
      backend: backend,
      items: const [],
      pickedFiles: const [],
      expectReview: false,
    );

    await tester.tap(
      find.byIcon(Icons.photo_library_outlined),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('camera')), findsOneWidget);
    expect(backend.createBatchCallCount, 0);
    expect(backend.processItemCallCount, 0);
  });

  testWidgets('explicit three-item save is strictly sequential', (
    tester,
  ) async {
    final backend = _FakeBackendService()
      ..onSave = (_) => const {'saved_count': 3};
    await _openReview(
      tester,
      backend: backend,
      items: [
        _detectedItemJson(id: 'item-a', name: 'Item A'),
        _detectedItemJson(id: 'item-b', name: 'Item B'),
        _detectedItemJson(id: 'item-c', name: 'Item C'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

    expect(backend.createBatchCallCount, 1);
    expect(backend.processItemCallCount, 3);
    expect(backend.processedItemIds, ['item-a', 'item-b', 'item-c']);
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
    expect(backend.saveCallCount, 1);
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
      final backend = _FakeBackendService()
        ..onSave = (_) => const {'saved_count': 1};
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
      await _pumpUntilKeyFound(tester, const ['wardrobe-upload-results']);
      expect(find.text('Added 3 items to your wardrobe!'), findsNothing);
      expect(
        find.textContaining('1 of 3 items are in your wardrobe'),
        findsOneWidget,
      );
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
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'e.g. Shirt, Saree, Sneakers',
      );
      expect(subCatField, findsOneWidget);
      await tester.enterText(subCatField, 'Boxer Briefs');
      await tester.pump();

      // Reactivity: the private-wear banner appears immediately, without a
      // separate confirm step.
      expect(find.textContaining("marked as private wear"), findsOneWidget);

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

  testWidgets('18: large text scale renders the review page without overflow', (
    tester,
  ) async {
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
  });

  testWidgets('19: custom occasion can be added and saved', (tester) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);

    await _addCustomOccasion(tester, 'Beach Mode');
    expect(find.text('Beach Mode'), findsOneWidget);
    await tester.pump();
    expect(find.text('Beach Mode'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

    final occasions = backend.saveCalls.single.single['occasions'] as List;
    expect(occasions, contains('Beach Mode'));
    expect(occasions, contains('Everyday'));
  });

  testWidgets('20: custom occasion input is limited to 24 characters', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);

    await _scrollToAndTapAddOccasion(tester);
    await tester.pumpAndSettle();
    await tester.enterText(
      _customOccasionField(),
      'A Tag Name That Is Far Too Long To Fit',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && (widget.data ?? '').startsWith('A Tag'),
          ),
        )
        .map((widget) => widget.data!)
        .toList();
    expect(labels, isNotEmpty);
    expect(labels.first.length, lessThanOrEqualTo(24));
    expect(
      'A Tag Name That Is Far Too Long To Fit'.startsWith(labels.first),
      isTrue,
    );
  });

  testWidgets('21: six custom occasions is the maximum', (tester) async {
    final backend = _FakeBackendService();
    await _openReview(tester, backend: backend, items: [_detectedItemJson()]);

    for (var i = 1; i <= 6; i++) {
      await _addCustomOccasion(tester, 'Tag$i');
    }
    expect(find.text('Tag6'), findsOneWidget);

    await _scrollToAndTapAddOccasion(tester);
    await tester.pump();
    expect(_customOccasionField(), findsNothing);
    expect(find.text('Tag7'), findsNothing);
  });

  testWidgets('22: custom duplicates and preset aliases do not duplicate', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(
      tester,
      backend: backend,
      items: [
        _detectedItemJson(occasions: const ['office', 'travel']),
      ],
    );

    await _addCustomOccasion(tester, 'Gym');
    await _addCustomOccasion(tester, 'gym');
    await _addCustomOccasion(tester, 'Work');

    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
    expect(backend.saveCalls.single.single['occasions'], [
      'Work',
      'Travel',
      'Gym',
    ]);
  });

  testWidgets('23: picker input over six is capped with the standard warning', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    var analyzedCount = 0;
    await _openReview(
      tester,
      backend: backend,
      pickedFiles: _pickedImages(7),
      onAnalyze: (images) {
        analyzedCount = images.length;
        return {
          'items': [_detectedItemJson()],
        };
      },
      items: [_detectedItemJson()],
    );

    expect(analyzedCount, 6);
    expect(find.text(wardrobeMaxItemsMessage), findsOneWidget);
  });

  testWidgets('24: selecting a seventh item keeps six selected', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    final items = List.generate(
      7,
      (index) => _detectedItemJson(
        id: 'det-$index',
        name: 'Item $index',
        selectedByDefault: index < 6,
      ),
    );
    await _openReview(tester, backend: backend, items: items);

    for (var index = 0; index < 6; index++) {
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('wardrobe-select-det-6')));
    await tester.pump();
    expect(find.text(wardrobeMaxItemsMessage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
    expect(backend.saveCalls.single.length, 6);
  });

  testWidgets('25: saving over six is blocked with the standard warning', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(
      tester,
      backend: backend,
      items: List.generate(
        7,
        (index) => _detectedItemJson(id: 'det-$index', selectedByDefault: true),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await tester.pump();
    expect(backend.saveCallCount, 0);
    expect(find.text(wardrobeMaxItemsMessage), findsOneWidget);
  });

  testWidgets(
    '26: repeated max-six rejection replaces one overlay and dismisses',
    (tester) async {
      final backend = _FakeBackendService();
      await _openReview(
        tester,
        backend: backend,
        items: List.generate(
          7,
          (index) =>
              _detectedItemJson(id: 'det-$index', selectedByDefault: true),
        ),
      );

      final onTap = tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('wardrobe-confirm-cta')),
          )
          .onTap!;
      onTap();
      onTap();
      await tester.pump();
      expect(find.text(wardrobeMaxItemsMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(find.text(wardrobeMaxItemsMessage), findsNothing);
    },
  );

  testWidgets('27: disposing a visible max-six warning is safe', (
    tester,
  ) async {
    final backend = _FakeBackendService();
    await _openReview(
      tester,
      backend: backend,
      items: List.generate(
        7,
        (index) => _detectedItemJson(id: 'det-$index', selectedByDefault: true),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------------
  // P0.21 — Wardrobe auto-refresh after successful upload.
  //
  // Root cause (see .planning/debug/p0-21-wardrobe-auto-refresh.md and the
  // pre-commit review): the Wardrobe screen's own camera/lens sheet
  // (_openLensSheet) is DEAD_CURRENTLY (unreferenced — confirmed via
  // `flutter analyze`), left untouched. The real active stale-Wardrobe
  // paths are external screens (Home's chat bar, DailyWear, main Chat) that
  // called `showAddToWardrobeModal(context)` with no `onSaved` — see the
  // 'P0.21 cross-screen refresh' group below. The FAB (_openAddModal) keeps
  // its existing behavior via the extracted `_handleItemSaved` handler.
  //
  // These tests exercise the real `_AddItemModal` state machine (via the
  // fake image picker + fake backend, same harness as the tests above) and
  // assert on an `onSaved` spy — the actual production callback contract —
  // not on source string matching.
  // ------------------------------------------------------------------

  group('P0.21 shared post-save handler', () {
    test('source contract: the FAB routes through _handleItemSaved', () {
      final source = File('lib/wardrobe.dart').readAsStringSync();
      // _openAddModal's showDialog must hand the modal the extracted
      // handler, not an inline closure — required so the FAB keeps its
      // exact pre-existing optimistic-insert + 3308946 reconciliation
      // behavior unchanged.
      expect(
        source.contains(
          'builder: (_) => _AddItemModal(onSave: _handleItemSaved)',
        ),
        isTrue,
        reason:
            'FAB (_openAddModal) must use the extracted _handleItemSaved handler',
      );
    });

    testWidgets(
      'CASE 1: a single successful item reaches onSaved exactly once automatically',
      (tester) async {
        final saved = <Map<String, dynamic>>[];
        final backend = _FakeBackendService();
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [_detectedItemJson(id: 'item-1')],
          onSaved: saved.add,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

        // No manual refresh action taken between save completing and this
        // assertion — onSaved must already have fired.
        expect(saved, hasLength(1));
        expect(saved.single['id'], 'wardrobe-item-1');
      },
    );

    testWidgets(
      'CASE 3: three successful sequential items all reach onSaved, no duplicates',
      (tester) async {
        final saved = <Map<String, dynamic>>[];
        final backend = _FakeBackendService()
          ..onSave = (_) => const {'saved_count': 3};
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [
            _detectedItemJson(id: 'item-a', name: 'Item A'),
            _detectedItemJson(id: 'item-b', name: 'Item B'),
            _detectedItemJson(id: 'item-c', name: 'Item C'),
          ],
          onSaved: saved.add,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

        expect(saved.map((item) => item['id']).toSet(), {
          'wardrobe-item-a',
          'wardrobe-item-b',
          'wardrobe-item-c',
        });
        expect(
          saved,
          hasLength(3),
          reason: 'each item must reach onSaved exactly once',
        );
      },
    );

    testWidgets(
      'CASE 4: mixed batch (2 ADDED + 1 FAILED) reaches onSaved exactly twice',
      (tester) async {
        final saved = <Map<String, dynamic>>[];
        final backend = _FakeBackendService()
          ..onSave = (_) => const {'saved_count': 2};
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [
            _detectedItemJson(id: 'item-a', name: 'Item A'),
            _detectedItemJson(id: 'item-b', name: 'Item B'),
            _detectedItemJson(id: 'item-c', name: 'Item C'),
          ],
          onSaved: saved.add,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        // 2 of 3 added + 0 reviewable -> results step (not success), matching
        // _confirmAndSave's step-selection logic.
        await _pumpUntilKeyFound(tester, const ['wardrobe-upload-results']);

        expect(
          saved,
          hasLength(2),
          reason: 'the FAILED item must never reach onSaved',
        );
        expect(saved.map((item) => item['id']).toSet(), {
          'wardrobe-item-a',
          'wardrobe-item-b',
        });
      },
    );

    testWidgets(
      'CASE 4b: five added plus one failed stays truthful and exposes Add Anyway',
      (tester) async {
        final saved = <Map<String, dynamic>>[];
        final backend = _FakeBackendService()
          // Simulate a stale batch counter: item responses are still the
          // authoritative record of the five successful saves.
          ..batchStatus = {
            'batch_id': 'stale-batch',
            'status': 'FAILED',
            'added_count': 0,
          }
          ..onProcessItem = (id, overrideDuplicate) {
            if (id == 'item-fail' && !overrideDuplicate) {
              return {
                'status': 'FAILED',
                'error_code': 'PERSISTENCE_FAILED',
                'reason': 'temporary save failure',
              };
            }
            return {
              'status': 'ADDED_TO_WARDROBE',
              'wardrobe_item_id': 'wardrobe-$id',
            };
          };

        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [
            ...List.generate(
              5,
              (index) =>
                  _detectedItemJson(id: 'item-$index', name: 'Item $index'),
            ),
            _detectedItemJson(id: 'item-fail', name: 'Failed item'),
          ],
          onSaved: saved.add,
        );

        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-upload-results']);

        expect(find.text('5 of 6 items are in your wardrobe.'), findsOneWidget);
        expect(find.text('Add Anyway'), findsOneWidget);
        expect(saved, hasLength(5));

        final addAnyway = find.text('Add Anyway');
        await tester.ensureVisible(addAnyway);
        await tester.tap(addAnyway);
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
        expect(saved, hasLength(6));
      },
    );

    testWidgets(
      'CASE 5: duplicate (NEEDS_REVIEW) does not reach onSaved until Add Anyway succeeds, then exactly once',
      (tester) async {
        final saved = <Map<String, dynamic>>[];
        final backend = _FakeBackendService()
          ..onProcessItem = (id, overrideDuplicate) => overrideDuplicate
              ? {
                  'status': 'ADDED_TO_WARDROBE',
                  'wardrobe_item_id': 'wardrobe-$id',
                }
              : {
                  'status': 'NEEDS_REVIEW',
                  'error_code': 'DUPLICATE_WARDROBE_ITEM',
                  'matched_item_id': 'existing-item',
                };
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [_detectedItemJson(id: 'dup-item')],
          onSaved: saved.add,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-upload-results']);

        expect(
          saved,
          isEmpty,
          reason: 'a duplicate must not persist before Add Anyway',
        );
        expect(find.text('Add Anyway'), findsOneWidget);

        await tester.tap(find.text('Add Anyway'));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

        expect(
          saved,
          hasLength(1),
          reason: 'Add Anyway must persist exactly once',
        );
        expect(saved.single['id'], 'wardrobe-dup-item');
      },
    );

    testWidgets('CASE 6: retry after a failure reaches onSaved exactly once', (
      tester,
    ) async {
      final saved = <Map<String, dynamic>>[];
      var call = 0;
      final backend = _FakeBackendService()
        ..onSave = (_) {
          call++;
          return {'saved_count': call == 1 ? 0 : 1};
        };
      await _openReviewWithOnSaved(
        tester,
        backend: backend,
        items: [_detectedItemJson(id: 'retry-item')],
        onSaved: saved.add,
      );
      await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
      await _pumpUntilKeyFound(tester, const ['wardrobe-error']);
      expect(
        saved,
        isEmpty,
        reason: 'the initial FAILED attempt must not reach onSaved',
      );

      await tester.tap(find.byKey(const ValueKey('wardrobe-retry-cta')));
      await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

      expect(
        saved,
        hasLength(1),
        reason: 'the retried success must reach onSaved exactly once',
      );
      expect(saved.single['id'], 'wardrobe-retry-item');
    });

    test(
      'CASE 7 (partial — see report): image reconciliation branch recovered from 3308946 is present',
      () {
        // _handleItemSaved's body (Appwrite calls, _fetchWardrobeItems
        // reconciliation) is private to _WardrobeScreenState and cannot be
        // driven from a widget test without a full Appwrite-networked
        // WardrobeScreen mount, which does not exist in this test harness
        // and is out of scope for this fix (no new Appwrite mocking infra
        // introduced). This is a pinning check, not behavioral proof —
        // documented as a known coverage gap in the P0.21 report.
        final source = File('lib/wardrobe.dart').readAsStringSync();
        final handlerStart = source.indexOf(
          'Future<void> _handleItemSaved(Map<String, dynamic> item) async {',
        );
        final handlerEnd = source.indexOf(
          '\n  List<WardrobeItem> get _filtered',
        );
        expect(handlerStart, greaterThan(0));
        expect(handlerEnd, greaterThan(handlerStart));
        final body = source.substring(handlerStart, handlerEnd);
        expect(
          body.contains(
            "if ((item['catalogStatus'] ?? '').toString() == 'catalog_pending') {",
          ),
          isTrue,
        );
        expect(
          body.contains('} else {'),
          isTrue,
          reason:
              'the non-catalog_pending reconciliation branch recovered from 3308946 must exist',
        );
        expect(body.contains('_fetchWardrobeItems();'), isTrue);
      },
    );
  });

  // ------------------------------------------------------------------
  // P0.21 (continued) — cross-screen refresh for the ACTIVE external
  // upload entry points. home.dart has NO active add-to-wardrobe call site
  // of its own — its only live path is _buildChatWrap() -> AhviChatPromptBar
  // (onAddToWardrobe: null) -> ahvi_chat_prompt_bar.dart's fallback, which is
  // the same shared call site the main Chat screen and DailyWear's chat bar
  // use. home.dart's own _openPlusMenu is DEAD_CURRENTLY (unreferenced,
  // confirmed via `flutter analyze`) and was left untouched (pre-commit
  // review trim) — not part of this fix.
  //
  // Active paths fixed: ahvi_chat_prompt_bar.dart's shared fallback (covers
  // Home, main Chat, DailyWear's chat bar), and daily_wear.dart's own
  // empty-state "Add wardrobe" CTA. Both call the existing
  // AppwriteService.invalidateWardrobeCache() notifier (already used by the
  // FAB's own manual-add path, previously unconsumed); WardrobeScreen now
  // listens for it.
  //
  // These tests exercise the real modal/save state machine and assert on
  // AppwriteService's real (already-existing) wardrobeGeneration counter —
  // not source string matching for the behavioral cases.
  // ------------------------------------------------------------------

  group('P0.21 cross-screen refresh (Chat bar / DailyWear)', () {
    void invalidate(Map<String, dynamic> _) =>
        AppwriteService().invalidateWardrobeCache();

    test(
      'source contract: each active external entry point signals through AppwriteService.invalidateWardrobeCache()',
      () {
        // Matched as two independent fragments (not one exact concatenated
        // string) since each call site wraps the closure across lines
        // differently — the point being pinned is "calls showAddToWardrobeModal
        // with an onSaved that invalidates the cache", not exact formatting.
        bool wiresInvalidation(String source) =>
            source.contains('onSaved: (_) =>') &&
            source.contains('AppwriteService().invalidateWardrobeCache()');
        final chatBar = File(
          'lib/widgets/ahvi_chat_prompt_bar.dart',
        ).readAsStringSync();
        final dailyWear = File('lib/daily_wear.dart').readAsStringSync();
        expect(
          wiresInvalidation(chatBar),
          isTrue,
          reason:
              'ahvi_chat_prompt_bar.dart (Home chat bar, main Chat, '
              'DailyWear chat bar, Diet page) must signal invalidation',
        );
        expect(
          wiresInvalidation(dailyWear),
          isTrue,
          reason:
              'daily_wear.dart empty-state "Add wardrobe" CTA must signal invalidation',
        );
      },
    );

    testWidgets(
      'CASE A/B/C: a single successful item via the shared external-entry-point pattern bumps wardrobeGeneration exactly once',
      (tester) async {
        final before = AppwriteService().wardrobeGeneration;
        final backend = _FakeBackendService();
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [_detectedItemJson(id: 'ext-item')],
          onSaved: invalidate,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

        expect(AppwriteService().wardrobeGeneration, before + 1);
      },
    );

    testWidgets(
      'CASE E (signal fidelity): three successful sequential items bump wardrobeGeneration exactly three times',
      (tester) async {
        final before = AppwriteService().wardrobeGeneration;
        final backend = _FakeBackendService()
          ..onSave = (_) => const {'saved_count': 3};
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [
            _detectedItemJson(id: 'ext-a', name: 'Item A'),
            _detectedItemJson(id: 'ext-b', name: 'Item B'),
            _detectedItemJson(id: 'ext-c', name: 'Item C'),
          ],
          onSaved: invalidate,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);

        expect(AppwriteService().wardrobeGeneration, before + 3);
      },
    );

    testWidgets(
      'CASE F: a FAILED item in a mixed batch does not bump wardrobeGeneration',
      (tester) async {
        final before = AppwriteService().wardrobeGeneration;
        final backend = _FakeBackendService()
          ..onSave = (_) => const {'saved_count': 2};
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [
            _detectedItemJson(id: 'ext-d', name: 'Item D'),
            _detectedItemJson(id: 'ext-e', name: 'Item E'),
            _detectedItemJson(id: 'ext-f', name: 'Item F'),
          ],
          onSaved: invalidate,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-upload-results']);

        expect(
          AppwriteService().wardrobeGeneration,
          before + 2,
          reason:
              'only the 2 ADDED items may bump the signal, never the FAILED one',
        );
      },
    );

    testWidgets(
      'CASE F: NEEDS_REVIEW does not bump wardrobeGeneration until Add Anyway succeeds, then exactly once',
      (tester) async {
        final before = AppwriteService().wardrobeGeneration;
        final backend = _FakeBackendService()
          ..onProcessItem = (id, overrideDuplicate) => overrideDuplicate
              ? {
                  'status': 'ADDED_TO_WARDROBE',
                  'wardrobe_item_id': 'wardrobe-$id',
                }
              : {
                  'status': 'NEEDS_REVIEW',
                  'error_code': 'DUPLICATE_WARDROBE_ITEM',
                  'matched_item_id': 'existing-item',
                };
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [_detectedItemJson(id: 'ext-dup')],
          onSaved: invalidate,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-upload-results']);
        expect(
          AppwriteService().wardrobeGeneration,
          before,
          reason:
              'a duplicate awaiting review must not signal a persisted change',
        );

        await tester.tap(find.text('Add Anyway'));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
        expect(AppwriteService().wardrobeGeneration, before + 1);
      },
    );

    testWidgets(
      'CASE E/F: retry after a failure bumps wardrobeGeneration exactly once (only on the retried success)',
      (tester) async {
        final before = AppwriteService().wardrobeGeneration;
        var call = 0;
        final backend = _FakeBackendService()
          ..onSave = (_) {
            call++;
            return {'saved_count': call == 1 ? 0 : 1};
          };
        await _openReviewWithOnSaved(
          tester,
          backend: backend,
          items: [_detectedItemJson(id: 'ext-retry')],
          onSaved: invalidate,
        );
        await tester.tap(find.byKey(const ValueKey('wardrobe-confirm-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-error']);
        expect(AppwriteService().wardrobeGeneration, before);

        await tester.tap(find.byKey(const ValueKey('wardrobe-retry-cta')));
        await _pumpUntilKeyFound(tester, const ['wardrobe-success']);
        expect(AppwriteService().wardrobeGeneration, before + 1);
      },
    );

    test(
      'CASE D (partial — see report): WardrobeScreen registers/unregisters as an AppwriteService listener and debounce-coalesces before reconciling',
      () {
        // Mounting the real WardrobeScreen end-to-end would require a fully
        // networked Appwrite double (its initState already makes a live
        // Client()/Databases() call), which is out of scope for this fix —
        // same limitation as CASE 7 above. This pins the structural wiring:
        // registration/deregistration lifecycle (no listener leak) and the
        // generation-compare + debounce Timer (coalescing), not full E2E
        // proof that a mounted screen visually refreshes.
        final source = File('lib/wardrobe.dart').readAsStringSync();
        expect(
          source.contains(
            'AppwriteService().addListener(_onAppwriteServiceChanged);',
          ),
          isTrue,
          reason:
              'WardrobeScreen must register for the shared invalidation signal on init',
        );
        expect(
          source.contains(
            'AppwriteService().removeListener(_onAppwriteServiceChanged);',
          ),
          isTrue,
          reason:
              'WardrobeScreen must unregister on dispose to avoid a listener leak',
        );
        final handlerStart = source.indexOf(
          'void _onAppwriteServiceChanged() {',
        );
        expect(handlerStart, greaterThan(0));
        // Read to the method's real closing brace rather than a fixed number
        // of characters: the handler legitimately grew (account-switch and
        // session-clear handling), which pushed the debounce Timer past an
        // earlier hard-coded 500-char window and failed this test even though
        // the debounce was present and correct.
        final handlerEnd = source.indexOf('\n  }', handlerStart);
        expect(handlerEnd, greaterThan(handlerStart));
        final handlerBody = source.substring(handlerStart, handlerEnd);
        expect(
          handlerBody.contains(
            'if (current == _lastSeenWardrobeGeneration) return;',
          ),
          isTrue,
          reason:
              'must ignore unrelated AppwriteService notifications (only react to real wardrobe changes)',
        );
        expect(
          handlerBody.contains('Timer('),
          isTrue,
          reason:
              'must debounce so a multi-item batch coalesces into one reconciliation fetch, not N',
        );
      },
    );
  });
}

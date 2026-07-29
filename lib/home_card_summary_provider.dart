import 'package:flutter/widgets.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/models/home_today_summary.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HomeCardSummaryProvider
// ═══════════════════════════════════════════════════════════════════════════════
//
// Single provider for ALL five home-card routine summaries:
//   wear · move · eat · care (skincare) · medicine
//
// Backend summary (GET /api/home/today-summary) is the base state; local
// completion events (markWearDone, updateSkincare, updateFromMeds) augment
// the currently displayed card for the same user/date.
//
// Registration in main.dart:
//   ChangeNotifierProxyProvider2<AppwriteService, BackendService,
//       HomeCardSummaryProvider>(
//     create: (_) => HomeCardSummaryProvider(),
//     update: (_, appwrite, backend, p) => p!..configure(backend, appwrite),
//   )
// ═══════════════════════════════════════════════════════════════════════════════

class HomeCardSummaryProvider extends ChangeNotifier {
  // ─── Backend-backed state ────────────────────────────────────────────────────

  BackendService? _backend;
  AppwriteService? _appwrite;

  bool _isLoading = false;
  Object? _error;
  HomeTodaySummary? _summary;
  String? _summaryCacheKey; // '$userId:$localDate' for last successful fetch
  String? _summaryInflightKey;
  Future<void>? _summaryInFlight;
  int _generation = 0; // incremented on reset; guards stale-in-flight writes

  bool get isLoading => _isLoading;
  Object? get error => _error;
  HomeTodaySummary? get summary => _summary;

  // ── Test seams ───────────────────────────────────────────────────────────────

  @visibleForTesting
  String? Function()? debugCurrentUserIdProvider;

  @visibleForTesting
  String Function()? debugLocalDateProvider;

  @visibleForTesting
  Future<HomeTodaySummary> Function()? debugSummaryFetcher;

  /// Generation counter — increments on every [reset]. Exposed for tests that
  /// assert a session invalidation fired exactly once (no duplicate listener).
  @visibleForTesting
  int get debugGeneration => _generation;

  // ── Wiring ───────────────────────────────────────────────────────────────────

  /// Called by ChangeNotifierProxyProvider2 whenever AppwriteService or
  /// BackendService is updated. Safe to call multiple times.
  void configure(BackendService backend, AppwriteService appwrite) {
    // Idempotent: always detach from the previously-wired AppwriteService (the
    // same one on a rebuild, or an old instance when dependencies change)
    // before attaching, so the listener is registered exactly once.
    if (_appwrite != null) {
      _appwrite!.removeSessionInvalidationListener(_onSessionInvalidated);
    }
    _backend = backend;
    _appwrite = appwrite;
    appwrite.addSessionInvalidationListener(_onSessionInvalidated);
  }

  @override
  void dispose() {
    // Detach from the session-invalidation broadcast so a disposed provider is
    // never called back (which would notifyListeners() after dispose).
    _appwrite?.removeSessionInvalidationListener(_onSessionInvalidated);
    _appwrite = null;
    super.dispose();
  }

  String _localDate() =>
      debugLocalDateProvider?.call() ??
      DateTime.now().toLocal().toIso8601String().substring(0, 10);

  String? _resolveUserId() {
    if (debugCurrentUserIdProvider != null) return debugCurrentUserIdProvider!();
    return _appwrite?.currentUserId;
  }

  String? _cacheKey() {
    final id = _resolveUserId();
    return (id != null && id.isNotEmpty) ? '$id:${_localDate()}' : null;
  }

  // ─── Public API ──────────────────────────────────────────────────────────────

  /// Fetches the today-summary from the backend. Returns immediately on cache
  /// hit or in-flight join; fetches once per user+date. Fire-and-forget safe.
  ///
  /// [forceRefresh] clears the cache entry so the next fetch runs even if the
  /// user+date key matches, while retaining the last successful summary for
  /// stale display during the reload. Does NOT clear [summary].
  Future<void> refresh({bool forceRefresh = false}) {
    final backend = _backend;
    // debugSummaryFetcher is the test seam — allow refresh without a real
    // backend when it is set so unit tests don't need a wired BackendService.
    if (backend == null && debugSummaryFetcher == null) return Future.value();

    final key = _cacheKey();

    if (forceRefresh) {
      // Invalidate cache entry without wiping the visible summary — callers
      // see stale data while the reload is in progress.
      _summaryCacheKey = null;
    }

    // Cache hit: same user+date
    if (_summary != null && _summaryCacheKey == key) return Future.value();

    // Single-flight: join existing in-flight for same scope
    if (_summaryInFlight != null && _summaryInflightKey == key) {
      return _summaryInFlight!;
    }

    final gen = ++_generation;
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    final future = _doFetch(backend, key, gen);
    _summaryInFlight = future;
    _summaryInflightKey = key;
    return future;
  }

  Future<void> _doFetch(BackendService? backend, String? key, int gen) async {
    try {
      final fetcher = debugSummaryFetcher ?? backend!.getHomeTodaySummary;
      final result = await fetcher();
      if (_generation != gen) {
        debugPrint('home.summary.stale_ignored');
        return;
      }
      _summary = result;
      _summaryCacheKey = key;
      _error = null;
    } catch (e) {
      if (_generation != gen) {
        debugPrint('home.summary.stale_ignored');
        return;
      }
      debugPrint('home.summary.failed err=${e.runtimeType}');
      _error = e;
      // Retain last successful summary for same user/date — only clear across
      // users or dates (handled by reset()).
    } finally {
      if (_generation == gen) {
        _isLoading = false;
        _summaryInFlight = null;
        _summaryInflightKey = null;
        notifyListeners();
      }
    }
  }

  void _onSessionInvalidated() {
    debugPrint('home.summary.reset');
    reset();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1.  WEAR / MOVE / EAT / CARE  (translation-key–based summary strings)
  // ─────────────────────────────────────────────────────────────────────────

  static const String _wearMaleKey    = 'home_card_wear_male';
  static const String _wearFemaleKey  = 'home_card_wear_female';
  static const String _wearDefaultKey = 'home_card_wear_default';
  static const String _moveDefaultKey = 'home_card_move_default';
  static const String _eatDefaultKey  = 'home_card_eat_default';
  static const String _careDefaultKey = 'home_card_care_default';

  /// Gender-aware neutral fallback KEY for the "Wear" line.
  static String wearFallbackKeyFor(String? gender) {
    switch ((gender ?? '').trim().toLowerCase()) {
      case 'male':
      case 'm':
      case 'man':
      case 'men':
        return _wearMaleKey;
      case 'female':
      case 'f':
      case 'woman':
      case 'women':
        return _wearFemaleKey;
      default:
        return _wearDefaultKey;
    }
  }

  String _wear = _wearDefaultKey;
  String _move = _moveDefaultKey;
  String _eat  = _eatDefaultKey;
  String _care = _careDefaultKey;

  bool _wearFromBackend = false;

  String get wear => _wear;
  String get move => _move;
  String get eat  => _eat;
  String get care => _care;

  String wearFor(BuildContext context) => context.tr(_wear);
  String moveFor(BuildContext context) => context.tr(_move);
  String eatFor(BuildContext context)  => context.tr(_eat);
  String careFor(BuildContext context) => context.tr(_care);

  void applyGenderFallback(String? gender) {
    if (_wearFromBackend) return;
    final next = wearFallbackKeyFor(gender);
    if (next == _wear) return;
    _wear = next;
    notifyListeners();
  }

  bool _setIfUseful(
    String current,
    String value,
    void Function(String) assign,
  ) {
    final cleaned = value.trim();
    if (cleaned.isEmpty || cleaned == current) return false;
    assign(cleaned);
    notifyListeners();
    return true;
  }

  void setWear(String value) {
    final changed = _setIfUseful(_wear, value, (c) => _wear = c);
    if (changed || value.trim().isNotEmpty) _wearFromBackend = true;
  }

  void setMove(String value) => _setIfUseful(_move, value, (c) => _move = c);
  void setEat(String value)  => _setIfUseful(_eat,  value, (c) => _eat  = c);
  void setCare(String value) => _setIfUseful(_care, value, (c) => _care = c);

  // ─────────────────────────────────────────────────────────────────────────
  // 1b.  WEAR — DAILY COMPLETION STATE
  // ─────────────────────────────────────────────────────────────────────────

  bool   _wearDone       = false;
  String _wearOutfitName = '';

  bool   get isWearDone     => _wearDone;
  String get wearOutfitName => _wearOutfitName;

  // ── Backend card display contract ────────────────────────────────────────
  //
  // subtitle/description  = backend headline
  // supporting/status copy = backend context
  //
  // The backend `status` field (machine values: ready, due_now, unavailable)
  // is internal-only and is NEVER read here — it must not reach the UI.
  //
  // available == true  → headline / context (null → caller uses local state)
  // available == false → supplied headline/context, else neutral copy. An
  //   explicitly-unavailable card is shown honestly; it is never replaced with
  //   personalised local fallback text. Local completion state augments only a
  //   present, available (same-user/date) card via absence of a backend value.

  static const String _kUnavailableSubtitle = 'Not available today';
  static const String _kUnavailableStatus = '—';

  /// Subtitle from a backend card per the display contract, or null when the
  /// caller should fall through to local state (no card, or available card
  /// with no headline).
  String? _backendSubtitle(HomeTodayCard? bc) {
    if (bc == null) return null;
    if (bc.available) return bc.headline.isNotEmpty ? bc.headline : null;
    if (bc.headline.isNotEmpty) return bc.headline;
    if (bc.context.isNotEmpty) return bc.context;
    return _kUnavailableSubtitle;
  }

  /// Supporting/status copy from a backend card per the display contract, or
  /// null when the caller should fall through to local state. The machine
  /// `status` field is deliberately never read.
  String? _backendStatus(HomeTodayCard? bc) {
    if (bc == null) return null;
    if (bc.available) return bc.context.isNotEmpty ? bc.context : null;
    if (bc.context.isNotEmpty) return bc.context;
    return _kUnavailableStatus;
  }

  // ── Backend-backed display getters (Wear) ────────────────────────────────

  /// One-liner subtitle for the Home "Wear" card (backend headline preferred).
  String get wearHomeSubtitle {
    final b = _backendSubtitle(_summary?.wear);
    if (b != null) return b;
    return _wearOutfitName.isNotEmpty ? _wearOutfitName : '';
  }

  /// Short status label for the Wear card (backend context preferred).
  String get wearHomeStatus {
    final b = _backendStatus(_summary?.wear);
    if (b != null) return b;
    return _wearDone ? 'Done' : 'Pick outfit';
  }

  void markWearDone({required bool done, String outfitName = ''}) {
    final changed = _wearDone != done || _wearOutfitName != outfitName;
    _wearDone = done;
    _wearOutfitName = outfitName;
    if (changed) notifyListeners();
  }

  // ── Backend-backed display getters (Move) ────────────────────────────────

  /// One-liner subtitle for the Home "Move" card from the backend summary.
  /// Returns empty string only when there is no backend move card, so home.dart
  /// falls through to the existing fitness-signal logic; an explicitly
  /// unavailable card yields honest neutral copy instead.
  String get moveHomeSubtitle => _backendSubtitle(_summary?.move) ?? '';

  /// Short status label for the Move card (backend context preferred).
  String get moveHomeStatus => _backendStatus(_summary?.move) ?? '';

  // ── Backend-backed display getters (Eat) ─────────────────────────────────

  /// One-liner subtitle for the Home "Eat" card from the backend summary.
  String get eatHomeSubtitle => _backendSubtitle(_summary?.eat) ?? '';

  /// Short status label for the Eat card (backend context preferred).
  String get eatHomeStatus => _backendStatus(_summary?.eat) ?? '';

  // ─────────────────────────────────────────────────────────────────────────
  // 2.  SKINCARE  (formerly SkincareStateProvider)
  // ─────────────────────────────────────────────────────────────────────────

  bool         _isNight        = false;
  int          _completedSteps = 0;
  int          _totalSteps     = 5;
  String       _skinType       = '';
  List<String> _concerns       = const [];

  bool         get isNight        => _isNight;
  int          get completedSteps => _completedSteps;
  int          get totalSteps     => _totalSteps;
  String       get skinType       => _skinType;
  List<String> get concerns       => List.unmodifiable(_concerns);

  double get skincareProgressPct =>
      _totalSteps == 0 ? 0.0 : _completedSteps / _totalSteps;

  bool get isSkincareDone =>
      _completedSteps >= _totalSteps && _totalSteps > 0;

  // ── Backend-backed display getters (Care) ────────────────────────────────

  String get skincareHomeSubtitle {
    final b = _backendSubtitle(_summary?.care);
    if (b != null) return b;
    // Local fallback — only when there is no backend care card at all.
    if (isSkincareDone) {
      return _isNight ? 'Night routine done ✓' : 'Morning glow done ✓';
    }
    if (_completedSteps > 0) {
      final rem = _totalSteps - _completedSteps;
      return '$_completedSteps/$_totalSteps · $rem left';
    }
    if (_skinType.isNotEmpty) {
      return _isNight ? 'Night routine' : 'Morning glow';
    }
    return 'Care routine';
  }

  String get skincareHomeStatus {
    final b = _backendStatus(_summary?.care);
    if (b != null) return b;
    // Local fallback
    if (isSkincareDone) return 'Done';
    if (_completedSteps > 0) {
      return '${(skincareProgressPct * 100).round()}%';
    }
    final hour = DateTime.now().hour;
    if ((hour >= 6 && hour < 12) || hour >= 19) return 'Time';
    return 'Later';
  }

  void updateSkincare({
    required bool isNight,
    required int completedSteps,
    required int totalSteps,
    String skinType = '',
    List<String> concerns = const [],
  }) {
    _isNight        = isNight;
    _completedSteps = completedSteps;
    _totalSteps     = totalSteps;
    _skinType       = skinType;
    _concerns       = List.unmodifiable(concerns);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3.  MEDICINE  (formerly MedicineStateProvider)
  // ─────────────────────────────────────────────────────────────────────────

  int _totalMeds   = 0;
  int _takenToday  = 0;
  int _pendingToday = 0;

  int get totalMeds    => _totalMeds;
  int get takenToday   => _takenToday;
  int get pendingToday => _pendingToday;

  double get medicineAdherence =>
      _totalMeds == 0 ? 0.0 : _takenToday / _totalMeds;

  bool get allMedsTaken => _totalMeds > 0 && _takenToday >= _totalMeds;

  bool get isMedicineDone => allMedsTaken;

  // ── Backend-backed display getters (Medicine) ────────────────────────────
  // Medicine text must come from backend safe fields only.
  // Never infer or display medicine name, dose, diagnosis, or prescription data.

  String get medicineHomeSubtitle {
    final b = _backendSubtitle(_summary?.medicine);
    if (b != null) return b;
    // Local fallback — count-only; never the medicine name.
    if (_totalMeds == 0) return 'No meds today';
    if (allMedsTaken) return 'All meds taken ✓';
    return '$_takenToday/$_totalMeds taken';
  }

  String get medicineHomeStatus {
    final b = _backendStatus(_summary?.medicine);
    if (b != null) return b;
    // Local fallback
    if (_totalMeds == 0) return 'None';
    if (allMedsTaken) return 'Done';
    if (_pendingToday > 0) {
      final hour = DateTime.now().hour;
      return (hour >= 8 && hour < 10) ? 'Now' : 'Pending';
    }
    return 'Upcoming';
  }

  /// Push a full medication snapshot after any load or mutation.
  /// Only meds with reminder == true count toward the badge.
  void updateFromMeds(List<Map<String, dynamic>> meds) {
    final reminded = meds.where((m) => m['reminder'] == true).toList();
    _totalMeds    = reminded.length;
    _takenToday   = reminded.where((m) => m['taken'] == true).length;
    _pendingToday = _totalMeds - _takenToday;
    // NOTE: _nextMedName intentionally removed — never display medication
    // names on the Home card (medicine privacy requirement).
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4.  FULL RESET
  // ─────────────────────────────────────────────────────────────────────────

  /// Resets all five card summaries to defaults. Called on sign-out and
  /// user switching (via onSessionInvalidated).
  void reset() {
    _generation++; // invalidate any in-flight fetch

    // Backend state
    _summary = null;
    _summaryCacheKey = null;
    _summaryInFlight = null;
    _summaryInflightKey = null;
    _isLoading = false;
    _error = null;

    // Wear / Move / Eat / Care strings
    _wear          = _wearDefaultKey;
    _wearFromBackend = false;
    _move          = _moveDefaultKey;
    _eat           = _eatDefaultKey;
    _care          = _careDefaultKey;

    // Wear daily completion
    _wearDone       = false;
    _wearOutfitName = '';

    // Skincare
    _isNight        = false;
    _completedSteps = 0;
    _totalSteps     = 5;
    _skinType       = '';
    _concerns       = const [];

    // Medicine (count-only; no medicine names stored)
    _totalMeds    = 0;
    _takenToday   = 0;
    _pendingToday = 0;

    notifyListeners();
  }
}

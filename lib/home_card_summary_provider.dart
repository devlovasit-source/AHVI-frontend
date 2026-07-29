import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'app_localizations.dart'; // adjust path as needed

// ═══════════════════════════════════════════════════════════════════════════════
// HomeCardSummaryProvider
// ═══════════════════════════════════════════════════════════════════════════════
//
// Single provider for ALL five home-card routine summaries:
//   wear · move · eat · care (skincare) · medicine
//
// Previously split across three files:
//   • home_card_summary_provider.dart  → wear / move / eat / care strings
//   • skincare_state_provider.dart     → live skincare progress
//   • medicine_state_provider.dart     → live medication adherence
//
// Now consolidated here so your MultiProvider only needs ONE registration:
//
//   ChangeNotifierProvider(create: (_) => HomeCardSummaryProvider()),
//
// Migration notes
// ───────────────
// • SkincareScreen   — replace `context.read<SkincareStateProvider>().update(...)`
//                      with   `context.read<HomeCardSummaryProvider>().updateSkincare(...)`
//
// • MediTrackScreen  — replace `context.read<MedicineStateProvider>().updateFromMeds(...)`
//                      with   `context.read<HomeCardSummaryProvider>().updateFromMeds(...)`
//
// • home_optimized.dart — remove the two extra imports and the two extra
//   `context.watch<>()` calls; `context.watch<HomeCardSummaryProvider>()`
//   already causes the routine cards row to repaint for ALL five cards.
//
// ═══════════════════════════════════════════════════════════════════════════════

class HomeCardSummaryProvider extends ChangeNotifier {
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
  /// Never a specific gendered look unless the backend supplies a real one.
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

  // True once a real (backend/dynamic) wear summary has been set, so the
  // gender fallback never overrides genuine data.
  bool _wearFromBackend = false;

  // ── Raw stored values (key or backend literal) ───────────────────────────

  String get wear => _wear;
  String get move => _move;
  String get eat  => _eat;
  String get care => _care;

  // ── Resolved display text for the current locale ─────────────────────────

  String wearFor(BuildContext context) => context.tr(_wear);
  String moveFor(BuildContext context) => context.tr(_move);
  String eatFor(BuildContext context)  => context.tr(_eat);
  String careFor(BuildContext context) => context.tr(_care);

  // ── Mutators ──────────────────────────────────────────────────────────────

  /// Apply the gender-aware fallback ONLY while no real summary has arrived.
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
  // 1b.  WEAR — DAILY COMPLETION STATE  (drives the Home "Wear" bubble/card)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Separate from the `_wear` summary string above (which is a fallback
  // gender-based greeting key). This tracks whether the user has actually
  // picked/confirmed an outfit TODAY in DailyWearScreen — call markWearDone()
  // from _DailyWearScreenState._wearOutfit() every time the user taps
  // "Wear this".

  bool   _wearDone       = false;
  String _wearOutfitName = '';

  bool   get isWearDone     => _wearDone;
  String get wearOutfitName => _wearOutfitName;

  /// One-liner subtitle shown on the Home "Wear" card once an outfit is picked.
  String get wearHomeSubtitle =>
      _wearOutfitName.isNotEmpty ? _wearOutfitName : '';

  /// Short status label shown next to the check/clock icon on the Wear card.
  String get wearHomeStatus => _wearDone ? 'Done' : 'Pick outfit';

  /// Push wear completion from DailyWearScreen whenever the user confirms
  /// today's outfit (or un-confirms it, e.g. picking a different one).
  void markWearDone({required bool done, String outfitName = ''}) {
    final changed = _wearDone != done || _wearOutfitName != outfitName;
    _wearDone = done;
    _wearOutfitName = outfitName;
    if (changed) notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2.  SKINCARE  (formerly SkincareStateProvider)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Call updateSkincare() from _SkincareScreenState._pushToHome() after
  // every mutation (markStep, loadProfile, setRoutine, toggleConcern).

  bool         _isNight        = false;
  int          _completedSteps = 0;
  int          _totalSteps     = 5; // default; updated when routine loads
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

  // ── Derived labels for the home "Care" card ──────────────────────────────

  /// One-liner subtitle shown on the "Care" routine card.
  String get skincareHomeSubtitle {
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

  /// Short status label shown next to the check/clock icon.
  String get skincareHomeStatus {
    if (isSkincareDone) return 'Done';
    if (_completedSteps > 0) {
      return '${(skincareProgressPct * 100).round()}%';
    }
    final hour = DateTime.now().hour;
    if ((hour >= 6 && hour < 12) || hour >= 19) return 'Time';
    return 'Later';
  }

  // ── Mutator (called by SkincareScreen) ───────────────────────────────────

  /// Push a full skincare state snapshot after any mutation in SkincareScreen.
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
  //
  // Call updateFromMeds() from _MediTrackScreenState._pushToHome() after
  // _fetchData() and after every _markTaken() / deleteMed().

  int    _totalMeds   = 0;
  int    _takenToday  = 0;
  int    _pendingToday = 0;
  String _nextMedName = '';

  int    get totalMeds    => _totalMeds;
  int    get takenToday   => _takenToday;
  int    get pendingToday => _pendingToday;
  String get nextMedName  => _nextMedName;

  double get medicineAdherence =>
      _totalMeds == 0 ? 0.0 : _takenToday / _totalMeds;

  bool get allMedsTaken => _totalMeds > 0 && _takenToday >= _totalMeds;

  bool get isMedicineDone => allMedsTaken;

  // ── Derived labels for the home "Medicine" card ──────────────────────────

  /// One-liner subtitle shown on the "Medicine" routine card.
  String get medicineHomeSubtitle {
    if (_totalMeds == 0) return 'No meds today';
    if (allMedsTaken) return 'All meds taken ✓';
    if (_nextMedName.isNotEmpty) {
      final name = _nextMedName.length > 14
          ? '${_nextMedName.substring(0, 12)}…'
          : _nextMedName;
      return 'Next: $name';
    }
    return '$_takenToday/$_totalMeds taken';
  }

  /// Short status label shown next to the check/clock icon.
  String get medicineHomeStatus {
    if (_totalMeds == 0) return 'None';
    if (allMedsTaken) return 'Done';
    if (_pendingToday > 0) {
      final hour = DateTime.now().hour;
      return (hour >= 8 && hour < 10) ? 'Now' : 'Pending';
    }
    return 'Upcoming';
  }

  // ── Mutator (called by MediTrackScreen) ──────────────────────────────────

  /// Push a full medication snapshot after any load or mutation.
  ///
  /// [meds] is the raw list from _MediTrackScreenState.meds.
  /// Only meds with reminder == true are counted toward the badge.
  void updateFromMeds(List<Map<String, dynamic>> meds) {
    final reminded    = meds.where((m) => m['reminder'] == true).toList();
    _totalMeds        = reminded.length;
    _takenToday       = reminded.where((m) => m['taken'] == true).length;
    _pendingToday     = _totalMeds - _takenToday;
    final pending     = reminded.where((m) => m['taken'] != true).toList();
    _nextMedName      = pending.isNotEmpty
        ? (pending.first['name'] ?? '').toString()
        : '';
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4.  FULL RESET
  // ─────────────────────────────────────────────────────────────────────────

  /// Resets all five card summaries to their defaults (call on sign-out).
  void reset() {
    // ── Wear / Move / Eat / Care strings ─────────────────────────────────
    _wear          = _wearDefaultKey;
    _wearFromBackend = false;
    _move          = _moveDefaultKey;
    _eat           = _eatDefaultKey;
    _care          = _careDefaultKey;

    // ── Wear daily completion ────────────────────────────────────────────
    _wearDone       = false;
    _wearOutfitName = '';

    // ── Skincare ─────────────────────────────────────────────────────────
    _isNight        = false;
    _completedSteps = 0;
    _totalSteps     = 5;
    _skinType       = '';
    _concerns       = const [];

    // ── Medicine ─────────────────────────────────────────────────────────
    _totalMeds      = 0;
    _takenToday     = 0;
    _pendingToday   = 0;
    _nextMedName    = '';

    notifyListeners();
  }
}
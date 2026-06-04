import 'package:flutter/foundation.dart';

/// Holds the one-line summaries shown on the home hero card.
/// Each page writes to this provider when the user makes a selection.
///
/// ── How to write from a page ──────────────────────────────────────────────
///
///   // inside DailyWearScreen, after user picks an outfit:
///   context.read<HomeCardSummaryProvider>().setWear('Silk blouse + white trousers');
///
///   // inside DietAndFitnessScreen, after user picks a workout:
///   context.read<HomeCardSummaryProvider>().setMove('20-min yoga');
///
///   // inside MainScreen (diet), after user picks a meal plan:
///   context.read<HomeCardSummaryProvider>().setEat('High-protein bowl');
///
///   // inside SkincareScreen, after user picks a routine:
///   context.read<HomeCardSummaryProvider>().setCare('AM glow routine');
///
/// ── Registration (do this once in main.dart / app root) ───────────────────
///
///   ChangeNotifierProvider(create: (_) => HomeCardSummaryProvider()),
///
/// ─────────────────────────────────────────────────────────────────────────

class HomeCardSummaryProvider extends ChangeNotifier {
  // ── Default fallback strings (shown before any page sets a value) ─────────
  String _wear = 'White shirt + denims + gold hoops';
  String _move = '7-min stretch';
  String _eat  = 'Light, protein-focused';
  String _care = 'Quick glow routine';

  // ── Getters ───────────────────────────────────────────────────────────────
  String get wear => _wear;
  String get move => _move;
  String get eat  => _eat;
  String get care => _care;

  // ── Setters — call from each page ─────────────────────────────────────────
  void setWear(String value) { _wear = value; notifyListeners(); }
  void setMove(String value) { _move = value; notifyListeners(); }
  void setEat (String value) { _eat  = value; notifyListeners(); }
  void setCare(String value) { _care = value; notifyListeners(); }

  /// Convenience: reset all back to defaults.
  void reset() {
    _wear = 'White shirt + denims + gold hoops';
    _move = '7-min stretch';
    _eat  = 'Light, protein-focused';
    _care = 'Quick glow routine';
    notifyListeners();
  }
}

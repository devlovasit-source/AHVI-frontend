// Typed models for GET /api/home/today-summary.
// Unknown JSON fields are silently ignored; missing or malformed individual
// cards become unavailable independently — one bad card cannot fail the rest.
import 'package:flutter/foundation.dart' show immutable;

// ── Action allowlist ──────────────────────────────────────────────────────────

enum HomeCardAction {
  openDailyWear,
  openFitness,
  openDiet,
  openSkincare,
  openMedi;

  static const _lookup = {
    'open_daily_wear': HomeCardAction.openDailyWear,
    'open_fitness': HomeCardAction.openFitness,
    'open_diet': HomeCardAction.openDiet,
    'open_skincare': HomeCardAction.openSkincare,
    'open_medi': HomeCardAction.openMedi,
  };

  // Returns null for any unknown value — unknown actions must never route.
  static HomeCardAction? fromString(String? s) => _lookup[s];
}

// ── HomeTodayCard ─────────────────────────────────────────────────────────────

@immutable
class HomeTodayCard {
  final String headline;
  final String context;
  final String status;
  final HomeCardAction? action;
  final String? entityId;
  final bool available;
  final String? reason;
  final String? source;

  const HomeTodayCard({
    required this.headline,
    required this.context,
    required this.status,
    this.action,
    this.entityId,
    this.available = true,
    this.reason,
    this.source,
  });

  static const HomeTodayCard _unavailable = HomeTodayCard(
    headline: '',
    context: '',
    status: '',
    available: false,
  );

  static HomeTodayCard unavailable([String? reason]) => reason == null
      ? _unavailable
      : HomeTodayCard(
          headline: '', context: '', status: '', available: false, reason: reason);

  factory HomeTodayCard.fromMap(Map<String, dynamic> m) {
    try {
      return HomeTodayCard(
        headline: (m['headline'] as String? ?? '').trim(),
        context: (m['context'] as String? ?? '').trim(),
        status: (m['status'] as String? ?? '').trim(),
        action: HomeCardAction.fromString(m['action'] as String?),
        entityId: m['entity_id'] as String?,
        available: m['available'] as bool? ?? true,
        reason: m['reason'] as String?,
        source: m['source'] as String?,
      );
    } catch (_) {
      return HomeTodayCard.unavailable('parse_error');
    }
  }
}

// ── HomeContextUsage ──────────────────────────────────────────────────────────

@immutable
class HomeContextUsage {
  final String contextVersion;
  final String contextUsage;

  const HomeContextUsage({
    required this.contextVersion,
    required this.contextUsage,
  });

  static const empty = HomeContextUsage(contextVersion: '', contextUsage: '');

  factory HomeContextUsage.fromMap(Map<String, dynamic> m) => HomeContextUsage(
    contextVersion: (m['context_version'] as String? ?? '').trim(),
    contextUsage: (m['context_usage'] as String? ?? '').trim(),
  );
}

// ── HomeTodaySummary ──────────────────────────────────────────────────────────

@immutable
class HomeTodaySummary {
  final String date;
  final String timezone;
  final HomeContextUsage contextUsage;
  final HomeTodayCard wear;
  final HomeTodayCard move;
  final HomeTodayCard eat;
  final HomeTodayCard care;
  final HomeTodayCard medicine;

  const HomeTodaySummary({
    required this.date,
    required this.timezone,
    required this.contextUsage,
    required this.wear,
    required this.move,
    required this.eat,
    required this.care,
    required this.medicine,
  });

  static HomeTodayCard _safeCard(Map<String, dynamic> cards, String key) {
    try {
      final v = cards[key];
      if (v is! Map) return HomeTodayCard.unavailable('missing');
      return HomeTodayCard.fromMap(Map<String, dynamic>.from(v));
    } catch (_) {
      return HomeTodayCard.unavailable('parse_error');
    }
  }

  factory HomeTodaySummary.fromMap(Map<String, dynamic> m) {
    final cards = m['cards'] is Map
        ? Map<String, dynamic>.from(m['cards'] as Map)
        : const <String, dynamic>{};
    return HomeTodaySummary(
      date: (m['date'] as String? ?? '').trim(),
      timezone: (m['timezone'] as String? ?? '').trim(),
      contextUsage: m['context_usage'] is Map
          ? HomeContextUsage.fromMap(
              Map<String, dynamic>.from(m['context_usage'] as Map),
            )
          : HomeContextUsage.empty,
      wear: _safeCard(cards, 'wear'),
      move: _safeCard(cards, 'move'),
      eat: _safeCard(cards, 'eat'),
      care: _safeCard(cards, 'care'),
      medicine: _safeCard(cards, 'medicine'),
    );
  }
}

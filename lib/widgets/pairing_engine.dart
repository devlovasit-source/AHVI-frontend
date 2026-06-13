// ============================================================
// pairing_engine.dart
// Local, rules-based "AI" pairing logic.
//
// Used until a real backend matching endpoint exists. Computes:
//   - worksWellWith(item, allItems) -> List<WardrobeItem>
//   - bestFor(item) -> List<String> (occasion chips)
//   - avoid(item) -> List<String>
//
// Designed so results differ per-garment (no hardcoded same list
// for every item) by scoring on category compatibility, occasion
// overlap, and basic color harmony.
// ============================================================

import 'package:myapp/models/detected_item.dart';

class PairingEngine {
  // ============================================================
  // CATEGORY COMPATIBILITY MAP
  // Which categories visually/functionally pair with which.
  // ============================================================
  static const Map<String, List<String>> _compatibleCategories = {
    'Tops': ['Bottoms', 'Outerwear', 'Footwear', 'Accessories', 'Bags', 'Jewelry'],
    'Bottoms': ['Tops', 'Outerwear', 'Footwear', 'Accessories', 'Bags'],
    'Dresses': ['Outerwear', 'Footwear', 'Accessories', 'Bags', 'Jewelry'],
    'Outerwear': ['Tops', 'Bottoms', 'Dresses', 'Footwear', 'Accessories'],
    'Footwear': ['Tops', 'Bottoms', 'Dresses', 'Outerwear'],
    'Accessories': ['Tops', 'Bottoms', 'Dresses', 'Outerwear'],
    'Bags': ['Tops', 'Bottoms', 'Dresses'],
    'Jewelry': ['Tops', 'Dresses'],
  };

  // ============================================================
  // COLOR HARMONY GROUPS
  // Items in the same or a "neutral pairs with everything" group
  // get a bonus score.
  // ============================================================
  static const List<String> _neutrals = [
    'white', 'black', 'gray', 'grey', 'beige', 'cream', 'navy', 'tan', 'brown', 'denim',
  ];

  static const Map<String, List<String>> _colorHarmony = {
    'pink': ['gray', 'grey', 'white', 'navy', 'denim', 'black'],
    'red': ['black', 'white', 'denim', 'navy'],
    'blue': ['white', 'gray', 'grey', 'beige', 'brown'],
    'navy': ['white', 'beige', 'cream', 'gray', 'grey'],
    'green': ['white', 'beige', 'tan', 'navy', 'black'],
    'yellow': ['navy', 'gray', 'grey', 'white', 'denim'],
    'orange': ['navy', 'denim', 'white', 'brown'],
    'brown': ['cream', 'beige', 'white', 'blue', 'green'],
    'purple': ['gray', 'grey', 'white', 'black'],
  };

  // ============================================================
  // WORKS WELL WITH
  // ============================================================
  static List<WardrobeItem> worksWellWith(
    WardrobeItem item,
    List<WardrobeItem> allItems,
  ) {
    final candidates = allItems.where((other) => other.id != item.id).toList();

    final scored = <_ScoredItem>[];

    final compatibleCats = _compatibleCategories[item.cat] ?? [];
    final itemColor = _extractColor(item.name);

    for (final other in candidates) {
      double score = 0;

      // 1. Category compatibility (primary signal)
      if (compatibleCats.contains(other.cat)) {
        score += 3;
      } else {
        // skip same-category items (e.g. two tops rarely "pair")
        continue;
      }

      // 2. Occasion overlap
      final overlap = item.occasions
          .toSet()
          .intersection(other.occasions.toSet())
          .length;
      score += overlap * 1.5;

      // 3. Color harmony
      final otherColor = _extractColor(other.name);
      if (itemColor != null && otherColor != null) {
        if (_neutrals.contains(otherColor)) {
          score += 1.5; // neutrals pair with everything
        } else if (_colorHarmony[itemColor]?.contains(otherColor) == true) {
          score += 1.0;
        }
      } else if (otherColor != null && _neutrals.contains(otherColor)) {
        score += 1.0;
      }

      // 4. Slight recency/usefulness nudge: prefer less-worn items
      // (keeps suggestions fresh / encourages use of full wardrobe)
      score += (other.worn == 0) ? 0.25 : 0;

      if (score > 0) {
        scored.add(_ScoredItem(other, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.item).toList();
  }

  // ============================================================
  // BEST FOR (occasion chips)
  // Derived from the item's existing occasions, ordered by a
  // formality ranking so the most relevant show first.
  // ============================================================
  static const List<String> _occasionPriority = [
    'Office',
    'Work',
    'Smart Casual',
    'Dinner',
    'Date Night',
    'Casual',
    'Daily',
    'Weekend',
    'Travel',
    'Gym',
    'Beach',
    'Party',
  ];

  static List<String> bestFor(WardrobeItem item) {
    if (item.occasions.isEmpty) return [];

    final normalized = item.occasions
        .map((o) => _titleCase(o))
        .toSet()
        .toList();

    normalized.sort((a, b) {
      final ai = _occasionPriority.indexOf(a);
      final bi = _occasionPriority.indexOf(b);
      final aRank = ai == -1 ? 999 : ai;
      final bRank = bi == -1 ? 999 : bi;
      return aRank.compareTo(bRank);
    });

    return normalized.take(3).toList();
  }

  // ============================================================
  // AVOID
  // Simple inverse rules: occasions explicitly unsuited to this
  // item's category/formality, used to fill the "Avoid" column.
  // ============================================================
  static List<String> avoid(WardrobeItem item) {
    final occasionsLower = item.occasions.map((o) => o.toLowerCase()).toSet();

    final isFormalLeaning = occasionsLower.any((o) =>
        o.contains('office') || o.contains('work') || o.contains('dinner') || o.contains('smart'));
    final isCasualLeaning = occasionsLower.any((o) =>
        o.contains('casual') || o.contains('daily') || o.contains('weekend'));
    final isActive = item.cat == 'Footwear' &&
        occasionsLower.any((o) => o.contains('gym') || o.contains('sport'));

    final result = <String>[];

    if (isFormalLeaning && !isActive) {
      result.addAll(['Gym', 'Beach']);
    }
    if (isFormalLeaning && !isCasualLeaning) {
      result.add('Heavy Rain');
    }
    if (isCasualLeaning && !isFormalLeaning) {
      result.addAll(['Black-Tie', 'Formal Events']);
    }
    if (item.cat == 'Dresses' || item.cat == 'Footwear') {
      if (!result.contains('Heavy Rain')) result.add('Heavy Rain');
    }

    return result.take(3).toList();
  }

  // ============================================================
  // HELPERS
  // ============================================================
  static String? _extractColor(String name) {
    final lower = name.toLowerCase();
    for (final color in [..._neutrals, ..._colorHarmony.keys]) {
      if (lower.contains(color)) return color;
    }
    return null;
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _ScoredItem {
  final WardrobeItem item;
  final double score;
  _ScoredItem(this.item, this.score);
}

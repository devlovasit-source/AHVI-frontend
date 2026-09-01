// ============================================================
// pairing_engine.dart
// Local, rules-based "AI" pairing logic.
//
// Used until a real backend matching endpoint exists. Computes:
//   - worksWellWith(item, allItems) -> List<WardrobeItem>
//   - bestFor(item) -> List<String> (occasion chips)
//   - avoid(item) -> List<String>
//
// Results differ per-garment (no hardcoded same list for every item) by
// scoring on category compatibility, occasion overlap, and color harmony.
//
// WardrobeItem is the existing repo model — it lives in wardrobe.dart, NOT a
// separate model file. Do not duplicate it.
// ============================================================

import 'package:myapp/wardrobe.dart';
import 'package:myapp/util/occasion_normalizer.dart';

class PairingEngine {
  // ============================================================
  // CATEGORY NORMALIZATION (req 7)
  // Collapse the many raw category strings the backend / user may emit
  // into the canonical buckets used by the compatibility map.
  // ============================================================
  static const Map<String, List<String>> _categoryAliases = {
    'Tops': [
      'top',
      'tops',
      'shirt',
      'tshirt',
      't-shirt',
      't shirt',
      'tee',
      'kurta',
      'kurti',
      'blouse',
      'polo',
      'sweater',
      'knit',
      'hoodie',
      'sweatshirt',
      'overshirt',
    ],
    'Bottoms': [
      'bottom',
      'bottoms',
      'trouser',
      'trousers',
      'jean',
      'jeans',
      'pant',
      'pants',
      'chino',
      'chinos',
      'short',
      'shorts',
      'skirt',
      'legging',
      'leggings',
      'churidar',
      'salwar',
    ],
    'Footwear': [
      'footwear',
      'shoe',
      'shoes',
      'sneaker',
      'sneakers',
      'sandal',
      'sandals',
      'loafer',
      'loafers',
      'boot',
      'boots',
      'heel',
      'heels',
      'mojari',
      'jutti',
    ],
    'Accessories': [
      'accessory',
      'accessories',
      'watch',
      'belt',
      'bag',
      'bags',
      'tote',
      'jewellery',
      'jewelry',
      'jewel',
      'necklace',
      'bracelet',
      'earring',
      'earrings',
      'scarf',
      'tie',
      'cap',
      'hat',
      'sunglasses',
    ],
    'Dresses': [
      'dress',
      'dresses',
      'gown',
      'saree',
      'sari',
      'lehenga',
      'anarkali',
      'jumpsuit',
    ],
    'Outerwear': [
      'outerwear',
      'blazer',
      'jacket',
      'coat',
      'overcoat',
      'cardigan',
      'chore',
      'nehru jacket',
      'bandi',
      'waistcoat',
    ],
  };

  /// Map any raw category/subcategory string to a canonical bucket.
  /// Falls back to a title-cased version of the input when no alias matches.
  static String normalizeCategory(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s.isEmpty) return 'Other';
    for (final entry in _categoryAliases.entries) {
      for (final alias in entry.value) {
        if (s == alias || s.contains(alias)) return entry.key;
      }
    }
    return _titleCase(s);
  }

  // ============================================================
  // CATEGORY COMPATIBILITY MAP (keyed by canonical buckets)
  // ============================================================
  static const Map<String, List<String>> _compatibleCategories = {
    'Tops': ['Bottoms', 'Outerwear', 'Footwear', 'Accessories'],
    'Bottoms': ['Tops', 'Outerwear', 'Footwear', 'Accessories'],
    'Dresses': ['Outerwear', 'Footwear', 'Accessories'],
    'Outerwear': ['Tops', 'Bottoms', 'Dresses', 'Footwear', 'Accessories'],
    'Footwear': ['Tops', 'Bottoms', 'Dresses', 'Outerwear'],
    'Accessories': ['Tops', 'Bottoms', 'Dresses', 'Outerwear'],
  };

  static String _blob(WardrobeItem item) => [
    item.name,
    item.cat,
    item.notes,
    ...item.occasions,
  ].join(' ').toLowerCase();

  static const Set<String> _nonFashionTerms = {
    'charger',
    'cable',
    'adapter',
    'bottle',
    'phone',
    'remote',
    'mouse',
    'keyboard',
    'laptop',
    'earbud',
    'headphone',
    'airpod',
    'plug',
    'wire',
    'battery',
    'speaker',
    'camera',
    'mug',
    'cup',
    'pen',
    'book',
    'box',
  };

  static bool _isFashionItem(WardrobeItem item) {
    final normalized = _blob(
      item,
    ).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

    if (normalized.isEmpty) return true;

    final tokens = normalized.split(RegExp(r'\s+'));

    for (final term in _nonFashionTerms) {
      if (tokens.contains(term) || tokens.contains('${term}s')) {
        return false;
      }
    }

    if (tokens.contains('powerbank')) {
      return false;
    }

    for (var i = 0; i < tokens.length - 1; i++) {
      if (tokens[i] == 'power' && tokens[i + 1] == 'bank') {
        return false;
      }
    }

    return true;
  }

  static bool _isEthnic(WardrobeItem item) {
    final blob = _blob(item);
    return blob.contains('saree') ||
        blob.contains('sari') ||
        blob.contains('lehenga') ||
        blob.contains('kurta') ||
        blob.contains('kurti') ||
        blob.contains('anarkali') ||
        blob.contains('ethnic') ||
        blob.contains('traditional') ||
        blob.contains('saree blouse') ||
        blob.contains('ethnic blouse');
  }

  static bool _isJewelry(WardrobeItem item) {
    final blob = _blob(item);
    return blob.contains('jewelry') ||
        blob.contains('jewellery') ||
        blob.contains('necklace') ||
        blob.contains('earring') ||
        blob.contains('bangle') ||
        blob.contains('bracelet') ||
        blob.contains('ring');
  }

  static bool _badEthnicPair(WardrobeItem item) {
    final blob = _blob(item);
    return blob.contains('loafer') ||
        blob.contains('leather shoe') ||
        blob.contains('formal shoe') ||
        blob.contains('oxford') ||
        blob.contains('derby') ||
        blob.contains('boot') ||
        blob.contains('sneaker') ||
        blob.contains('trainer') ||
        blob.contains('running shoe') ||
        blob.contains('sports shoe') ||
        blob.contains('cap') ||
        blob.contains('jeans') ||
        blob.contains('trouser') ||
        blob.contains('pants');
  }

  // ============================================================
  // COLOR HARMONY
  // ============================================================
  static const List<String> _neutrals = [
    'white',
    'black',
    'gray',
    'grey',
    'beige',
    'cream',
    'navy',
    'tan',
    'brown',
    'denim',
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
    final candidates = allItems
        .where((other) => other.id != item.id)
        .where(_isFashionItem)
        .toList();

    final scored = <_ScoredItem>[];

    final itemCat = normalizeCategory(item.cat);
    final itemIsEthnic = _isEthnic(item);
    final itemIsJewelry = _isJewelry(item);
    final compatibleCats = itemIsEthnic
        ? const ['Tops', 'Dresses', 'Accessories', 'Footwear', 'Outerwear']
        : itemIsJewelry
        ? const ['Tops', 'Dresses', 'Outerwear']
        : (_compatibleCategories[itemCat] ?? const []);
    final itemColor = _extractColor(item.name);

    for (final other in candidates) {
      double score = 0;

      // 1. Category compatibility (primary signal) — normalize both sides.
      final otherCat = normalizeCategory(other.cat);
      if (itemIsJewelry && otherCat == 'Bottoms') {
        continue;
      }
      if (itemIsEthnic && _badEthnicPair(other)) {
        continue;
      }
      if (itemIsEthnic && otherCat == 'Tops' && !_isEthnic(other)) {
        continue;
      }
      if (compatibleCats.contains(otherCat)) {
        score += 3;
      } else {
        continue; // skip incompatible / same-bucket items
      }

      if (itemIsEthnic) {
        if (_isJewelry(other)) score += 3;
        final otherBlob = _blob(other);
        if (otherBlob.contains('blouse') ||
            otherBlob.contains('potli') ||
            otherBlob.contains('clutch') ||
            otherBlob.contains('jutti') ||
            otherBlob.contains('mojari') ||
            otherBlob.contains('kolhapuri') ||
            otherBlob.contains('dressy sandal')) {
          score += 2.5;
        }
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
          score += 1.5;
        } else if (_colorHarmony[itemColor]?.contains(otherColor) == true) {
          score += 1.0;
        }
      } else if (otherColor != null && _neutrals.contains(otherColor)) {
        score += 1.0;
      }

      // 4. Prefer less-worn items to keep suggestions fresh
      score += (other.worn == 0) ? 0.25 : 0;

      if (score > 0) scored.add(_ScoredItem(other, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.item).toList();
  }

  // ============================================================
  // BEST FOR (occasion chips) — derived from the item's occasions,
  // ordered by a formality ranking.
  // ============================================================
  static const List<String> _occasionPriority = [
    'work',
    'casual',
    'dinner',
    'travel',
    'sport',
    'party',
    'festive',
    'wedding',
  ];

  static List<String> bestFor(WardrobeItem item) {
    if (item.occasions.isEmpty) return [];

    final byKey = <String, String>{};
    for (final occasion in item.occasions) {
      final key = canonicalOccasionKey(occasion);
      if (key.isNotEmpty) {
        byKey.putIfAbsent(key, () => humanizeOccasion(occasion));
      }
    }
    final normalized = byKey.values.toList();
    normalized.sort((a, b) {
      final ai = _occasionPriority.indexOf(canonicalOccasionKey(a));
      final bi = _occasionPriority.indexOf(canonicalOccasionKey(b));
      final aRank = ai == -1 ? 999 : ai;
      final bRank = bi == -1 ? 999 : bi;
      return aRank.compareTo(bRank);
    });
    return normalized.take(3).toList();
  }

  // ============================================================
  // AVOID
  // ============================================================
  static List<String> avoid(WardrobeItem item) {
    final occasionsLower = item.occasions.map((o) => o.toLowerCase()).toSet();
    final cat = normalizeCategory(item.cat);

    final isFormalLeaning = occasionsLower.any(
      (o) =>
          o.contains('office') ||
          o.contains('work') ||
          o.contains('dinner') ||
          o.contains('smart'),
    );
    final isCasualLeaning = occasionsLower.any(
      (o) =>
          o.contains('casual') || o.contains('daily') || o.contains('weekend'),
    );
    final isActive =
        cat == 'Footwear' &&
        occasionsLower.any((o) => o.contains('gym') || o.contains('sport'));

    final result = <String>[];
    if (isFormalLeaning && !isActive) result.addAll(['Gym', 'Beach']);
    if (isFormalLeaning && !isCasualLeaning) result.add('Heavy Rain');
    if (isCasualLeaning && !isFormalLeaning) {
      result.addAll(['Black-Tie', 'Formal Events']);
    }
    if (cat == 'Dresses' || cat == 'Footwear') {
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
        .map(
          (w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _ScoredItem {
  final WardrobeItem item;
  final double score;
  _ScoredItem(this.item, this.score);
}

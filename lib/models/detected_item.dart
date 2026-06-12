// ============================================================
// detected_item.dart
// Data model for AI-detected clothing items
// ============================================================

import 'package:myapp/app_localizations.dart';

class DetectedItem {
  final String id;
  final String name;
  final String color;
  final String style;
  final List<String> occasions;
  final List<String> pairsWith;
  final int pairingCount;
  final int matchCount;
  final int occasionCount;
  final String imageUrl;
  bool isSelected;

  DetectedItem({
    required this.id,
    required this.name,
    required this.color,
    required this.style,
    required this.occasions,
    required this.pairsWith,
    required this.pairingCount,
    required this.matchCount,
    required this.occasionCount,
    required this.imageUrl,
    this.isSelected = true,
  });

  // ============================================================
  // Factory Constructor: Parse from JSON (Backend Response)
  // ============================================================
  factory DetectedItem.fromJson(Map<String, dynamic> json) {
    return DetectedItem(
      id: json['id'] ?? _generateId(),
      name: json['name'] ?? 'Unknown Item',
      color: json['color'] ?? 'Unknown',
      style: json['style'] ?? 'Casual',
      occasions: _parseList(json['occasions']),
      pairsWith: _parseList(json['pairsWith']),
      pairingCount: json['pairingCount'] ?? 0,
      matchCount: json['matchCount'] ?? 0,
      occasionCount: json['occasionCount'] ?? 0,
      imageUrl: json['imageUrl'] ?? '',
      isSelected: json['isSelected'] ?? true,
    );
  }

  // ============================================================
  // Convert to JSON (for storage/API)
  // ============================================================
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'style': style,
      'occasions': occasions,
      'pairsWith': pairsWith,
      'pairingCount': pairingCount,
      'matchCount': matchCount,
      'occasionCount': occasionCount,
      'imageUrl': imageUrl,
      'isSelected': isSelected,
    };
  }

  // ============================================================
  // Convert to WardrobeItem (for storage in app)
  // ============================================================
  WardrobeItem toWardrobeItem() {
    return WardrobeItem(
      id: id,
      name: name,
      cat: _categoryFromStyle(style),
      occasions: occasions,
      notes: '',
      worn: 0,
      liked: false,
      imageUrl: imageUrl,
    );
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  /// Parse list safely from JSON
  static List<String> _parseList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return [];
  }

  /// Generate unique ID if not provided
  static String _generateId() {
    return 'item_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Map style to wardrobe category
  String _categoryFromStyle(String style) {
    if (style.isEmpty) return 'Tops';

    final lower = style.toLowerCase();

    // Outerwear
    if (lower.contains('outerwear') ||
        lower.contains('blazer') ||
        lower.contains('jacket') ||
        lower.contains('coat') ||
        lower.contains('cardigan') ||
        lower.contains('sweater') ||
        lower.contains('hoodie')) {
      return 'Outerwear';
    }

    // Dresses
    if (lower.contains('dress') || lower.contains('gown')) {
      return 'Dresses';
    }

    // Bottoms
    if (lower.contains('pant') ||
        lower.contains('trouser') ||
        lower.contains('short') ||
        lower.contains('skirt') ||
        lower.contains('jeans')) {
      return 'Bottoms';
    }

    // Footwear
    if (lower.contains('shoe') ||
        lower.contains('boot') ||
        lower.contains('sandal') ||
        lower.contains('loafer') ||
        lower.contains('sneaker')) {
      return 'Footwear';
    }

    // Accessories
    if (lower.contains('accessory') ||
        lower.contains('belt') ||
        lower.contains('scarf') ||
        lower.contains('tie')) {
      return 'Accessories';
    }

    // Bags
    if (lower.contains('bag') ||
        lower.contains('purse') ||
        lower.contains('backpack')) {
      return 'Bags';
    }

    // Jewelry
    if (lower.contains('jewelry') ||
        lower.contains('jewellery') ||
        lower.contains('necklace') ||
        lower.contains('bracelet') ||
        lower.contains('ring') ||
        lower.contains('earring')) {
      return 'Jewelry';
    }

    // Makeup
    if (lower.contains('makeup') || lower.contains('cosmetic')) {
      return 'Makeup';
    }

    // Skincare
    if (lower.contains('skincare') || lower.contains('skin care')) {
      return 'Skincare';
    }

    // Default to Tops
    return 'Tops';
  }

  /// Get display category name
  String get categoryDisplay {
    return _categoryFromStyle(style);
  }

  /// Check if item has all required fields
  bool get isValid {
    return id.isNotEmpty &&
        name.isNotEmpty &&
        imageUrl.isNotEmpty &&
        occasions.isNotEmpty;
  }

  /// Copy with modifications
  DetectedItem copyWith({
    String? id,
    String? name,
    String? color,
    String? style,
    List<String>? occasions,
    List<String>? pairsWith,
    int? pairingCount,
    int? matchCount,
    int? occasionCount,
    String? imageUrl,
    bool? isSelected,
  }) {
    return DetectedItem(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      style: style ?? this.style,
      occasions: occasions ?? this.occasions,
      pairsWith: pairsWith ?? this.pairsWith,
      pairingCount: pairingCount ?? this.pairingCount,
      matchCount: matchCount ?? this.matchCount,
      occasionCount: occasionCount ?? this.occasionCount,
      imageUrl: imageUrl ?? this.imageUrl,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  String toString() => 'DetectedItem(id: $id, name: $name, color: $color)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectedItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ============================================================
// WARDROBE ITEM CLASS (Reference - from your existing code)
// ============================================================
// This is what you'll convert DetectedItem into for storage

class WardrobeItem {
  final String id;
  String name;
  String cat;
  List<String> occasions;
  String notes;
  int worn;
  bool liked;

  // Dual URLs to match your Database
  String? imageUrl; // Raw image URL
  String? maskedUrl; // Processed PNG URL

  WardrobeItem({
    required this.id,
    required this.name,
    required this.cat,
    required this.occasions,
    this.notes = '',
    this.worn = 0,
    this.liked = false,
    this.imageUrl,
    this.maskedUrl,
  });

  // Helper to always show the processed image first, falling back to raw
  String? get displayUrl => maskedUrl ?? imageUrl;
}

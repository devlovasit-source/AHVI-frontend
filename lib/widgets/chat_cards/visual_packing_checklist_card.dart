import 'package:flutter/material.dart';
import 'package:myapp/theme/theme_tokens.dart';

/// Canonical payload adapter for the backend's rich packing checklist card.
/// The backend has shipped both snake_case and camelCase aliases over time.
class VisualPackingChecklistPayload {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> sections;
  final List<dynamic> actions;

  const VisualPackingChecklistPayload({
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.actions,
  });

  factory VisualPackingChecklistPayload.fromJson(Map<String, dynamic> card) {
    final rawSections = card['visual_sections'] ?? card['visualSections'];
    final sections = rawSections is List
        ? rawSections
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['items'] is List)
        .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final rawActions = card['actions'];
    return VisualPackingChecklistPayload(
      title: (card['title'] ?? 'Carry-on Packing Checklist').toString().trim(),
      subtitle: (card['subtitle'] ?? 'Short trip').toString().trim(),
      sections: sections,
      actions: rawActions is List && rawActions.isNotEmpty
          ? List<dynamic>.from(rawActions)
          : const [
        {'label': 'Open checklist'},
        {'label': 'Plan outfits'},
        {'label': 'Weather prep'},
      ],
    );
  }

  bool get isEmpty => sections.isEmpty;
}

/// Shared renderer for the rich packing response used by both chat surfaces.
class VisualPackingChecklistCard extends StatefulWidget {
  final Map<String, dynamic> card;
  final ValueChanged<String>? onAction;

  const VisualPackingChecklistCard({
    super.key,
    required this.card,
    this.onAction,
  });

  @override
  State<VisualPackingChecklistCard> createState() =>
      _VisualPackingChecklistCardState();
}

class _VisualPackingChecklistCardState
    extends State<VisualPackingChecklistCard> {
  final Map<String, bool> _checks = {};

  VisualPackingChecklistPayload get _payload =>
      VisualPackingChecklistPayload.fromJson(widget.card);

  List<Map<String, dynamic>> _items(Map<String, dynamic> section) {
    final raw = section['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  String _label(Map<String, dynamic> item) =>
      (item['display_label'] ?? item['label'] ?? item['name'] ?? 'Item')
          .toString()
          .trim();

  String _stateKey(Map<String, dynamic> item) =>
      (item['id'] ?? _label(item)).toString();

  bool _isDone(Map<String, dynamic> item) =>
      _checks[_stateKey(item)] ?? item['packed'] == true;

  (int, int) _progress() {
    var packed = 0;
    var total = 0;
    for (final section in _payload.sections) {
      for (final item in _items(section)) {
        total++;
        if (_isDone(item)) packed++;
      }
    }
    return (packed, total);
  }

  @override
  Widget build(BuildContext context) {
    if (_payload.isEmpty) return const SizedBox.shrink();
    final t = context.themeTokens;
    final progress = _progress();
    final ratio = progress.$2 == 0 ? 0.0 : progress.$1 / progress.$2;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 4, right: 20, bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _payload.title.isEmpty
                          ? 'Carry-on Packing Checklist'
                          : _payload.title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 20,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (_payload.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        _payload.subtitle,
                        style: TextStyle(
                          color: t.accent.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      '${progress.$1} of ${progress.$2} packed',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _progressBar(ratio, t),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _heroVisual(t),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 320 ? 1 : 2;
              const gap = 10.0;
              final width =
                  ((constraints.maxWidth - gap * (columns - 1)) / columns) -
                      0.5;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < _payload.sections.length; i++)
                    SizedBox(
                      width: width,
                      child: _sectionCard(_payload.sections[i], i + 1, t),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _actionRow(t),
        ],
      ),
    );
  }

  Widget _progressBar(double ratio, AppThemeTokens t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 6,
        color: t.accent.primary.withValues(alpha: 0.14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: ratio.clamp(0.0, 1.0),
            child: Container(color: t.accent.primary),
          ),
        ),
      ),
    );
  }

  Widget _heroVisual(AppThemeTokens t) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // soft backdrop
          Positioned(
            right: 2,
            top: 8,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accent.secondary.withValues(alpha: 0.14),
              ),
            ),
          ),
          // sun hat — brim + dome, tilted
          Positioned(
            left: 0,
            top: 10,
            child: Transform.rotate(
              angle: -0.32,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.accent.secondary.withValues(alpha: 0.9),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -7),
                    child: Container(
                      width: 38,
                      height: 7,
                      decoration: BoxDecoration(
                        color: t.accent.secondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // airplane trail
          Positioned(
            right: 2,
            top: 0,
            child: Icon(
              Icons.flight_rounded,
              size: 18,
              color: t.accent.primary.withValues(alpha: 0.85),
            ),
          ),
          // suitcase handle
          Positioned(
            right: 34,
            bottom: 62,
            child: Container(
              width: 22,
              height: 15,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: t.accent.primary.withValues(alpha: 0.85),
                  width: 2.2,
                ),
              ),
            ),
          ),
          // suitcase body
          Positioned(
            right: 14,
            bottom: 4,
            child: Container(
              width: 56,
              height: 62,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: t.accent.primary.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: t.accent.primary,
                  width: 1.4,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.panel.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Container(
                    width: 36,
                    height: 1.4,
                    color: t.panel.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
          ),
          // passport badge
          Positioned(
            left: 8,
            bottom: 0,
            child: Container(
              width: 20,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent.primary,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: t.panel, width: 1.6),
              ),
              child: Icon(Icons.menu_book_rounded, size: 11, color: t.panel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
      Map<String, dynamic> section,
      int number,
      AppThemeTokens t,
      ) {
    final title = (section['title'] ?? section['label'] ?? 'Section')
        .toString()
        .trim();
    final items = _items(section);
    final id = (section['id'] ?? title).toString().toLowerCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  packingSectionIconForKey(id),
                  size: 15,
                  color: t.accent.primary,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$number. ${title.isEmpty ? 'Section' : title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${items.length} items',
                style: TextStyle(
                  color: t.accent.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (items.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 6.0;
                const columns =
                4; // fixed so tiles are the same size in every grid
                final tileWidth =
                ((constraints.maxWidth - gap * (columns - 1)) / columns)
                    .clamp(0.0, 110.0);
                final row = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: tileWidth,
                        child: _itemTile(items[i], t),
                      ),
                    ],
                  ],
                );
                if (items.length <= columns) return row;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: row,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> item, AppThemeTokens t) {
    final label = _label(item);
    final done = _isDone(item);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PackingThumb(item: item, fill: true),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 26,
          child: Text(
            label.isEmpty ? 'Item' : label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 9.8,
              height: 1.12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() {
            _checks[_stateKey(item)] = !done;
          }),
          child: Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: done
                ? t.accent.primary
                : t.mutedText.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _actionRow(AppThemeTokens t) {
    final chips = <Widget>[];
    for (final raw in _payload.actions.take(3)) {
      final action = raw is Map
          ? Map<String, dynamic>.from(raw)
          : {'label': raw.toString()};
      final label = (action['label'] ?? action['title'] ?? '')
          .toString()
          .trim();
      if (label.isEmpty) continue;
      chips.add(
        Expanded(
          child: GestureDetector(
            onTap: widget.onAction == null
                ? null
                : () => widget.onAction!(label),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: t.accent.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: t.accent.primary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    packingActionIconForLabel(label),
                    size: 15,
                    color: t.accent.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.accent.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: t.accent.primary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    final row = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 8));
      row.add(chips[i]);
    }
    return Row(children: row);
  }
}

/// The old renderer's image precedence is intentionally centralized here.
String packingImageUrlForItem(Map<String, dynamic> item) {
  final plural = item['image_urls'] ?? item['imageUrls'];
  if (plural is List) {
    for (final value in plural) {
      final url = value.toString().trim();
      if (url.isNotEmpty && url != 'null') return url;
    }
  }
  return (item['image_url'] ?? item['imageUrl'] ?? '').toString().trim();
}

String packingAssetKeyForItem(Map<String, dynamic> item) =>
    (item['asset_key'] ?? item['assetKey'] ?? item['assetIcon'] ?? '')
        .toString()
        .trim();

IconData? packingIconForKey(String key) {
  switch (key.toLowerCase()) {
    case 'sunscreen':
      return Icons.wb_sunny_outlined;
    case 'sunglasses':
      return Icons.remove_red_eye_outlined;
    case 'charger':
    case 'tech':
      return Icons.power_outlined;
    case 'power_bank':
      return Icons.battery_charging_full_outlined;
    case 'toiletries':
    case 'essentials':
      return Icons.inventory_2_outlined;
    case 'water_bottle':
      return Icons.local_drink_outlined;
    case 'shoes':
    case 'clothes':
    case 'jacket':
      return Icons.checkroom_outlined;
    case 'towel':
      return Icons.dry_cleaning_outlined;
    case 'medicine':
      return Icons.medical_services_outlined;
    case 'first_aid':
      return Icons.health_and_safety_outlined;
    case 'documents':
    case 'document':
      return Icons.description_outlined;
    case 'passport':
      return Icons.badge_outlined;
    case 'tickets':
      return Icons.confirmation_number_outlined;
    case 'wallet':
      return Icons.account_balance_wallet_outlined;
    case 'earphones':
      return Icons.headphones_outlined;
    case 'lip_balm':
      return Icons.face_outlined;
    case 'wet_wipes':
      return Icons.cleaning_services_outlined;
    case 'moisturizer':
      return Icons.spa_outlined;
    case 'sanitizer':
      return Icons.sanitizer_outlined;
    case 'face_mask':
      return Icons.masks_outlined;
    case 'umbrella':
      return Icons.umbrella_outlined;
    case 'travel_pillow':
      return Icons.airline_seat_recline_normal_outlined;
    case 'health':
      return Icons.health_and_safety_outlined;
    case 'camera':
      return Icons.camera_alt_outlined;
    case 'weather':
      return Icons.cloud_outlined;
    case 'bag':
      return Icons.shopping_bag_outlined;
  }
  return null;
}

IconData packingSectionIconForKey(String key) {
  final text = key.toLowerCase();
  final icon = packingIconForKey(text);
  if (icon != null) return icon;
  if (text.contains('cloth') || text.contains('top') || text.contains('wear')) {
    return Icons.checkroom_rounded;
  }
  if (text.contains('tech') ||
      text.contains('charger') ||
      text.contains('phone')) {
    return Icons.power_rounded;
  }
  if (text.contains('document') ||
      text.contains('passport') ||
      text.contains('ticket')) {
    return Icons.description_rounded;
  }
  if (text.contains('weather') ||
      text.contains('rain') ||
      text.contains('sun')) {
    return Icons.wb_sunny_outlined;
  }
  if (text.contains('essential') ||
      text.contains('toiletr') ||
      text.contains('medicine')) {
    return Icons.spa_rounded;
  }
  return Icons.inventory_2_rounded;
}

IconData packingActionIconForLabel(String label) {
  final text = label.toLowerCase();
  if (text.contains('outfit') || text.contains('plan')) {
    return Icons.checkroom_rounded;
  }
  if (text.contains('weather')) return Icons.cloud_outlined;
  return Icons.assignment_turned_in_outlined;
}

/// Public thumbnail used by the checklist card and renderer tests.
class PackingThumb extends StatelessWidget {
  final Map<String, dynamic> item;
  final double size;
  final bool round;
  final bool fill;

  const PackingThumb({
    super.key,
    required this.item,
    this.size = 40,
    this.round = false,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    final imageUrl = packingImageUrlForItem(item);
    final assetKey = packingAssetKeyForItem(item);
    final label = (item['label'] ?? item['display_label'] ?? '').toString();
    final iconKey = (item['iconKey'] ?? item['icon_key'] ?? '')
        .toString()
        .trim();
    final icon =
        packingIconForKey(iconKey) ??
            packingSectionIconForKey(
              (item['section'] ?? item['category'] ?? label)
                  .toString()
                  .toLowerCase(),
            );
    final iconSize = fill ? 22.0 : size * 0.46;
    Widget child;
    if (imageUrl.isNotEmpty) {
      child = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(icon, size: iconSize, color: t.accent.primary),
      );
    } else if (assetKey.startsWith('assets/')) {
      child = Image.asset(
        assetKey,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(icon, size: iconSize, color: t.accent.primary),
      );
    } else {
      child = Icon(icon, size: iconSize, color: t.accent.primary);
    }
    return Container(
      width: fill ? double.infinity : size,
      height: fill ? double.infinity : size,
      decoration: BoxDecoration(
        color: t.accent.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(round ? 999 : 12),
        border: round ? null : Border.all(color: t.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(padding: const EdgeInsets.all(5), child: child),
    );
  }
}
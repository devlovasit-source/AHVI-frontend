import 'package:flutter/material.dart';

/// Shared model + renderer for the AHVI backend's `module_card` response.
/// Used by main chat, calendar plan-chat, and diet chat so the
/// real-data summary cards (medicines, bills, meals, workout, skincare,
/// events) render the same way everywhere.

class AhviModuleCardRow {
  final bool done;
  final String main;
  final String sub;
  final String tag;
  const AhviModuleCardRow({
    required this.done,
    required this.main,
    required this.sub,
    required this.tag,
  });

  Map<String, dynamic> toJson() => {
    'done': done,
    'main': main,
    'sub': sub,
    'tag': tag,
  };

  factory AhviModuleCardRow.fromJson(Map<String, dynamic> j) =>
      AhviModuleCardRow(
        done: j['done'] == true,
        main: (j['main'] ?? '').toString(),
        sub: (j['sub'] ?? '').toString(),
        tag: (j['tag'] ?? '').toString(),
      );
}

class AhviModuleCard {
  final String module;
  final String title;
  final String icon;
  final String summary;
  final int countDone;
  final int countTotal;
  final List<AhviModuleCardRow> rows;
  final String openKey;

  const AhviModuleCard({
    required this.module,
    required this.title,
    required this.icon,
    required this.summary,
    required this.countDone,
    required this.countTotal,
    required this.rows,
    required this.openKey,
  });

  static bool isModuleCard(Map? response) {
    if (response == null) return false;
    return (response['response_type'] ?? '').toString() == 'module_card';
  }

  static AhviModuleCard? fromResponse(Map<String, dynamic> response) {
    if (!isModuleCard(response)) return null;
    final raw = response['card'];
    if (raw is! Map) return null;
    final rowsRaw = raw['rows'];
    final rows = <AhviModuleCardRow>[];
    if (rowsRaw is List) {
      for (final r in rowsRaw) {
        if (r is! Map) continue;
        rows.add(
          AhviModuleCardRow(
            done: r['done'] == true,
            main: (r['main'] ?? '').toString(),
            sub: (r['sub'] ?? '').toString(),
            tag: (r['tag'] ?? '').toString(),
          ),
        );
      }
    }
    int _toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return AhviModuleCard(
      module: (response['module'] ?? raw['module'] ?? '').toString(),
      title: (raw['title'] ?? 'Summary').toString(),
      icon: (raw['icon'] ?? '').toString(),
      summary: (raw['summary'] ?? response['message_text'] ?? '').toString(),
      countDone: _toInt(raw['count_done']),
      countTotal: _toInt(raw['count_total']),
      rows: rows,
      openKey: (raw['open_key'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'module': module,
    'title': title,
    'icon': icon,
    'summary': summary,
    'count_done': countDone,
    'count_total': countTotal,
    'rows': rows.map((r) => r.toJson()).toList(),
    'open_key': openKey,
  };

  /// For restoring from local storage (flat shape, distinct from the
  /// backend's [fromResponse] envelope shape).
  factory AhviModuleCard.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final rowsRaw = j['rows'];
    return AhviModuleCard(
      module: (j['module'] ?? '').toString(),
      title: (j['title'] ?? 'Summary').toString(),
      icon: (j['icon'] ?? '').toString(),
      summary: (j['summary'] ?? '').toString(),
      countDone: toInt(j['count_done']),
      countTotal: toInt(j['count_total']),
      rows: rowsRaw is List
          ? rowsRaw
          .map((r) => AhviModuleCardRow.fromJson(
        Map<String, dynamic>.from(r as Map),
      ))
          .toList()
          : const [],
      openKey: (j['open_key'] ?? '').toString(),
    );
  }

  IconData get iconData {
    switch (icon) {
      case 'medication':
        return Icons.medication_rounded;
      case 'restaurant':
        return Icons.restaurant_menu_rounded;
      case 'receipt':
        return Icons.receipt_long_rounded;
      case 'fitness':
        return Icons.fitness_center_rounded;
      case 'event':
        return Icons.event_note_rounded;
      case 'spa':
        return Icons.spa_rounded;
      default:
        return Icons.dashboard_rounded;
    }
  }
}

class AhviModuleCardView extends StatelessWidget {
  final AhviModuleCard card;
  final VoidCallback? onOpen;

  /// Palette overrides so each page can match its own theme.
  final Color? surfaceColor;
  final Color? textColor;
  final Color? mutedColor;
  final Color? accentColor;
  final Color? borderColor;

  const AhviModuleCardView({
    super.key,
    required this.card,
    this.onOpen,
    this.surfaceColor,
    this.textColor,
    this.mutedColor,
    this.accentColor,
    this.borderColor,
  });

  Color _surface(BuildContext c) =>
      surfaceColor ?? Theme.of(c).colorScheme.surfaceContainerHighest;
  Color _text(BuildContext c) =>
      textColor ?? Theme.of(c).colorScheme.onSurface;
  Color _muted(BuildContext c) =>
      mutedColor ?? Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.62);
  Color _accent(BuildContext c) =>
      accentColor ?? Theme.of(c).colorScheme.primary;
  Color _border(BuildContext c) =>
      borderColor ?? Theme.of(c).colorScheme.outline.withValues(alpha: 0.35);

  @override
  Widget build(BuildContext context) {
    final hasOpen = card.openKey.isNotEmpty && onOpen != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + title + count badge.
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _accent(context).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(card.iconData, size: 16, color: _accent(context)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  card.title,
                  style: TextStyle(
                    color: _text(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (card.countTotal > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _accent(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _accent(context).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${card.countDone}/${card.countTotal}',
                    style: TextStyle(
                      color: _accent(context),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (card.rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...card.rows.map((row) => _row(context, row)),
          ],
          if (hasOpen) ...[
            const SizedBox(height: 6),
            Divider(color: _border(context), height: 1),
            const SizedBox(height: 2),
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    'Open ${card.title}',
                    style: TextStyle(
                      color: _accent(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AhviModuleCardRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: row.done
              ? _accent(context).withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border(context)),
        ),
        child: Row(
          children: [
            Icon(
              row.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: row.done
                  ? _accent(context)
                  : _muted(context).withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.main,
                    style: TextStyle(
                      color: _text(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (row.sub.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      row.sub,
                      style: TextStyle(color: _muted(context), fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            if (row.tag.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _accent(context).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  row.tag,
                  style: TextStyle(
                    color: _accent(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

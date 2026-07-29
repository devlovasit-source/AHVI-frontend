import 'package:myapp/app_routes.dart';

enum CalendarQuickAction {
  viewEvents(id: 'calendar_view_events', label: 'View events', planType: ''),
  planDay(id: 'calendar_plan_day', label: 'Plan my day', planType: 'day_plan'),
  prepTomorrow(
    id: 'calendar_prep_tomorrow',
    label: 'Prep for tomorrow',
    planType: 'tomorrow_prep',
  );

  const CalendarQuickAction({
    required this.id,
    required this.label,
    required this.planType,
  });

  final String id;
  final String label;
  final String planType;
}

CalendarQuickAction? calendarQuickActionFor({
  required String value,
  required String label,
}) {
  final canonicalValue = value.trim().toLowerCase();
  for (final action in CalendarQuickAction.values) {
    if (canonicalValue == action.id) return action;
  }

  final displayBoundary = label.trim().isNotEmpty ? label : value;
  switch (displayBoundary.trim().toLowerCase()) {
    case 'view events':
      return CalendarQuickAction.viewEvents;
    case 'plan my day':
      return CalendarQuickAction.planDay;
    case 'prep for tomorrow':
      return CalendarQuickAction.prepTomorrow;
  }
  return null;
}

class CalendarActionRequest {
  const CalendarActionRequest({required this.message, required this.context});

  final String message;
  final Map<String, dynamic> context;
}

CalendarActionRequest calendarActionRequest(
  CalendarQuickAction action, {
  required String occasion,
}) {
  assert(action != CalendarQuickAction.viewEvents);
  return CalendarActionRequest(
    message: action.label,
    context: <String, dynamic>{
      'calendar_action': action.id,
      'requested_plan_type': action.planType,
      if (occasion.trim().isNotEmpty) 'occasion': occasion.trim(),
    },
  );
}

class CalendarActionCoordinator {
  bool _calendarNavigationPending = false;

  Future<void> dispatch(
    CalendarQuickAction action, {
    required Future<void> Function(String route) navigate,
    required Future<void> Function(CalendarQuickAction action) requestPlan,
  }) async {
    if (action == CalendarQuickAction.viewEvents) {
      if (_calendarNavigationPending) return;
      _calendarNavigationPending = true;
      await navigate(AppRoutes.calendar);
      return;
    }
    await requestPlan(action);
  }
}

String? normalizeCalendarRoute(Object? raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  if (value.isEmpty) return null;
  final path =
      Uri.tryParse(value)?.path.replaceAll(RegExp(r'/+$'), '') ?? value;
  if (path == 'calendar' ||
      path == AppRoutes.calendar ||
      path == 'organize/calendar' ||
      path == '/organize/calendar') {
    return AppRoutes.calendar;
  }
  return null;
}

String? calendarOpenModuleRoute(Map<String, dynamic> response) {
  String? routeFrom(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is Map) {
      for (final key in const [
        'route',
        'module',
        'value',
        'target',
        'path',
        'open_module',
      ]) {
        final value = raw[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  for (final map in <Map<String, dynamic>>[
    response,
    if (response['data'] is Map)
      Map<String, dynamic>.from(response['data'] as Map),
    if (response['card'] is Map)
      Map<String, dynamic>.from(response['card'] as Map),
  ]) {
    final openModule = routeFrom(map['open_module']);
    if (openModule != null) return openModule;
    final cta = routeFrom(map['cta']);
    if (cta != null) return cta;
  }
  return null;
}

class CalendarPlanSection {
  const CalendarPlanSection({required this.title, required this.items});

  final String title;
  final List<String> items;
}

class CalendarPlanPack {
  const CalendarPlanPack({
    required this.title,
    required this.planType,
    required this.sections,
  });

  final String title;
  final String planType;
  final List<CalendarPlanSection> sections;

  static CalendarPlanPack? tryParse(
    Map<String, dynamic> response, {
    required CalendarQuickAction? requestedAction,
  }) {
    final data = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : <String, dynamic>{};
    final meta = response['meta'] is Map
        ? Map<String, dynamic>.from(response['meta'] as Map)
        : <String, dynamic>{};
    final intent =
        (response['intent'] ?? data['intent'] ?? meta['intent'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final type = (response['response_type'] ?? response['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (intent != 'plan_pack' && type != 'plan_pack') return null;

    final action = requestedAction == CalendarQuickAction.prepTomorrow
        ? CalendarQuickAction.prepTomorrow
        : CalendarQuickAction.planDay;
    final sectionSource = _firstSectionList(response, data);
    final sections = sectionSource
        .whereType<Map>()
        .map((raw) {
          final section = Map<String, dynamic>.from(raw);
          final itemsRaw =
              section['items'] ??
              section['steps'] ??
              section['tasks'] ??
              section['checklist'];
          final items = itemsRaw is List
              ? itemsRaw
                    .map(_planItemText)
                    .where((item) => item.isNotEmpty)
                    .toList(growable: false)
              : const <String>[];
          return CalendarPlanSection(
            title: (section['title'] ?? section['name'] ?? 'Plan')
                .toString()
                .trim(),
            items: items,
          );
        })
        .toList(growable: false);

    return CalendarPlanPack(
      title: action == CalendarQuickAction.prepTomorrow
          ? 'Tomorrow Prep Plan'
          : 'Day Plan',
      planType: action.planType,
      sections: sections,
    );
  }
}

String _planItemText(Object? raw) {
  if (raw is Map) {
    return (raw['display_label'] ??
            raw['label'] ??
            raw['name'] ??
            raw['title'] ??
            raw['main'] ??
            '')
        .toString()
        .trim();
  }
  return raw?.toString().trim() ?? '';
}

List<dynamic> _firstSectionList(
  Map<String, dynamic> response,
  Map<String, dynamic> data,
) {
  for (final containerKey in const ['prep', 'plan', 'checklist']) {
    final container = data[containerKey];
    if (container is Map && container['sections'] is List) {
      return container['sections'] as List;
    }
  }
  for (final key in const ['prep_sections', 'plan_sections', 'sections']) {
    if (data[key] is List) return data[key] as List;
  }
  for (final map in [response, data]) {
    final visual = map['visual_sections'] ?? map['visualSections'];
    if (visual is List) return visual;
  }
  final card = response['card'];
  if (card is Map) {
    final visual = card['visual_sections'] ?? card['visualSections'];
    if (visual is List) return visual;
  }
  return const [];
}

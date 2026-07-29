import 'package:flutter/foundation.dart';
import 'package:myapp/util/safe_text.dart';

Map<String, dynamic>? calendarJsonMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(sanitizeUtf16Deep(value) as Map);
}

class CalendarEventRecord {
  const CalendarEventRecord({
    required this.id,
    required this.title,
    required this.startTime,
    required this.type,
    required this.description,
    required this.metadata,
    required this.reminderMinutes,
  });

  final String id;
  final String title;
  final DateTime startTime;
  final String type;
  final String description;
  final Map<String, dynamic> metadata;
  final int reminderMinutes;

  static CalendarEventRecord? tryParse(
    Object? raw, {
    void Function(String eventId, String field)? onSkipped,
  }) {
    final event = calendarJsonMap(raw);
    if (event == null) {
      onSkipped?.call('unknown', 'event');
      return null;
    }

    final id = _firstText(event, const ['id', r'$id', 'event_id']);
    if (id.isEmpty) {
      onSkipped?.call('unknown', 'id');
      return null;
    }

    final startRaw = _firstText(event, const [
      'start_time',
      'startTime',
      'starts_at',
    ]);
    final startTime = DateTime.tryParse(startRaw)?.toLocal();
    if (startTime == null) {
      onSkipped?.call(id, 'start_time');
      return null;
    }

    final reminderValue = event['reminder_minutes'];
    final reminderMinutes = reminderValue is num
        ? reminderValue.toInt()
        : int.tryParse(reminderValue?.toString() ?? '') ?? 0;
    final metadata = calendarJsonMap(event['metadata']) ?? <String, dynamic>{};

    return CalendarEventRecord(
      id: id,
      title: _firstText(event, const ['title', 'summary'], fallback: 'Plan'),
      startTime: startTime,
      type: _firstText(event, const ['type', 'event_type']),
      description: _firstText(event, const ['description']),
      metadata: metadata,
      reminderMinutes: reminderMinutes,
    );
  }
}

enum CalendarListSurface {
  homeToday('home_today'),
  calendar('calendar');

  const CalendarListSurface(this.wireName);

  final String wireName;
}

String calendarListStartDiagnostic({
  required CalendarListSurface surface,
  DateTime? from,
  DateTime? to,
}) =>
    'AHVI_CALENDAR_LIST_START surface=${surface.wireName} '
    'from=${from?.toIso8601String() ?? 'none'} '
    'to=${to?.toIso8601String() ?? 'none'}';

String calendarListOkDiagnostic({
  required CalendarListSurface surface,
  required CalendarEventBatch batch,
}) =>
    'AHVI_CALENDAR_LIST_OK surface=${surface.wireName} '
    'raw_count=${batch.rawCount} parsed_count=${batch.parsedCount} '
    'skipped_count=${batch.skippedCount}';

class CalendarEventBatch {
  const CalendarEventBatch({
    required this.events,
    required this.rawCount,
    required this.skippedCount,
  });

  final List<Map<String, dynamic>> events;
  final int rawCount;
  final int skippedCount;

  int get parsedCount => events.length;

  static CalendarEventBatch parse(
    Object? raw, {
    void Function(String eventId, String field)? onSkipped,
  }) {
    if (raw is! List) {
      return const CalendarEventBatch(
        events: <Map<String, dynamic>>[],
        rawCount: 0,
        skippedCount: 0,
      );
    }
    final events = <Map<String, dynamic>>[];
    var skippedCount = 0;
    for (final value in raw) {
      final event = calendarJsonMap(value);
      final record = CalendarEventRecord.tryParse(
        event,
        onSkipped: (eventId, field) {
          skippedCount++;
          onSkipped?.call(eventId, field);
        },
      );
      if (record != null && event != null) events.add(event);
    }
    return CalendarEventBatch(
      events: events,
      rawCount: raw.length,
      skippedCount: skippedCount,
    );
  }
}

class CalendarMutationResult {
  const CalendarMutationResult({
    required this.eventId,
    required this.startTime,
    required this.reused,
    this.reminderId = '',
    this.reminderScheduled = false,
  });

  final String eventId;
  final DateTime? startTime;
  final bool reused;
  final String reminderId;
  final bool reminderScheduled;

  bool get reminderConfirmed => reminderId.isNotEmpty || reminderScheduled;

  static CalendarMutationResult? tryParse(Object? raw) {
    final response = calendarJsonMap(raw);
    if (response == null) return null;
    final maps = <Map<String, dynamic>>[response];
    for (final key in const [
      'event',
      'calendar_event',
      'data',
      'result',
      'action_data',
      'payload',
    ]) {
      final nested = calendarJsonMap(response[key]);
      if (nested != null) {
        maps.add(nested);
        final event = calendarJsonMap(nested['event']);
        if (event != null) maps.add(event);
      }
    }

    final intent = maps
        .map((map) => _firstText(map, const ['intent', 'action']))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '')
        .toLowerCase();
    if (intent != 'calendar_event_created' &&
        intent != 'calendar_event_reused') {
      return null;
    }

    final eventId = maps
        .map((map) => _firstText(map, const ['event_id', 'id', r'$id']))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (eventId.isEmpty) return null;

    final startRaw = maps
        .map(
          (map) =>
              _firstText(map, const ['start_time', 'startTime', 'starts_at']),
        )
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final reminderMaps = <Map<String, dynamic>>[...maps];
    for (final map in maps) {
      final reminder = calendarJsonMap(map['reminder']);
      if (reminder != null) reminderMaps.add(reminder);
    }
    final reminderId = reminderMaps
        .map((map) => _firstText(map, const ['reminder_id', 'notification_id']))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final reminderScheduled = reminderMaps.any((map) {
      final explicit = map['reminder_scheduled'] ?? map['scheduled'];
      if (explicit is bool) return explicit;
      final value = explicit?.toString().toLowerCase() ?? '';
      return value == 'true' || value == 'scheduled' || value == 'success';
    });

    return CalendarMutationResult(
      eventId: eventId,
      startTime: DateTime.tryParse(startRaw)?.toLocal(),
      reused: intent == 'calendar_event_reused',
      reminderId: reminderId,
      reminderScheduled: reminderScheduled,
    );
  }
}

class CalendarRefreshSignal {
  CalendarRefreshSignal._();

  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  static void notify() {
    generation.value++;
    debugPrint('AHVI_CALENDAR_REFRESH');
  }
}

String _firstText(
  Map<String, dynamic> map,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value != 'null') return value;
  }
  return fallback;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/calendar_event_record.dart';

void main() {
  test('normalizes nested dynamic maps into a canonical calendar event', () {
    final record = CalendarEventRecord.tryParse(<dynamic, dynamic>{
      r'$id': 'event-1',
      'title': 'Office',
      'start_time': '2026-07-27T07:00:00+05:30',
      'type': 'meeting',
      'reminder_minutes': '15',
      'metadata': <dynamic, dynamic>{'outfit': 'Blue shirt'},
    });

    expect(record, isNotNull);
    expect(record!.id, 'event-1');
    expect(record.startTime.toUtc(), DateTime.utc(2026, 7, 27, 1, 30));
    expect(record.metadata, isA<Map<String, dynamic>>());
    expect(record.metadata['outfit'], 'Blue shirt');
    expect(record.reminderMinutes, 15);
  });

  test('isolates an event with an invalid canonical start time', () {
    String? skippedId;
    String? skippedField;

    final record = CalendarEventRecord.tryParse(
      {'id': 'bad-event', 'start_time': 'not-a-date'},
      onSkipped: (eventId, field) {
        skippedId = eventId;
        skippedField = field;
      },
    );

    expect(record, isNull);
    expect(skippedId, 'bad-event');
    expect(skippedField, 'start_time');
  });

  test('reads canonical created event and durable reminder outcome', () {
    final result = CalendarMutationResult.tryParse({
      'intent': 'calendar_event_created',
      'data': {
        'event': {
          'event_id': 'event-2',
          'start_time': '2026-07-27T07:00:00+05:30',
          'reminder': {'reminder_id': 'reminder-2'},
        },
      },
    });

    expect(result, isNotNull);
    expect(result!.eventId, 'event-2');
    expect(result.startTime, isNotNull);
    expect(result.reused, isFalse);
    expect(result.reminderConfirmed, isTrue);
    expect(result.reminderId, 'reminder-2');
  });

  test('reads reused event with explicit scheduled reminder outcome', () {
    final result = CalendarMutationResult.tryParse({
      'action': 'calendar_event_reused',
      'event_id': 'event-3',
      'startTime': '2026-07-27T08:00:00+05:30',
      'reminder_scheduled': true,
    });

    expect(result, isNotNull);
    expect(result!.reused, isTrue);
    expect(result.reminderConfirmed, isTrue);
  });

  test('does not treat an ordinary calendar response as a mutation', () {
    expect(
      CalendarMutationResult.tryParse({
        'module': 'calendar',
        'message': 'What time works?',
      }),
      isNull,
    );
  });

  test('does not infer reminder success from the event status', () {
    final result = CalendarMutationResult.tryParse({
      'intent': 'calendar_event_created',
      'event_id': 'event-4',
      'start_time': '2026-07-27T09:00:00+05:30',
      'status': 'scheduled',
    });

    expect(result, isNotNull);
    expect(result!.reminderConfirmed, isFalse);
  });
}

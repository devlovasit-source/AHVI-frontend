import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';

void main() {
  group('creation intent - must schedule/intercept', () {
    const creations = [
      'Remind me to take Dolo at 8 PM',
      'Can you remind me to take Dolo at 8 PM?',
      'Could you set a medicine reminder for Dolo at 9?',
      'Schedule a reminder to take Thyronorm at 7:15 AM',
      'Add a medicine reminder for Vitamin D at 8:30 PM',
      'Create a tablet reminder for Metformin at 9 PM',
    ];

    for (final text in creations) {
      test('"$text" is a creation request', () {
        expect(debugIsMedicineReminderCreateRequest(text), isTrue);
        expect(
          debugIsReminderQuestion(text),
          isFalse,
          reason: 'creation intent must take precedence over question form',
        );
      });
    }

    test('polite question-shaped command still extracts name and time', () {
      final intent = debugExtractMedicineReminderIntent(
        'Can you remind me to take Dolo at 8 PM?',
      );
      expect(intent, isNotNull);
      expect(intent!['name']!.toLowerCase(), contains('dolo'));
      expect(intent['time'], '8 PM');
    });

    test('minute-level times are preserved', () {
      final first = debugExtractMedicineReminderIntent(
        'Schedule a reminder to take Thyronorm at 7:15 AM',
      );
      expect(first, isNotNull);
      expect(first!['name']!.toLowerCase(), contains('thyronorm'));
      expect(first['time'], '7:15 AM');

      final second = debugExtractMedicineReminderIntent(
        'Add a medicine reminder for Vitamin D at 8:30 PM',
      );
      expect(second, isNotNull);
      expect(second!['time'], '8:30 PM');

      final evening = debugExtractMedicineReminderIntent(
        'Remind me to take Dolo at 8:15 PM',
      );
      expect(evening, isNotNull);
      expect(evening!['time'], '8:15 PM');
    });
  });

  group('reminder-information questions - must not create', () {
    const queries = [
      'When is my Dolo reminder?',
      'What reminders do I have?',
      'Show my medicine reminders',
      'Do I have a reminder for Dolo?',
      'What time is my medicine reminder?',
      'Check my reminders',
    ];

    for (final text in queries) {
      test('"$text" is a reminder question, never a creation', () {
        expect(debugIsMedicineReminderCreateRequest(text), isFalse);
        expect(debugIsReminderQuestion(text), isTrue);
        expect(
          debugExtractMedicineReminderIntent(text),
          isNull,
          reason: 'query must never produce a schedulable intent',
        );
      });
    }
  });

  group('unrelated questions - normal chat', () {
    const unrelated = [
      'What should I wear today?',
      'Can you suggest a healthy breakfast?',
      'Why should I take this medicine?',
    ];

    for (final text in unrelated) {
      test('"$text" is neither creation nor reminder question', () {
        expect(debugIsMedicineReminderCreateRequest(text), isFalse);
        expect(debugIsReminderQuestion(text), isFalse);
        expect(debugExtractMedicineReminderIntent(text), isNull);
        expect(debugIsAhviChatQuestion(text), isTrue);
      });
    }
  });
}

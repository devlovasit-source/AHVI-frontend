import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/medi_tracker.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

Map<String, dynamic> _medicine(String id, String name) => {
  'id': id,
  'name': name,
  'dose': '10 mg',
  'freq': 'Once daily',
  'time': '12:00 PM',
  'cat': 'Heart',
  'left': 5,
  'total': 5,
  'reminder': true,
  'taken': false,
};

void main() {
  test('valid emoji remains unchanged', () {
    final record = sanitizeMediRecord(
      {'name': 'Vitamin 👗'},
      recordId: 'med-1',
    );

    expect(record!['name'], 'Vitamin 👗');
  });

  test('lone high surrogate is replaced and diagnosed', () {
    final diagnostics = <String>[];
    final record = sanitizeMediRecord(
      {'name': 'A\uD800B'},
      recordId: 'med-high',
      diagnostic: diagnostics.add,
    );

    expect(record!['name'], 'A\uFFFDB');
    expect(
      diagnostics,
      contains('AHVI_MEDI_RECORD_SANITIZED record_id=med-high field=name'),
    );
  });

  test('lone low surrogate is replaced', () {
    final record = sanitizeMediRecord(
      {'name': 'A\uDC00B'},
      recordId: 'med-low',
    );

    expect(record!['name'], 'A\uFFFDB');
  });

  test('dosage category and notes are sanitized through aliases', () {
    final diagnostics = <String>[];
    final record = sanitizeMediRecord(
      {
        'dosage': '5\uD800 mg',
        'category': 'Heart\uDC00',
        'notes': 'After food \uD800',
      },
      recordId: 'med-fields',
      diagnostic: diagnostics.add,
    );

    expect(record!['dose'], '5\uFFFD mg');
    expect(record['cat'], 'Heart\uFFFD');
    expect(record['notes'], 'After food \uFFFD');
    expect(diagnostics.where((line) => line.contains('record_id=med-fields')), hasLength(3));
    expect(diagnostics.join(' '), isNot(contains('After food')));
  });

  test('nullable Appwrite fields receive typed defaults', () {
    final record = sanitizeMediRecord(
      {
        'name': null,
        'dose': null,
        'freq': null,
        'time': null,
        'cat': null,
        'notes': null,
        'left': null,
        'total': null,
        'reminder': null,
      },
      recordId: 'med-null',
    );

    expect(record, containsPair('name', 'Medicine'));
    expect(record, containsPair('dose', ''));
    expect(record, containsPair('freq', ''));
    expect(record, containsPair('time', '12:00 PM'));
    expect(record, containsPair('cat', 'Other'));
    expect(record, containsPair('notes', ''));
    expect(record, containsPair('left', 0));
    expect(record, containsPair('total', 0));
    expect(record, containsPair('reminder', true));
  });

  test('Map<dynamic, dynamic> keys are converted safely', () {
    final source = <dynamic, dynamic>{
      'name': 'Aspirin',
      'dose': '10 mg',
      42: 'ignored',
    };

    final record = sanitizeMediRecord(source, recordId: 'med-map');

    expect(record!['name'], 'Aspirin');
    expect(record['dose'], '10 mg');
  });

  testWidgets(
    'one malformed medicine does not prevent other medicines rendering',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppThemeTokens.light(_accent)]),
          home: MediTrackScreen(
            skipInitialFetch: true,
            initialMeds: [
              _medicine('bad', 'Malformed \uD800 medicine'),
              _medicine('good', 'Healthy medicine'),
            ],
            markTakenSync: (_, newLeft, takenAtIso) async {},
            deleteSync: (id) async {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Malformed \uFFFD medicine'), findsOneWidget);
      expect(find.text('Healthy medicine'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Medi screen opens without a painting exception', (tester) async {
    final fields = _medicine('paint', 'Name \uD800')
      ..['dose'] = 'Dose \uDC00'
      ..['cat'] = 'Category \uD800'
      ..['notes'] = 'Notes \uDC00';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppThemeTokens.light(_accent)]),
        home: MediTrackScreen(
          skipInitialFetch: true,
          initialMeds: [fields],
          markTakenSync: (_, newLeft, takenAtIso) async {},
          deleteSync: (id) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Name \uFFFD'), findsOneWidget);
    expect(find.text('Dose \uFFFD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

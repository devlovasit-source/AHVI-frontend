import 'dart:async';

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

Map<String, dynamic> _medicine() => {
  'id': 'med-1',
  'name': 'Aspirin',
  'dose': '10 mg',
  'freq': 'Once daily',
  'time': '12:00 PM',
  'cat': 'Heart',
  'left': 5,
  'total': 5,
  'reminder': true,
  'taken': false,
  'color': const Color(0xFFFF8EC7),
};

Future<void> _pump(
  WidgetTester tester, {
  required MediMarkTakenSync sync,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppThemeTokens.light(_accent)]),
      home: MediTrackScreen(
        skipInitialFetch: true,
        initialMeds: [_medicine()],
        markTakenSync: sync,
        deleteSync: (_) async {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Mark Taken remains optimistic while mounted', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      sync: (_, newLeft, __) async {
        calls++;
        expect(newLeft, 4);
      },
    );

    await tester.tap(find.text('Aspirin'));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Take'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mark Taken completion after navigation does not throw', (
    tester,
  ) async {
    final pending = Completer<void>();
    await _pump(tester, sync: (_, __, ___) => pending.future);

    await tester.tap(find.text('Aspirin'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    pending.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated Mark Taken taps sync only once', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await _pump(
      tester,
      sync: (_, __, ___) {
        calls++;
        return pending.future;
      },
    );

    await tester.tap(find.text('Aspirin'));
    await tester.tap(find.text('Aspirin'));
    await tester.pump();
    expect(calls, 1);

    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid taps create only one persisted Mark Taken log', (
    tester,
  ) async {
    final pending = Completer<void>();
    var logCreates = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppThemeTokens.light(_accent)]),
        home: MediTrackScreen(
          skipInitialFetch: true,
          initialMeds: [_medicine()],
          markTakenSync: (_, newLeft, takenAtIso) => pending.future,
          deleteSync: (id) async {},
          onMarkTakenLogCreated: () => logCreates++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Aspirin'));
    await tester.tap(find.text('Aspirin'));
    await tester.pump();
    expect(logCreates, 1);

    pending.complete();
    await tester.pump();
    expect(logCreates, 1);
  });
}

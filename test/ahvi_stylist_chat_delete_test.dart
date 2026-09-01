import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('swipe cancel preserves the selected conversation', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b')]);

    await _openHistory(tester);
    await tester.drag(find.text('Conversation A'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete conversation?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation A'), findsOneWidget);
    expect(find.text('Conversation B'), findsOneWidget);
    expect(await _storedIds(), ['a', 'b']);
  });

  testWidgets('inactive delete removes only the selected session', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b')]);

    await _deleteFromSwipe(tester, 'a');

    expect(find.text('Conversation A'), findsNothing);
    expect(find.text('Conversation B'), findsOneWidget);
    expect(await _storedIds(), ['b']);
  });

  testWidgets('active delete resets to a fresh session and survives reopen', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b')]);

    await _openHistory(tester);
    await tester.tap(find.text('Conversation B'));
    await tester.pump();
    await _deleteFromSwipe(tester, 'b');

    expect(find.text('Conversation B'), findsNothing);
    expect(find.byType(AhviChatPromptBar), findsOneWidget);
    expect(await _storedIds(), ['a']);

    await tester.pump(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _openChat(tester);
    await _openHistory(tester);

    expect(find.text('Conversation B'), findsNothing);
    expect(find.text('Conversation A'), findsOneWidget);
  });

  testWidgets('clear chat remains an all-history operation', (tester) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b')]);

    await tester.tap(find.byTooltip('Chat options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear chat'));
    await tester.pumpAndSettle();

    expect(await _storedIds(), isEmpty);
    await _openHistory(tester);
    expect(find.text('Conversation A'), findsNothing);
    expect(find.text('Conversation B'), findsNothing);
  });
}

Map<String, dynamic> _session(String id) {
  final label = id.toUpperCase();
  return {
    'id': id,
    'title': 'Conversation $label',
    'createdAt': '2026-08-01T0${id == 'a' ? '1' : '2'}:00:00.000Z',
    'messages': [
      {'text': 'Message $label', 'textKey': null, 'isUser': true},
    ],
  };
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required List<Map<String, dynamic>> sessions,
}) async {
  SharedPreferences.setMockInitialValues({
    'ahvi_chat_history_style': jsonEncode(sessions),
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: BaseTheme.light.copyWith(
        extensions: [AppThemeTokens.light(_accent)],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('open-chat'),
            onPressed: () =>
                showAhviStylistChatSheet(context, moduleContext: 'style'),
            child: const Text('Open chat'),
          ),
        ),
      ),
    ),
  );
  await _openChat(tester);
}

Future<void> _openChat(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-chat')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
}

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.history_rounded));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _deleteFromSwipe(WidgetTester tester, String id) async {
  await _openHistory(tester);
  await tester.drag(
    find.text('Conversation ${id.toUpperCase()}'),
    const Offset(-500, 0),
  );
  await tester.pumpAndSettle();
  expect(find.text('Delete conversation?'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

Future<List<String>> _storedIds() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('ahvi_chat_history_style');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((session) => (session as Map)['id'].toString())
      .toList();
}

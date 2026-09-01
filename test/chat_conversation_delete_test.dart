import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/chat.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  void Function(FlutterErrorDetails)? previousOnError;
  setUp(() {
    previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('RenderConstraintsTransformBox overflowed') ||
          message.contains('RenderFlex overflowed')) {
        return;
      }
      previousOnError?.call(details);
    };
  });
  tearDown(() => FlutterError.onError = previousOnError);

  testWidgets('deleting A leaves B and C out of local history', (tester) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b'), _session('c')]);

    await _deleteFromMenu(tester, 'a');

    expect(find.text('Conversation A'), findsNothing);
    expect(find.text('Conversation B'), findsOneWidget);
    expect(find.text('Conversation C'), findsOneWidget);
    expect(await _storedSessionIds(), containsAll(<String>['b', 'c']));
    expect((await _storedSessionIds()), hasLength(2));
  });

  testWidgets('deleted session is absent after a chat reload', (tester) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b')]);
    await _deleteFromMenu(tester, 'a');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _pumpChat(tester, sessions: null);
    await _openHistory(tester);

    expect(find.text('Conversation A'), findsNothing);
    expect(find.text('Conversation B'), findsOneWidget);
  });

  testWidgets('cancel confirmation leaves the conversation and persistence intact', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a')]);

    await _openDeleteMenu(tester, 'a');
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Delete conversation?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation A'), findsOneWidget);
    expect(await _storedSessionIds(), ['a']);
  });

  testWidgets('swipe delete requires confirmation and uses the same path', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a')]);

    await _openHistory(tester);
    await tester.drag(find.text('Conversation A'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete conversation?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation A'), findsOneWidget);
  });

  testWidgets('three-dot delete requires confirmation', (tester) async {
    await _pumpChat(tester, sessions: [_session('a')]);

    await _openDeleteMenu(tester, 'a');
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();

    expect(find.text('Delete conversation?'), findsOneWidget);
    expect(
      find.text('This conversation will be removed from your chat history.'),
      findsOneWidget,
    );
  });

  testWidgets('confirmed deletion sends the exact session id to cloud sync', (
    tester,
  ) async {
    final deletedIds = <String>[];
    await _pumpChat(
      tester,
      sessions: [_session('a'), _session('b')],
      onDeleteSessionCloud: (id) async => deletedIds.add(id),
    );

    await _deleteFromMenu(tester, 'b');

    expect(deletedIds, ['b']);
  });

  testWidgets('cloud failure keeps the local deletion authoritative', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      sessions: [_session('a')],
      onDeleteSessionCloud: (_) async => throw StateError('offline'),
    );

    await _deleteFromMenu(tester, 'a');

    expect(find.text('Conversation A'), findsNothing);
    expect(await _storedSessionIds(), isEmpty);
    expect(
      find.text('Conversation deleted locally. Cloud sync failed.'),
      findsOneWidget,
    );
  });

  testWidgets('deleting the active session starts a fresh empty conversation', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a')]);
    await _loadSession(tester, 'a');
    expect(find.text('Message A'), findsOneWidget);

    await _deleteFromMenu(tester, 'a');

    expect(find.text('Message A'), findsNothing);
    expect(find.text('chat_greeting'), findsOneWidget);
    expect(await _storedSessionIds(), isEmpty);
  });

  testWidgets('deleting an inactive session does not disturb the active chat', (
    tester,
  ) async {
    await _pumpChat(tester, sessions: [_session('a'), _session('b')]);
    await _loadSession(tester, 'a');

    await _deleteFromMenu(tester, 'b');

    expect(find.text('Message A'), findsOneWidget);
    expect(find.text('Conversation B'), findsNothing);
    expect(await _storedSessionIds(), ['a']);
  });

  test('conversation deletion does not add individual-message deletion behavior', () {
    final source = File('lib/chat.dart').readAsStringSync();
    expect(RegExp(r'\bDismissible\b').allMatches(source), hasLength(1));
    expect(source, contains('confirmDismiss: (_) => _requestDeleteSession(s.id)'));
    expect(source, isNot(contains('onMessageDismissed')));
    expect(source, isNot(contains('Delete message')));
  });
}

Map<String, dynamic> _session(String id) {
  final label = id.toUpperCase();
  return {
    'id': id,
    'title': 'Conversation $label',
    'createdAt': DateTime.utc(2026, 8, 1, int.parse(id == 'a' ? '1' : id == 'b' ? '2' : '3')).toIso8601String(),
    'history': [
      {'role': 'user', 'content': 'Message $label'},
    ],
    'messages': const [],
  };
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required List<Map<String, dynamic>>? sessions,
  Future<void> Function(String sessionId)? onDeleteSessionCloud,
}) async {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('RenderConstraintsTransformBox overflowed') ||
        message.contains('RenderFlex overflowed')) {
      return;
    }
    previousOnError?.call(details);
  };
  if (sessions != null) {
    SharedPreferences.setMockInitialValues({
      'ahvi_chat_sessions': jsonEncode(sessions),
    });
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: BaseTheme.light.copyWith(
        extensions: [AppThemeTokens.light(_accent)],
      ),
      home: ChatScreen(
        showBackButton: false,
        onDeleteSessionCloud: onDeleteSessionCloud ?? (_) async {},
        userNameLoader: () async => null,
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openHistory(WidgetTester tester) async {
  if (find.byIcon(Icons.history_rounded).evaluate().isNotEmpty) {
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
  }
}

Future<void> _openDeleteMenu(WidgetTester tester, String id) async {
  await _openHistory(tester);
  await tester.tap(find.byKey(ValueKey('session-actions-$id')));
  await tester.pumpAndSettle();
}

Future<void> _deleteFromMenu(WidgetTester tester, String id) async {
  await _openDeleteMenu(tester, id);
  await tester.tap(find.text('Delete conversation'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

Future<void> _loadSession(WidgetTester tester, String id) async {
  await _openHistory(tester);
  await tester.tap(find.text('Conversation ${id.toUpperCase()}'));
  await tester.pumpAndSettle();
}

Future<List<String>> _storedSessionIds() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('ahvi_chat_sessions');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .map((session) => (session as Map)['id'].toString())
      .toList();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'normalized style opens full-screen on root route and Back pops once',
    (tester) async {
      final rootObserver = _RecordingNavigatorObserver();
      final nestedObserver = _RecordingNavigatorObserver();
      final contextData = <String, dynamic>{'source': 'presentation-test'};
      Future<void> onRefresh() async {}

      BuildContext? launchContext;
      var completed = 0;
      await tester.pumpWidget(
        _testApp(
          rootObserver: rootObserver,
          nestedObserver: nestedObserver,
          launcher: Builder(
            builder: (context) {
              launchContext = context;
              return ElevatedButton(
                key: const ValueKey('open-chat'),
                onPressed: () {
                  showAhviStylistChatSheet(
                    context,
                    moduleContext: '  StYlE  ',
                    contextData: contextData,
                    onRefresh: onRefresh,
                    initialPrompt: '   ',
                  ).then((_) => completed++);
                },
                child: const Text('Open chat'),
              );
            },
          ),
        ),
      );

      final rootPushesBefore = rootObserver.pushed.length;
      final nestedPushesBefore = nestedObserver.pushed.length;
      await tester.tap(find.byKey(const ValueKey('open-chat')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(rootObserver.pushed.length, rootPushesBefore + 1);
      expect(rootObserver.pushed.last, isA<MaterialPageRoute<void>>());
      expect(nestedObserver.pushed.length, nestedPushesBefore);

      final dynamic chat = tester.widget(_chatFinder);
      expect(chat.moduleContext, 'style');
      expect(chat.contextData, same(contextData));
      expect(chat.rootContext, same(launchContext));
      expect(chat.onRefresh, same(onRefresh));
      expect(chat.initialPrompt, '   ');
      expect(chat.isFullScreen, isTrue);
      expect(
        find.byKey(const ValueKey('ahvi-chat-modal-drag-handle')),
        findsNothing,
      );

      final routeScaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(
        routeScaffold.backgroundColor,
        AppThemeTokens.light(_accent).backgroundPrimary,
      );
      expect(routeScaffold.resizeToAvoidBottomInset, isTrue);
      expect(
        find.ancestor(of: _chatFinder, matching: find.byType(SafeArea)),
        findsNothing,
      );
      expect(
        find.descendant(of: _chatFinder, matching: find.byType(SafeArea)),
        findsOneWidget,
      );

      final devicePixelRatio = tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(bottom: 240 * devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final logicalScreenHeight =
          tester.view.physicalSize.height / devicePixelRatio;
      expect(
        tester.getBottomRight(find.byType(TextField)).dy,
        lessThanOrEqualTo(logicalScreenHeight - 240),
      );
      tester.view.resetViewInsets();
      await tester.pump();

      final popsBefore = rootObserver.popCount;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(rootObserver.popCount, popsBefore + 1);
      expect(completed, 1);
      expect(_chatFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('non-style context retains modal presentation and parameters', (
    tester,
  ) async {
    final rootObserver = _RecordingNavigatorObserver();
    final nestedObserver = _RecordingNavigatorObserver();
    final contextData = <String, dynamic>{'medications': const []};
    Future<void> onRefresh() async {}

    BuildContext? launchContext;
    await tester.pumpWidget(
      _testApp(
        rootObserver: rootObserver,
        nestedObserver: nestedObserver,
        launcher: Builder(
          builder: (context) {
            launchContext = context;
            return ElevatedButton(
              key: const ValueKey('open-chat'),
              onPressed: () => showAhviStylistChatSheet(
                context,
                moduleContext: '  MeDi  ',
                contextData: contextData,
                onRefresh: onRefresh,
                initialPrompt: '   ',
              ),
              child: const Text('Open chat'),
            );
          },
        ),
      ),
    );

    final rootPushesBefore = rootObserver.pushed.length;
    final nestedPushesBefore = nestedObserver.pushed.length;
    await tester.tap(find.byKey(const ValueKey('open-chat')));
    await tester.pumpAndSettle();

    expect(rootObserver.pushed.length, rootPushesBefore);
    expect(nestedObserver.pushed.length, nestedPushesBefore + 1);
    expect(nestedObserver.pushed.last, isA<PopupRoute<void>>());

    final dynamic chat = tester.widget(_chatFinder);
    expect(chat.moduleContext, 'medi');
    expect(chat.contextData, same(contextData));
    expect(chat.rootContext, same(launchContext));
    expect(chat.onRefresh, same(onRefresh));
    expect(chat.initialPrompt, '   ');
    expect(chat.isFullScreen, isFalse);
    expect(
      find.byKey(const ValueKey('ahvi-chat-modal-drag-handle')),
      findsOneWidget,
    );

    final modalScaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(modalScaffold.backgroundColor, Colors.transparent);
    expect(modalScaffold.resizeToAvoidBottomInset, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prepare context uses Prep presentation instead of Style', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        rootObserver: _RecordingNavigatorObserver(),
        nestedObserver: _RecordingNavigatorObserver(),
        launcher: Builder(
          builder: (context) => ElevatedButton(
            key: const ValueKey('open-chat'),
            onPressed: () => showAhviStylistChatSheet(
              context,
              moduleContext: ' Prepare ',
            ),
            child: const Text('Open chat'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-chat')));
    await tester.pumpAndSettle();

    final dynamic chat = tester.widget(_chatFinder);
    expect(chat.moduleContext, 'prepare');
    expect(find.text('Plan outfits for an event'), findsOneWidget);
    expect(find.text('Wardrobe detox tips'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Finder get _chatFinder => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_AhviStylistChatSheet',
);

Widget _testApp({
  required _RecordingNavigatorObserver rootObserver,
  required _RecordingNavigatorObserver nestedObserver,
  required Widget launcher,
}) {
  final tokens = AppThemeTokens.light(_accent);
  return MaterialApp(
    theme: BaseTheme.light.copyWith(extensions: [tokens]),
    navigatorObservers: [rootObserver],
    home: Navigator(
      observers: [nestedObserver],
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => launcher),
    ),
  );
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  int popCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

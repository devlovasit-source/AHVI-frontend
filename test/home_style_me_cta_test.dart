import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/home.dart';
import 'package:myapp/home_card_summary_provider.dart';
import 'package:myapp/profile.dart' as profile;
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/ahvi_speech_service.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/feature/chat/widgets/blocks/visual_directions/visual_direction_carousel.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'EXPO_PUBLIC_APPWRITE_ENDPOINT=https://appwrite.test\n'
          'EXPO_PUBLIC_APPWRITE_PROJECT_ID=project\n'
          'EXPO_PUBLIC_APPWRITE_DATABASE_ID=database\n'
          'EXPO_PUBLIC_BACKEND_API_URL=https://backend.test/',
      isOptional: true,
    );
  });

  testWidgets('Style Me voice fills editable composer and uses normal send', (
    tester,
  ) async {
    final backend = _HomeStyleBackend();
    final speech = _FakeSpeechClient();
    await _pumpDirectStyleChat(tester, backend, speech);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(speech.startCount, 1);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

    speech.emit('What should I wear for dinner tomorrow?');
    await tester.pump();
    final input = find.descendant(
      of: _chatFinder,
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(input).controller?.text,
      'What should I wear for dinner tomorrow?',
    );
    expect(backend.moduleRequests, isEmpty);

    await tester.enterText(
      input,
      'What should I wear for dinner tomorrow night?',
    );
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(backend.moduleRequests, [
      'What should I wear for dinner tomorrow night?',
    ]);
  });

  testWidgets('Style Me voice second tap stops and denial stays typeable', (
    tester,
  ) async {
    final backend = _HomeStyleBackend();
    final speech = _FakeSpeechClient();
    await _pumpDirectStyleChat(tester, backend, speech);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    speech.finishWithError();
    await tester.pump();
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    expect(speech.stopCount, 1);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    speech.ready = false;
    await _pumpDirectStyleChat(tester, backend, speech);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(
      find.textContaining('Microphone access is unavailable'),
      findsOneWidget,
    );

    await _submit(tester, 'Typed chat still works');
    expect(backend.moduleRequests, contains('Typed chat still works'));
  });

  testWidgets('Home Style Me opens one prompt-free chat surface', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    final backend = _HomeStyleBackend();
    await _pumpHome(tester, backend, observer);

    final cta = find.byKey(const ValueKey('home-style-me-cta'));
    expect(cta, findsOneWidget);
    expect(tester.widget<Container>(cta).key, isNotNull);

    final pushesBefore = observer.materialPushes;
    await tester.tap(cta);
    await _waitForChat(tester);

    expect(observer.materialPushes, pushesBefore + 1);
    expect(_chatFinder, findsOneWidget);
    final dynamic chat = tester.widget(_chatFinder);
    expect(chat.moduleContext, 'style');
    expect(chat.initialPrompt, isNull);
    expect(chat.contextData, isEmpty);
    expect(backend.requests, isEmpty);
    expect(find.text('Curating your look'), findsNothing);
    expect(find.byType(VisualDirectionCarousel), findsNothing);
    expect(tester.takeException(), isNull);
    await _drainHomeBackground(tester);
  });

  testWidgets('Home Style card fits a short 360dp phone without overflow', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _HomeStyleBackend(),
      _RecordingNavigatorObserver(),
      size: const Size(360, 640),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Home Style Me rapid double tap does not duplicate routes', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await _pumpHome(tester, _HomeStyleBackend(), observer);
    final cta = find.byKey(const ValueKey('home-style-me-cta'));
    final pushesBefore = observer.materialPushes;

    await tester.tap(cta);
    await tester.tap(cta, warnIfMissed: false);
    await _waitForChat(tester);

    expect(observer.materialPushes, pushesBefore + 1);
    expect(_chatFinder, findsOneWidget);
    await _drainHomeBackground(tester);
  });

  testWidgets('Back closes Home Style Me and restores usable Home', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await _pumpHome(tester, _HomeStyleBackend(), observer);
    await tester.tap(find.byKey(const ValueKey('home-style-me-cta')));
    await _waitForChat(tester);

    await _popChatWithBack(tester);

    expect(_chatFinder, findsNothing);
    expect(find.byKey(const ValueKey('home-style-me-cta')), findsOneWidget);
    expect(observer.popCount, 1);
    expect(tester.takeException(), isNull);
    await _drainHomeBackground(tester);
  });

  testWidgets(
    'Home Style Me supports advice followed by Visual Inspiration boards',
    (tester) async {
      final backend = _HomeStyleBackend();
      await _pumpHome(tester, backend, _RecordingNavigatorObserver());
      await tester.tap(find.byKey(const ValueKey('home-style-me-cta')));
      await _waitForChat(tester);
      expect(find.text('Show visual inspiration'), findsNothing);

      await _submit(tester, 'What should I wear to a coffee date?');
      expect(find.textContaining('coffee date'), findsWidgets);
      expect(find.byType(VisualDirectionCarousel), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Lock'), findsNothing);

      await _submit(
        tester,
        'Show visual inspiration for a smart casual weekend.',
      );
      await _waitForText(tester, 'Smart Casual 1');
      await _waitForText(tester, 'Save', skipOffstage: false);
      expect(find.text('Smart Casual 1'), findsWidgets);
      expect(find.text('Smart Casual 2'), findsWidgets);
      expect(find.text('Smart Casual 3'), findsWidgets);
      expect(find.text('Save', skipOffstage: false), findsWidgets);
      expect(find.text('Share', skipOffstage: false), findsWidgets);
      expect(find.text('Lock'), findsNothing);
      expect(find.text('Shuffle'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(backend.moduleRequests, [
        'What should I wear to a coffee date?',
        'Show visual inspiration for a smart casual weekend.',
      ]);
      expect(backend.requestIds, hasLength(2));
      expect(backend.requestIds.toSet(), hasLength(2));
      expect(tester.takeException(), isNull);
      await _drainHomeBackground(tester);
    },
  );

  testWidgets('Wardrobe quick action sends wardrobe-first board flags', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _HomeStyleBackend();
    await tester.pumpWidget(
      Provider<BackendService>.value(
        value: backend,
        child: MaterialApp(
          theme: BaseTheme.light.copyWith(
            extensions: [AppThemeTokens.light(_accent)],
          ),
          localizationsDelegates: const [_TestLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAhviStylistChatSheet(
                context,
                moduleContext: 'wardrobe',
                initialPrompt: 'Use my wardrobe',
              ),
              child: const Text('Open wardrobe chat'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open wardrobe chat'));
    await tester.pumpAndSettle();

    expect(backend.requests, contains('Use my wardrobe'));
    expect(backend.actions, contains('use_my_wardrobe'));
    expect(backend.useWardrobe, isTrue);
    expect(backend.wardrobeFirst, isTrue);
    expect(backend.assetPolicy, 'wardrobe');
    expect(backend.allowGenericAssetsInMainBoard, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing Home Style Me during loading is lifecycle safe', (
    tester,
  ) async {
    final backend = _HomeStyleBackend(
      responseDelay: const Duration(seconds: 1),
    );
    final observer = _RecordingNavigatorObserver();
    await _pumpHome(tester, backend, observer);
    await tester.tap(find.byKey(const ValueKey('home-style-me-cta')));
    await _waitForChat(tester);
    await _submit(tester, 'Hi, how are you?');
    await tester.pump(const Duration(milliseconds: 50));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _popChatWithBack(tester);
    await tester.pump(const Duration(seconds: 10));

    expect(_chatFinder, findsNothing);
    expect(observer.popCount, 1);
    expect(tester.takeException(), isNull);
    await _drainHomeBackground(tester);
  });

  testWidgets('Home prompt and Style Me share colour-advice capability', (
    tester,
  ) async {
    final homeBackend = _HomeStyleBackend();
    await _pumpHome(tester, homeBackend, _RecordingNavigatorObserver());

    final homePrompt = find.byType(TextField).first;
    await tester.enterText(homePrompt, 'What colours suit me?');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _waitForText(tester, 'Colour advice is available.');
    expect(find.byType(VisualDirectionCarousel), findsNothing);
    final homeCall = homeBackend.moduleCalls.single;

    await _popChatWithBack(tester);
    final styleBackend = _HomeStyleBackend();
    await _pumpHome(tester, styleBackend, _RecordingNavigatorObserver());
    await tester.tap(find.byKey(const ValueKey('home-style-me-cta')));
    await _waitForChat(tester);
    await _submit(tester, 'What colours suit me?');
    await _waitForText(tester, 'Colour advice is available.');
    expect(find.byType(VisualDirectionCarousel), findsNothing);
    final styleCall = styleBackend.moduleCalls.single;

    expect(styleCall.domain, homeCall.domain);
    expect(styleCall.message, homeCall.message);
    expect(styleCall.chatHistory, homeCall.chatHistory);
    expect(styleCall.context, homeCall.context);
    expect(styleCall.domain, 'style');
    expect(styleCall.message, 'What colours suit me?');
  });

  testWidgets('Style Me retains colour context across advice turns', (
    tester,
  ) async {
    final backend = _HomeStyleBackend();
    await _pumpHome(tester, backend, _RecordingNavigatorObserver());
    await tester.tap(find.byKey(const ValueKey('home-style-me-cta')));
    await _waitForChat(tester);

    for (final prompt in [
      'What colours suit me?',
      'I have a warm undertone',
      'What about blue?',
      'Show me an outfit using those colours',
    ]) {
      await _submit(tester, prompt);
      await _waitForText(tester, _HomeStyleBackend.replyFor(prompt));
    }

    expect(find.byType(VisualDirectionCarousel), findsWidgets);
    expect(backend.moduleCalls, hasLength(4));
    expect(
      backend.moduleCalls.map((call) => call.domain),
      everyElement('style'),
    );
    expect(
      _historyContains(
        backend.moduleCalls[1].chatHistory,
        role: 'user',
        content: 'What colours suit me?',
      ),
      isTrue,
    );
    expect(
      _historyContains(
        backend.moduleCalls[1].chatHistory,
        role: 'assistant',
        content: _HomeStyleBackend.replyFor('What colours suit me?'),
      ),
      isTrue,
    );
    expect(
      _historyContains(
        backend.moduleCalls[2].chatHistory,
        role: 'user',
        content: 'I have a warm undertone',
      ),
      isTrue,
    );
    expect(
      _historyContains(
        backend.moduleCalls[3].chatHistory,
        role: 'user',
        content: 'What about blue?',
      ),
      isTrue,
    );
  });

  testWidgets('Style multi-turn activity context stays on module chat', (
    tester,
  ) async {
    final backend = _HomeStyleBackend(continuityMode: true);
    await _pumpHome(tester, backend, _RecordingNavigatorObserver());
    await tester.tap(find.byKey(const ValueKey('home-style-me-cta')));
    await _waitForChat(tester);

    await _submit(tester, 'I need something for tomorrow');
    await _waitForText(tester, 'What are you dressing for?');
    await _submit(tester, 'I have a badminton game');
    await _waitForText(tester, 'For your badminton game tomorrow.');
    await _submit(tester, 'show visual inspiration for this');
    await _waitForText(tester, 'For your badminton game tomorrow.');

    expect(backend.legacyRequests, isEmpty);
    expect(backend.moduleCalls, hasLength(3));
    expect(
      backend.moduleCalls.map((call) => call.domain),
      everyElement('style'),
    );
    expect(
      _historyContains(
        backend.moduleCalls[2].chatHistory,
        role: 'user',
        content: 'I have a badminton game',
      ),
      isTrue,
    );
    expect(find.byType(VisualDirectionCarousel), findsWidgets);
  });
}

Finder get _chatFinder => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().contains('AhviStylistChatSheet'),
);

Future<void> _waitForChat(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_chatFinder.evaluate().isNotEmpty) return;
  }
  fail('Home Style Me chat surface did not open');
}

Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  bool skipOffstage = true,
}) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text, skipOffstage: skipOffstage).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Expected text did not render: $text');
}

Future<void> _drainHomeBackground(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 9));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _popChatWithBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 100));
  if (_chatFinder.evaluate().isNotEmpty) {
    await tester.binding.handlePopRoute();
  }
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _pumpHome(
  WidgetTester tester,
  _HomeStyleBackend backend,
  NavigatorObserver observer, {
  Size size = const Size(1920, 2700),
}) async {
  final appwrite = AppwriteService();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppwriteService>.value(value: appwrite),
        Provider<BackendService>.value(value: backend),
        ChangeNotifierProvider<HomeCardSummaryProvider>(
          create: (_) => HomeCardSummaryProvider(),
        ),
        ChangeNotifierProvider<profile.ProfileController>(
          create: (_) => profile.ProfileController(),
        ),
      ],
      child: MaterialApp(
        theme: BaseTheme.light.copyWith(
          extensions: [AppThemeTokens.light(_accent)],
        ),
        localizationsDelegates: const [_TestLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        navigatorObservers: [observer],
        home: const Screen4(loadContextSignals: false),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpDirectStyleChat(
  WidgetTester tester,
  _HomeStyleBackend backend,
  AhviSpeechClient speech,
) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    Provider<BackendService>.value(
      value: backend,
      child: MaterialApp(
        theme: BaseTheme.light.copyWith(
          extensions: [AppThemeTokens.light(_accent)],
        ),
        localizationsDelegates: const [_TestLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAhviStylistChatSheet(
              context,
              moduleContext: 'style',
              speechClient: speech,
            ),
            child: const Text('Open Style Me'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Style Me'));
  await _waitForChat(tester);
}

Future<void> _submit(WidgetTester tester, String prompt) async {
  final input = find.descendant(
    of: _chatFinder,
    matching: find.byType(TextField),
  );
  await tester.enterText(input, prompt);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

bool _historyContains(
  List<Map<String, String>> history, {
  required String role,
  required String content,
}) => history.any(
  (entry) => entry['role'] == role && entry['content'] == content,
);

class _RecordingNavigatorObserver extends NavigatorObserver {
  int materialPushes = 0;
  int popCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute<void>) materialPushes++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

class _FakeSpeechClient implements AhviSpeechClient {
  bool ready = true;
  @override
  bool isListening = false;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  ValueChanged<String>? _onText;
  VoidCallback? _onDone;

  @override
  Future<bool> ensureReady() async => ready;

  @override
  Future<void> start({
    required ValueChanged<String> onText,
    VoidCallback? onDone,
  }) async {
    startCount++;
    isListening = true;
    _onText = onText;
    _onDone = onDone;
  }

  void emit(String text) => _onText?.call(text);

  void finishWithError() {
    isListening = false;
    _finish();
  }

  @override
  Future<void> stop() async {
    stopCount++;
    isListening = false;
    _finish();
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    isListening = false;
    _finish();
  }

  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }
}

class _TestLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_TestLocalizationsDelegate old) => false;
}

class _ModuleCall {
  final String domain;
  final String message;
  final List<Map<String, String>> chatHistory;
  final Map<String, dynamic> context;

  const _ModuleCall({
    required this.domain,
    required this.message,
    required this.chatHistory,
    required this.context,
  });
}

class _HomeStyleBackend extends BackendService {
  final Duration responseDelay;
  final bool continuityMode;
  final List<String> requests = [];
  final List<String> moduleRequests = [];
  final List<String> legacyRequests = [];
  final List<_ModuleCall> moduleCalls = [];
  final List<String> requestIds = [];
  final List<String> actions = [];
  bool useWardrobe = false;
  bool wardrobeFirst = false;
  String? assetPolicy;
  bool allowGenericAssetsInMainBoard = true;

  _HomeStyleBackend({
    this.responseDelay = Duration.zero,
    this.continuityMode = false,
  }) : super(appwriteService: AppwriteService());

  static String replyFor(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('warm undertone')) {
      return 'Warm undertones often suit earthy and golden colours.';
    }
    if (lower.contains('what about blue')) {
      return 'Blue can work well; compare warmer navy and softer blue shades.';
    }
    if (lower.contains('show me an outfit')) {
      return 'Here is an outfit using those colours.';
    }
    if (lower.contains('colours suit me')) {
      return 'Colour advice is available.';
    }
    return 'Hi. I am here to help with your style questions.';
  }

  @override
  Future<Map<String, dynamic>> getTodayWorkout({bool forceRefresh = false}) {
    return Future.value(const {});
  }

  @override
  Future<Map<String, dynamic>> sendModuleChat({
    required String domain,
    required String message,
    Map<String, dynamic>? context,
    List<Map<String, String>> chatHistory = const [],
    Map<String, dynamic>? userProfile,
    Map<String, dynamic>? styleState,
    String? requestId,
  }) async {
    moduleRequests.add(message);
    moduleCalls.add(
      _ModuleCall(
        domain: domain,
        message: message,
        chatHistory: List<Map<String, String>>.from(chatHistory),
        context: Map<String, dynamic>.from(context ?? const {}),
      ),
    );
    requestIds.add(requestId ?? '');
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    if (continuityMode) return _continuityResponse(message);
    final lower = message.toLowerCase();
    if (lower.contains('visual inspiration')) return _visualResponse();
    if (lower.contains('colours suit me') ||
        lower.contains('warm undertone') ||
        lower.contains('what about blue') ||
        lower.contains('show me an outfit')) {
      final isVisual = lower.contains('show me an outfit');
      return {
        'type': 'stylist_advice',
        'route': isVisual ? 'visual_inspiration' : 'style_advice',
        'response_mode': isVisual ? 'visual_inspiration' : 'text_only',
        'message_text': _HomeStyleBackend.replyFor(message),
        if (isVisual) ..._visualResponse(),
      };
    }
    if (lower.contains('coffee date')) {
      return {
        'type': 'stylist_advice',
        'route': 'style_advice',
        'mode': 'style_advice',
        'interaction_mode': 'advice',
        'message_text':
            'For a coffee date, choose a relaxed layer and finish with simple footwear.',
      };
    }
    return {
      'type': 'conversation',
      'route': 'conversation',
      'message_text': 'Hi. I am here to help with your style questions.',
    };
  }

  @override
  Future<Map<String, dynamic>> sendChatQuery(
    String query,
    String userId,
    List<Map<String, String>> chatHistory,
    String currentMemory, {
    bool isRetry = false,
    List<Map<String, dynamic>>? fetchedWardrobe,
    String moduleContext = 'chat',
    Map<String, dynamic>? userProfile,
    String? styleAction,
    List<String> excludeStyleSignatures = const [],
    int? requestedBoardCount,
    String? action,
    String? clarification,
    String? sessionId,
    String? previousPrompt,
    String? resolvedPrompt,
    String? currentLookId,
    Map<String, dynamic>? styleContext,
    Map<String, dynamic>? styleState,
    Map<String, dynamic>? lastStyleContext,
    bool showClosestOption = false,
    bool allowClosestOption = false,
    bool closest = false,
    bool useWardrobe = false,
    bool wardrobeFirst = false,
    String? assetPolicy,
    bool allowGenericAssetsInMainBoard = true,
    String? requestId,
  }) async {
    requests.add(query);
    if (continuityMode) legacyRequests.add(query);
    actions.add(action ?? styleAction ?? '');
    this.useWardrobe = useWardrobe;
    this.wardrobeFirst = wardrobeFirst;
    this.assetPolicy = assetPolicy;
    this.allowGenericAssetsInMainBoard = allowGenericAssetsInMainBoard;
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    final lower = query.toLowerCase();
    if (lower.contains('visual inspiration')) return _visualResponse();
    if (lower.contains('white shirt')) {
      return {
        'type': 'stylist_advice',
        'route': 'style_pairing',
        'mode': 'style_pairing',
        'interaction_mode': 'pairing',
        'message_text': 'Pair the white shirt with a deeper neutral bottom.',
      };
    }
    if (lower.contains('coffee date')) {
      return {
        'type': 'stylist_advice',
        'route': 'style_advice',
        'mode': 'style_advice',
        'interaction_mode': 'advice',
        'message_text':
            'For a coffee date, choose a relaxed layer and finish with simple footwear.',
      };
    }
    if (lower.contains('wardrobe')) {
      return {
        'type': 'cards',
        'route': 'wardrobe_style',
        'mode': 'wardrobe_style',
        'action': 'use_wardrobe',
        'board_policy': 'wardrobe',
        'interaction_mode': 'wardrobe',
        'source_policy': 'wardrobe',
        'message_text': 'I used your wardrobe.',
        'data': {
          'rendered_boards': [_board('wardrobe-1'), _board('wardrobe-2')],
        },
        'cards': [
          {'title': 'Generic module card one'},
          {'title': 'Generic module card two'},
        ],
      };
    }
    return {
      'type': 'conversation',
      'route': 'conversation',
      'message_text': 'Hi. I am here to help with your style questions.',
    };
  }

  Map<String, dynamic> _visualResponse() => {
    'type': 'stylist_advice',
    'route': 'style_advice',
    'mode': 'style_advice',
    'board_policy': 'recommendation',
    'interaction_mode': 'recommendation',
    'visual_directions': [
      _board('board-1'),
      _board('board-2'),
      _board('board-3'),
    ],
  };

  Map<String, dynamic> _continuityResponse(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('need something')) {
      return {
        'type': 'clarification',
        'route': 'clarification',
        'response_mode': 'clarification',
        'message_text': 'What are you dressing for?',
      };
    }
    if (lower.contains('badminton')) {
      return {
        'type': 'stylist_advice',
        'route': 'style_advice',
        'response_mode': 'text_only',
        'message_text': 'For your badminton game tomorrow.',
      };
    }
    return {
      ..._visualResponse(),
      'response_mode': 'visual_inspiration',
      'message_text': 'For your badminton game tomorrow.',
    };
  }

  Map<String, dynamic> _board(String id) => {
    'board_id': id,
    'revision': 3,
    'source_policy': 'wardrobe',
    'title': 'Smart Casual ${id.substring(id.length - 1)}',
    'items': [
      _boardItem('top-$id', 'White Shirt', 'top'),
      _boardItem('bottom-$id', 'Dark Trousers', 'bottom'),
      _boardItem('shoe-$id', 'Clean Sneakers', 'footwear'),
    ],
  };

  Map<String, dynamic> _boardItem(String id, String name, String role) => {
    'item_id': id,
    'name': name,
    'slot': role,
    'role': role,
    'source': 'wardrobe',
    'image_url': 'https://example.test/$id.jpg',
    'board_image_url': 'https://example.test/$id.png',
    'board_status': 'cutout_ready',
    'position': {
      'x': 0.1,
      'y': 0.1,
      'width': 0.4,
      'height': 0.4,
      'rotation': 0,
      'z': 1,
    },
  };
}

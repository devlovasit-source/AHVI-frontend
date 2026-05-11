import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart';
import 'package:myapp/boards.dart';
import 'package:myapp/profile.dart' as profile;
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/ahvi_chat_prompt_bar.dart';
import 'package:myapp/widgets/ahvi_lens_sheet.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:provider/provider.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/ahvi_response_parser.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/chat.dart'; // 🚀 Added Chat Screen Integration
import 'package:myapp/app_localizations.dart'; // 🆕 Localization

// ─── Colors ──────────────────────────────────────────────

// 🆕 Nav items are now built dynamically in _buildBottomNav() using localization
// _homeNavItems icons only — labels come from JSON
const _homeNavIcons = <IconData>[
  Icons.home_outlined,
  Icons.dry_cleaning_outlined,
  Icons.grid_view_rounded,
  Icons.explore_outlined,
];
// Keep original for fallback / non-localized usage
const _homeNavItems = <({IconData icon, String label})>[
  (icon: Icons.home_outlined, label: 'Home'),
  (icon: Icons.dry_cleaning_outlined, label: 'Wardrobe'),
  (icon: Icons.grid_view_rounded, label: 'Planner'),
  (icon: Icons.explore_outlined, label: 'Explore'),
];

Color _accent(AppThemeTokens t) => t.accent.primary;
Color _accentSecondary(AppThemeTokens t) => t.accent.secondary;
Color _accentTertiary(AppThemeTokens t) => t.accent.tertiary;

// 🆕 AI suggestions keys — values come from JSON
const _aiSuggestionKeys = [
  'ai_sug_1',
  'ai_sug_2',
  'ai_sug_3',
  'ai_sug_4',
  'ai_sug_5',
  'ai_sug_6',
  'ai_sug_7',
];
// Keep original English as fallback
const _aiSuggestions = [
  "Your 2pm meeting is in 4 hrs — want to prep an outfit?",
  "It's 14°C and partly cloudy — shall I suggest a layered look?",
  "You haven't planned your week yet — want me to help?",
  "Feeling indecisive? I can style you in seconds.",
  "New drops match your saved style — want to see them?",
  "Your Friday dinner is coming up — let's plan the look.",
  "I noticed you love minimal styles — new picks are in.",
];

// 🆕 Prepare chips keys for localization
const _prepareChipKeys = [
  ('prepare_carry_on', '✈️ Carry-on Packing'),
  ('prepare_birthday', '🎂 Birthday Party Planning'),
  ('prepare_camping', '🏕️ Camping Trip'),
  ('prepare_wedding', '💍 Wedding Planning'),
  ('prepare_workout', '🏋️ Gym Workout Routine'),
  ('prepare_meal_prep', '🍳 Weekly Meal Prep'),
  ('prepare_dev_project', '💻 New Coding Project Setup'),
  ('prepare_moving', '🏠 House Moving Checklist'),
  ('prepare_study', '🎓 Exam Study Plan'),
  ('prepare_gardening', '🌿 Garden Planting'),
];
const _prepareChips = [
  ('✈️ Carry-on', '✈️ Carry-on Packing'),
  ('🎂 Birthday Party', '🎂 Birthday Party Planning'),
  ('🏕️ Camping', '🏕️ Camping Trip'),
  ('💍 Wedding', '💍 Wedding Planning'),
  ('🏋️ Workout', '🏋️ Gym Workout Routine'),
  ('🍳 Meal Prep', '🍳 Weekly Meal Prep'),
  ('💻 Dev Project', '💻 New Coding Project Setup'),
  ('🏠 Moving House', '🏠 House Moving Checklist'),
  ('🎓 Study Plan', '🎓 Exam Study Plan'),
  ('🌿 Gardening', '🌿 Garden Planting'),
];

typedef _SuggestionState = ({int index, double opacity});
typedef _ClockState = ({String greeting, String date});

class Screen4 extends StatefulWidget {
  const Screen4({super.key, this.onShellNavTap});

  final ValueChanged<int>? onShellNavTap;

  @override
  State<Screen4> createState() => _Screen4State();
}

class _Screen4State extends State<Screen4>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  AppThemeTokens get _t => context.themeTokens;

  // 🔧 FIX: Palette switch అయినప్పుడు full rebuild trigger చేయడానికి
  // accent color track చేస్తాం — change అయితే setState() చేస్తాం
  Color? _cachedAccent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAccent = context.themeTokens.accent.primary;
    if (_cachedAccent != null && _cachedAccent != newAccent) {
      // Palette switch జరిగింది — IndexedStack లో alive గా ఉన్న
      // ఈ screen ని force rebuild చేయాలి
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _cachedAccent = newAccent;
  }

  Color get _bgPrimary => _t.backgroundPrimary;
  Color get _bgSecondary => _t.backgroundSecondary;
  Color get _surface => _t.phoneShellInner;
  Color get _textHeading => _t.textPrimary;
  Color get _textSub => _t.mutedText;
  Color get _textMuted => _t.mutedText;
  Color get _accent => _t.accent.primary;
  Color get _accentSecondary => _t.accent.secondary;
  Color get _accentTertiary => _t.accent.tertiary;
  Color get _panel => _t.panel;
  Color get _card => _t.card;
  Color get _phoneShell => _t.phoneShell;
  Color get _tileText => _t.tileText;
  Color get _shadowStrong => _bgPrimary.withValues(alpha: 0.35);
  Color get _shadowMedium => _bgPrimary.withValues(alpha: 0.20);
  Color get _shadowLight => _bgPrimary.withValues(alpha: 0.12);
  Color get _transparent => _bgPrimary.withValues(alpha: 0.0);
  Color get _onAccent => Theme.of(context).colorScheme.onPrimary;
  Color get _border => _t.cardBorder;
  LinearGradient get _accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_accent, _accentTertiary],
  );
  LinearGradient get _accentGradient2 => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_accent, _accentSecondary],
  );

  late AnimationController _aurora1Ctrl;
  late AnimationController _aurora2Ctrl;
  late AnimationController _aurora3Ctrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _pulseCtrl;
  int _activeNavIdx = 0;

  late AnimationController _floatBadgeCtrl;
  late AnimationController _breatheCtrl;
  late List<AnimationController> _heartPopCtrls;
  final List<bool> _likedState = [false, false, true, false];

  final ValueNotifier<_SuggestionState> _suggestionState =
      ValueNotifier<_SuggestionState>((index: 0, opacity: 1.0));
  Timer? _suggestionTimer;

  // ── Plus menu ─────────────────────────────────────────────────────────────
  // (Lens sheet manages its own state — no local controller needed)
  late AnimationController _plusMenuCtrl; // kept to avoid dispose() errors

  bool _toastVisible = false;
  Timer? _toastTimer;

  bool _seeAllOpen = false;
  late AnimationController _seeAllCtrl;

  late List<AnimationController> _navRiseCtrls;

  final ValueNotifier<_ClockState> _clockState = ValueNotifier<_ClockState>((
    greeting:
        'greeting_morning', // 🆕 key గా store — display లో translate అవుతుంది
    date: '',
  ));
  Timer? _clockTimer;
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ValueNotifier<double> _keyboardHeight = ValueNotifier<double>(0.0);

  // ── Voice ──────────────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  final Map<String, List<List<bool>>> _prepareExactChecksByTitle = {};
  final Map<String, List<List<String>>> _prepareExactItemsByTitle = {};
  final Map<String, List<TextEditingController>>
  _prepareExactAddControllersByTitle = {};
  final Map<String, bool> _prepareExactSavedByTitle = {};
  final Map<String, List<bool>> _prepareExactOutfitSavedByTitle = {};
  final Map<String, String> _boardIdByLabel = const {
    '🎉 Party Looks': 'party_looks',
    '💍 Occasion': 'occasion',
    '💼 Office Fit': 'office_fit',
    '✈️ Vacation': 'vacation',
    '✨ Everything Else': 'everything_else',
  };

  _OverlayState _overlayState = _OverlayState.idle;
  String? _activeIntent;
  String _chatPlaceholderKey = 'ask_me'; // ✅ JSON key: "ask_me"
  String get _chatPlaceholder =>
      AppLocalizations.t(context, _chatPlaceholderKey);
  bool _homeCollapsed = false;
  late AnimationController _homeCollapseCtrl;
  late AnimationController _overlayFadeCtrl;
  late AnimationController _thinkingCtrl;
  late AnimationController _tagsRevealCtrl;
  List<String> _overlaySuggestions = [];
  String _overlayBrandSub = '';

  // 🚀 STATE FIX: We now use a list to stack messages + tracking variables
  final List<_ResponseData> _responses = [];
  final List<Map<String, String>> _chatHistory = [];
  String _runningMemory = "";
  final ScrollController _overlayScrollCtrl = ScrollController();

  List<String> _responseTags = [];
  final Map<String, String> _responseTagValues = {};
  bool _tagsRevealed = false;

  String _userName = '';
  Uint8List? _avatarBytes;

  Future<void> _savePrepareExactToBoard({
    required String boardId,
    required String title,
    required List<
      ({String name, String emoji, Color color, List<String> items})
    >
    sections,
    required List<List<String>> itemsState,
    required List<List<bool>> checksState,
    required List<bool> outfitSaved,
  }) async {
    final sectionPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < sections.length; i++) {
      sectionPayload.add({
        'name': sections[i].name,
        'emoji': sections[i].emoji,
        'color': sections[i].color.value,
        'items': List<String>.from(itemsState[i]),
        'checked': List<bool>.from(checksState[i]),
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
    // Keyboard height track చేయడానికి FocusNode listener
    _chatFocusNode.addListener(_onChatFocusChange);
    WidgetsBinding.instance.addObserver(this);

    _aurora1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
    _aurora2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
    _aurora3Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat(reverse: true);
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _floatBadgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _heartPopCtrls = List.generate(
      4,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      ),
    );

    _seeAllCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _plusMenuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _navRiseCtrls = List.generate(
      4,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
        value: i == 0 ? 1.0 : 0.0,
      ),
    );

    _suggestionTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _rotateSuggestion(),
    );

    _homeCollapseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _overlayFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _thinkingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _tagsRevealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _updateClock(),
    );

    _fetchUserProfile();

    // 🔧 FIX: Home tab active glow — first frame లో animate చేయి
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _navRiseCtrls[0].animateTo(
          1.0,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
      }
    });
  }

  Future<void> _fetchUserProfile() async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);
    final profileCtrl = Provider.of<profile.ProfileController>(
      context,
      listen: false,
    );
    final user = await appwrite.getCurrentUser();

    if (user != null && mounted) {
      // ProfileController లో name ఉంటే దాన్ని వాడు (onboarding లో enter చేసిన name)
      // లేకపోతే Appwrite user.name వాడు
      final profileName = profileCtrl.state.name;
      final rawName = (profileName != null && profileName.isNotEmpty)
          ? profileName
          : user.name;

      final firstName = rawName.isNotEmpty
          ? rawName.split(' ').first
          : 'Stylist';

      // avatarPath లేనప్పుడు Appwrite fallback avatar తెచ్చుకో
      Uint8List? avatarBytes;
      try {
        avatarBytes = await appwrite.getUserAvatar(rawName);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _userName = firstName;
          _avatarBytes = avatarBytes;
        });
      }
    }
  }

  void _updateClock() {
    if (!mounted) return;
    final now = DateTime.now();
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    // 🆕 Greeting key — translated in _buildGreetingBlock()
    String greetingKey;
    if (now.hour >= 5 && now.hour < 12) {
      greetingKey = 'greeting_morning';
    } else if (now.hour >= 12 && now.hour < 17) {
      greetingKey = 'greeting_afternoon';
    } else if (now.hour >= 17 && now.hour < 21) {
      greetingKey = 'greeting_evening';
    } else {
      greetingKey = 'greeting_night';
    }
    _clockState.value = (
      greeting: greetingKey,
      date: '${days[now.weekday % 7]}, ${now.day} ${months[now.month - 1]}',
    );
  }

  void _rotateSuggestion() {
    final current = _suggestionState.value;
    _suggestionState.value = (index: current.index, opacity: 0.0);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _suggestionState.value = (
        index: (current.index + 1) % _aiSuggestions.length,
        opacity: 1.0,
      );
    });
  }

  void _startThinkingAnimation() {
    if (!_thinkingCtrl.isAnimating) {
      _thinkingCtrl.repeat();
    }
  }

  void _stopThinkingAnimation() {
    if (_thinkingCtrl.isAnimating) {
      _thinkingCtrl
        ..stop()
        ..value = 0.0;
    }
  }

  // ── Voice methods ──────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _chatController.text = result.recognizedWords;
            _chatController.selection = TextSelection.fromPosition(
              TextPosition(offset: _chatController.text.length),
            );
          });
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _speech.stop();
            setState(() => _isListening = false);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_IN',
        cancelOnError: true,
        partialResults: true,
      );
    }
  }

  void _onChatFocusChange() {
    if (!mounted) return;
    if (!_chatFocusNode.hasFocus) {
      _keyboardHeight.value = 0.0;
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // ValueNotifier మాత్రమే update చేయి — setState() లేదు.
    // Prompt bar Builder లో MediaQuery.of(ctx).viewInsets directly read అవుతుంది.
    // setState() వేస్తే logo కూడా rebuild అయి jump అవుతుంది.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final kbH = MediaQuery.of(context).viewInsets.bottom;
      if (_keyboardHeight.value != kbH) {
        _keyboardHeight.value = kbH;
      }
    });
  }

  void dispose() {
    _chatFocusNode.removeListener(_onChatFocusChange);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardHeight.dispose();
    _speech.stop();
    _aurora1Ctrl.dispose();
    _aurora2Ctrl.dispose();
    _aurora3Ctrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    _floatBadgeCtrl.dispose();
    _breatheCtrl.dispose();
    for (final c in _heartPopCtrls) {
      c.dispose();
    }
    _seeAllCtrl.dispose();
    _plusMenuCtrl.dispose();
    for (final c in _navRiseCtrls) {
      c.dispose();
    }
    _homeCollapseCtrl.dispose();
    _overlayFadeCtrl.dispose();
    _thinkingCtrl.dispose();
    _tagsRevealCtrl.dispose();
    _suggestionTimer?.cancel();
    _toastTimer?.cancel();
    _clockTimer?.cancel();
    _suggestionState.dispose();
    _clockState.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    for (final ctrls in _prepareExactAddControllersByTitle.values) {
      for (final c in ctrls) {
        c.dispose();
      }
    }
    _overlayScrollCtrl.dispose();
    super.dispose();
  }

  void _showComingSoon() {
    setState(() => _toastVisible = true);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  // 🚀 FIXED: Chat Navigation logic for the Bottom Nav Bar
  void _handleNavTap(int idx) {
    if (idx == 0) {
      // Home tab — already here, just ensure active
      if (_activeNavIdx != 0) {
        _navRiseCtrls[_activeNavIdx].animateTo(
          0.0,
          curve: const Cubic(0.4, 0.0, 0.2, 1.0),
        );
        _navRiseCtrls[0].animateTo(
          1.0,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
        setState(() => _activeNavIdx = 0);
      } else {
        // 🔧 FIX: Already on home tab — rise animation ensure చేయి
        _navRiseCtrls[0].animateTo(
          1.0,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0),
        );
      }
      if (widget.onShellNavTap != null) widget.onShellNavTap!(0);
      return;
    }

    // Highlight the tapped tab immediately before navigating
    void _activateTab(int i) {
      _navRiseCtrls[_activeNavIdx].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
      _navRiseCtrls[i].animateTo(
        1.0,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      setState(() => _activeNavIdx = i);
    }

    if (idx == 1) {
      // 🔧 FIX: Shell కి delegate చేసే ముందు local tab highlight చేయి
      _navRiseCtrls[_activeNavIdx].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
      _navRiseCtrls[1].animateTo(
        1.0,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      setState(() => _activeNavIdx = 1);
      if (widget.onShellNavTap != null) {
        widget.onShellNavTap!(1);
        return;
      }
      _openNavScreen(const WardrobeScreen());
      return;
    }
    if (idx == 2) {
      // 🔧 FIX: Shell కి delegate చేసే ముందు local tab highlight చేయి
      _navRiseCtrls[_activeNavIdx].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
      _navRiseCtrls[2].animateTo(
        1.0,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      );
      setState(() => _activeNavIdx = 2);
      if (widget.onShellNavTap != null) {
        widget.onShellNavTap!(2);
        return;
      }
      _openNavScreen(const BoardsScreen());
      return;
    }
    if (idx == 3) {
      _showComingSoon();
      return;
    }
    if (idx == _activeNavIdx) return;

    _navRiseCtrls[_activeNavIdx].animateTo(
      0.0,
      curve: const Cubic(0.4, 0.0, 0.2, 1.0),
    );
    _navRiseCtrls[idx].animateTo(
      1.0,
      curve: const Cubic(0.34, 1.56, 0.64, 1.0),
    );
    setState(() => _activeNavIdx = idx);
  }

  void _openPlusMenu(BuildContext ctx) {
    HapticFeedback.lightImpact();
    final navigator = Navigator.of(ctx, rootNavigator: true);
    showAhviLensSheet(
      ctx,
      t: _t,
      onVisualSearch: () => _showComingSoon(),
      onFindSimilar: () => _showComingSoon(),
      onAddToWardrobe: () => showAddToWardrobeModal(navigator.context),
    );
  }

  void _closePlusMenu() {
    // No-op: lens sheet manages its own dismiss
  }

  void _openNavScreen(Widget page) {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 350),
            reverseTransitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (context, animation, secondary) => page,
            transitionsBuilder: (context, animation, secondary, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: const Cubic(0.22, 1.0, 0.36, 1.0),
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        )
        .then((_) {
          // Back వచ్చినప్పుడు Home tab active గా reset చేయి
          if (!mounted) return;
          final prevIdx = _activeNavIdx;
          if (prevIdx != 0) {
            _navRiseCtrls[prevIdx].animateTo(
              0.0,
              curve: const Cubic(0.4, 0.0, 0.2, 1.0),
            );
          }
          _navRiseCtrls[0].animateTo(
            1.0,
            curve: const Cubic(0.34, 1.56, 0.64, 1.0),
          );
          setState(() => _activeNavIdx = 0);
          // 🔧 FIX: Shell కి కూడా Home index తెలియజేయి — nav bar తిరిగి కనపడుతుంది
          if (widget.onShellNavTap != null) widget.onShellNavTap!(0);
        });
  }

  void _openModuleChat(String moduleKey) {
    // Overlay తెరవకుండా directly ChatScreen కి navigate చేయి
    final module = (moduleKey == 'plan') ? 'prepare' : moduleKey;
    _openNavScreen(ChatScreen(moduleContext: module));
  }

  void _openChatWithPrompt(String prompt) {
    final text = prompt.trim();
    final module = (_activeIntent ?? 'style').trim();
    if (text.isEmpty) {
      _openNavScreen(ChatScreen(moduleContext: module));
      return;
    }
    _openNavScreen(ChatScreen(moduleContext: module, initialPrompt: text));
  }

  void _openPickSheet(String name, String tag) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _bgPrimary.withValues(alpha: 0.30),
      builder: (sheetContext) => _buildPickSheet(
        name: name,
        tag: tag,
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  void _openSeeAll() {
    setState(() => _seeAllOpen = true);
    _seeAllCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 400),
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
  }

  void _closeSeeAll() {
    _seeAllCtrl
        .animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: const Cubic(0.4, 0.0, 1.0, 1.0),
        )
        .then((_) {
          if (mounted) setState(() => _seeAllOpen = false);
        });
  }

  void _toggleLike(int cardIdx) {
    setState(() => _likedState[cardIdx] = !_likedState[cardIdx]);
    _heartPopCtrls[cardIdx]
      ..reset()
      ..forward();
  }

  void _triggerIntent(String intent) {
    if (_overlayState != _OverlayState.idle) return;
    _activeIntent = intent;
    final cfg = _intentConfig[intent]!;
    _setPlaceholder(intent);
    setState(() {
      _homeCollapsed = true;
      _overlayBrandSub = cfg.brandSub;
    });
    _homeCollapseCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
    Future.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        _stopThinkingAnimation();
        _overlayState = _OverlayState.suggestions;
        _overlaySuggestions = cfg.suggestions;
        _responses.clear();
        _tagsRevealed = false;
      });
      _overlayFadeCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 380),
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      );
    });
  }

  void _submitQuery(String query) {
    // Overlay తెరవకుండా directly ChatScreen కి navigate చేయి
    _openChatWithPrompt(query);
  }

  // 🚀 FIXED FUNCTION: REAL API CALL WITH HISTORY & MEMORY
  Future<void> _handleQuery(String question, String intent) async {
    if (_overlayState == _OverlayState.thinking) return;

    final cfg = _intentConfig[intent] ?? _intentConfig['chat']!;

    setState(() {
      _startThinkingAnimation();
      _overlayState = _OverlayState.thinking;
      _overlaySuggestions = [];
      _responseTags = cfg.responseTags;
      _responseTagValues.clear();
      _tagsRevealed = false;
      // We DO NOT clear _responses here so the old messages stay on screen!
    });

    _ResponseData? resp;

    final isPrepareQuickChip =
        intent == 'prepare' && _prepareChips.any((chip) => chip.$2 == question);
    if (isPrepareQuickChip) {
      resp = _buildPrepareChipResponse(question);
    } else {
      try {
        final backend = Provider.of<BackendService>(context, listen: false);

        // Grab the history payload we've been secretly storing
        final historyPayload = List<Map<String, String>>.from(_chatHistory);

        final apiResult = await backend.sendChatQuery(
          question,
          'user_$_userName',
          historyPayload,
          _runningMemory,
          moduleContext: intent,
        );
        final parsed = AhviResponse.fromMap(apiResult);

        // Store user's question into history
        _chatHistory.add({"role": "user", "content": question});

        if (apiResult['updated_memory'] != null) {
          _runningMemory = apiResult['updated_memory'];
        }

        String aiText = parsed.messageText.isNotEmpty
            ? parsed.messageText
            : (apiResult['error']?.toString() ?? "No content");

        // Store AHVI's response into history
        _chatHistory.add({"role": "assistant", "content": aiText});

        // Cleanup tags perfectly
        aiText = aiText.replaceAll(
          RegExp(r'\[CHIPS:.*?\]', caseSensitive: false, dotAll: true),
          '',
        );
        aiText = aiText.replaceAll(
          RegExp(r'\[STYLE_BOARD:.*?\]', caseSensitive: false, dotAll: true),
          '',
        );
        aiText = aiText.replaceAll(
          RegExp(r'\[PACK_LIST:.*?\]', caseSensitive: false, dotAll: true),
          '',
        );
        aiText = aiText.trim();

        if (aiText.length > 1500) {
          aiText =
              '${aiText.substring(0, 1500)}... \n\n[Text truncated to prevent UI crash]';
        }

        if (parsed.chips.isNotEmpty) {
          _responseTags = parsed.chips.map((chip) => chip.label).toList();
          _responseTagValues
            ..clear()
            ..addEntries(
              parsed.chips.map((chip) => MapEntry(chip.label, chip.value)),
            );
        }

        resp = _responseDataFromAhvi(question, aiText, parsed);
      } catch (e) {
        String errorMsg = e.toString();
        if (errorMsg.length > 150) {
          errorMsg = '${errorMsg.substring(0, 150)}... [Error Truncated]';
        }

        resp = _ResponseData(
          type: 'text',
          question: question,
          intro: "Backend Connection Failed.\n\n$errorMsg",
        );
      }
    }

    if (!mounted) return;

    setState(() {
      _stopThinkingAnimation();
      _overlayState = _OverlayState.response;
      _responses.add(resp!); // 🚀 Add the new message to the list!
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_overlayScrollCtrl.hasClients) {
        _overlayScrollCtrl.animateTo(
          _overlayScrollCtrl.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    const int tagDelay = 150;

    Future.delayed(Duration(milliseconds: tagDelay), () {
      if (!mounted) return;
      setState(() => _tagsRevealed = true);
      _tagsRevealCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 200),
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      );
    });
  }

  void _dismissOverlay() {
    _overlayFadeCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: const Cubic(0.4, 0.0, 1.0, 1.0),
    );
    _homeCollapseCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 500),
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
    setState(() {
      _stopThinkingAnimation();
      _overlayState = _OverlayState.idle;
      _activeIntent = null;
      _homeCollapsed = false;
      _overlaySuggestions = [];
      _responseTagValues.clear();
      _responses.clear();
      _tagsRevealed = false;
      _chatPlaceholderKey = 'ask_me'; // ✅
    });
  }

  void _setPlaceholder(String intent) {
    // 🆕 Key store చేస్తున్నాం — getter లో translate అవుతుంది
    setState(() => _chatPlaceholderKey = 'placeholder_$intent');
  }

  void _handlePrepareChipSend(String query) {
    if (_activeIntent == 'prepare' &&
        (_overlayState == _OverlayState.suggestions ||
            _overlayState == _OverlayState.response)) {
      _handleQuery(query, 'prepare');
      return;
    }
    if (_overlayState == _OverlayState.idle) {
      _triggerIntent('prepare');
      Future.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        if (_overlayState == _OverlayState.suggestions &&
            (_activeIntent ?? 'prepare') == 'prepare') {
          _handleQuery(query, 'prepare');
        }
      });
    }
  }

  _ResponseData _buildPrepareChipResponse(String question) {
    return _ResponseData(type: 'prepare_exact', question: question, intro: '');
  }

  String _tagText(String tag) {
    final looksLikeLocalizationKey =
        RegExp(r'^[a-z0-9_]+$').hasMatch(tag) && tag.contains('_');
    return looksLikeLocalizationKey ? AppLocalizations.t(context, tag) : tag;
  }

  String _tagValue(String tag) => _responseTagValues[tag] ?? _tagText(tag);

  _ResponseData _responseDataFromAhvi(
    String question,
    String aiText,
    AhviResponse parsed,
  ) {
    final planSections = _planSectionsFromAhvi(parsed);
    if (planSections.isNotEmpty) {
      return _ResponseData(
        type: 'plan',
        question: question,
        intro: aiText,
        planSections: planSections,
      );
    }
    if (parsed.isPrep && parsed.checklistItems.isNotEmpty) {
      return _ResponseData(
        type: 'plan',
        question: question,
        intro: aiText,
        planSections: [
          _PlanSection(
            'Prep checklist',
            (_) => _accentTertiary,
            parsed.checklistItems,
          ),
        ],
      );
    }
    return _ResponseData(type: 'text', question: question, intro: aiText);
  }

  List<_PlanSection> _planSectionsFromAhvi(AhviResponse parsed) {
    final sections = parsed.isPrep && parsed.prepSections.isNotEmpty
        ? parsed.prepSections
        : parsed.planSections;
    final colors = [
      (AppThemeTokens t) => _accent,
      (AppThemeTokens t) => _accentSecondary,
      (AppThemeTokens t) => _accentTertiary,
    ];
    return List<_PlanSection>.generate(sections.length, (index) {
      final section = sections[index];
      return _PlanSection(
        section.title,
        colors[index % colors.length],
        section.items,
      );
    });
  }

  bool get _hasTransientUi =>
      _seeAllOpen || _overlayState != _OverlayState.idle;

  void _handleBackNavigation() {
    if (_seeAllOpen) {
      _closeSeeAll();
      return;
    }
    if (_overlayState != _OverlayState.idle) {
      _dismissOverlay();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasTransientUi,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
        backgroundColor: _bgPrimary,
        resizeToAvoidBottomInset: false,
        body: _buildPhoneScreen(),
      ),
    );
  }

  Widget _buildPhoneScreen() {
    return Container(
      decoration: BoxDecoration(color: _bgPrimary),
      child: Stack(
        children: [
          _buildAuroraLayer(),

          AnimatedBuilder(
            animation: _homeCollapseCtrl,
            builder: (context, child) {
              final curve = CurvedAnimation(
                parent: _homeCollapseCtrl,
                curve: const Cubic(0.16, 1.0, 0.3, 1.0),
                reverseCurve: const Cubic(0.4, 0.0, 1.0, 1.0),
              );
              final t = curve.value;
              return Transform.translate(
                offset: Offset(0, -48 * t),
                child: Transform.scale(
                  scale: 1.0 - 0.02 * t,
                  child: Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0),
                    child: IgnorePointer(
                      ignoring: _homeCollapsed,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: SafeArea(
              top: true,
              bottom: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenH = constraints.maxHeight;

                  const navBarH =
                      86.0; // nav bar total height (pillH + maxBulge + safeBottom)
                  const topSectionH = 170.0;
                  const spacing = 18.0;

                  // Placeholder height — _buildFixedLogoBar తో exact match:
                  // SafeArea.top (statusBarH) + topPad + logoFontSize + botPad
                  // Chat _ChatLogoHeader కూడా same values use చేస్తోంది
                  final double topPad = screenH < 700 ? 6.0 : 10.0;
                  final double botPad = screenH < 700 ? 4.0 : 6.0;
                  final double logoFontSizeH = screenH < 700 ? 26.0 : 30.0;
                  final double statusBarH = MediaQuery.paddingOf(context).top;
                  final double topBarPlaceholderH =
                      statusBarH + topPad + logoFontSizeH + botPad;

                  // Available height after fixed sections
                  const chatBarH = 64.0;
                  const navBarH2 = 86.0;
                  const bottomReserve = 10 + chatBarH + navBarH2;
                  final availableH =
                      screenH -
                      topBarPlaceholderH -
                      topSectionH -
                      bottomReserve -
                      spacing;
                  // Hero gets 62%, secondary gets 38% of available space
                  final heroFlex = 62;
                  final secFlex = 38;

                  return SizedBox(
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20.0, right: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Space reserved for fixed logo overlay (not animated)
                          SizedBox(height: topBarPlaceholderH),
                          _buildGreetingBlock(),
                          // Hero card — grows with screen
                          Expanded(
                            flex: heroFlex,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildHeroCard(),
                            ),
                          ),
                          // Plan & Prep cards — also grow with screen
                          Expanded(
                            flex: secFlex,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildSecondaryRow(),
                            ),
                          ),
                          // Space reserved for floating prompt bar + nav bar (Positioned in Stack)
                          const SizedBox(height: 10 + 64 + navBarH),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Fixed AHVI Logo — Chat screen లాగే Positioned గా ఉంది ──
          // top: 0, SafeArea(bottom: false) తో — Chat _ChatLogoHeader తో
          // exact match అవుతుంది: status bar + topPad + logoFontSize + botPad
          Positioned(top: 0, left: 0, right: 0, child: _buildFixedLogoBar()),

          if (_overlayState != _OverlayState.idle) _buildAiOverlay(),

          if (_activeIntent == 'prepare' &&
              (_overlayState == _OverlayState.suggestions ||
                  _overlayState == _OverlayState.response))
            Builder(
              builder: (context) {
                final keyboardH = MediaQuery.of(context).viewInsets.bottom;
                final chipsBottom = keyboardH > 0
                    ? keyboardH + 72
                    : (MediaQuery.of(context).size.height * 0.23).clamp(
                        160.0,
                        210.0,
                      );
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: chipsBottom,
                  child: _buildPrepareBottomQuickChips(),
                );
              },
            ),

          // Plus menu replaced by AhviLensSheet (opened via onPlusTap)

          // ── Floating Prompt Bar ─────────────────────────────────────────────
          // Nav bar fixed గా ఉంటుంది — keyboard వచ్చినా move అవ్వదు
          // Prompt bar మాత్రమే keyboard పైకి లిఫ్ట్ అవుతుంది
          Builder(
            builder: (ctx) {
              // Read viewInsets directly — no ValueNotifier needed,
              // didChangeMetrics triggers a rebuild via setState anyway.
              final kbH = MediaQuery.of(ctx).viewInsets.bottom;
              final safeB = MediaQuery.paddingOf(ctx).bottom;
              final navBarTotalH = safeB + 86.0 + 8.0;
              final promptBottom = kbH > 0 ? kbH + 8.0 : navBarTotalH;
              return Positioned(
                left: 20,
                right: 20,
                bottom: promptBottom,
                // Wrap in MediaQuery with zeroed viewInsets so Flutter does NOT
                // call showOnScreen / scroll-to-visible when the TextField gets
                // focus — that was causing the whole page to jump to the top.
                child: MediaQuery(
                  data: MediaQuery.of(
                    ctx,
                  ).copyWith(viewInsets: EdgeInsets.zero),
                  child: _buildChatWrap(),
                ),
              );
            },
          ),

          // Only show nav bar when NOT inside a Shell (Shell has its own nav bar)
          // 🔧 FIX: Keyboard open అయినా nav bar same position లో ఉండాలి — hide చేయకూడదు
          if (widget.onShellNavTap == null)
            Builder(
              builder: (ctx) {
                final safeB = MediaQuery.paddingOf(ctx).bottom;
                return Positioned(
                  left: 16,
                  right: 16,
                  bottom: safeB + 8,
                  child: _buildBottomNav(),
                );
              },
            ),

          if (_seeAllOpen) _buildSeeAllPanel(),

          _buildComingSoonToast(),
        ],
      ),
    );
  }

  Widget _buildAuroraLayer() {
    // 🔧 FIX: RepaintBoundary తీసేశాం + colors ని builder లోపల
    // fresh గా read చేస్తున్నాం — palette switch అయినప్పుడు correct colors వస్తాయి
    return Positioned.fill(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _aurora1Ctrl,
            _aurora2Ctrl,
            _aurora3Ctrl,
          ]),
          builder: (context, _) {
            final t1 = _aurora1Ctrl.value;
            final t2 = _aurora2Ctrl.value;
            final t3 = _aurora3Ctrl.value;
            final tok = context.themeTokens;
            final c1 = tok.accent.primary;
            final c2 = tok.accent.secondary;
            final c3 = tok.accent.tertiary;
            return Stack(
              children: [
                Positioned(
                  top: -100 + (t1 * 90),
                  left: -80 + (t1 * 60),
                  child: _auroraOrb(340, 340, c1.withValues(alpha: 0.30)),
                ),
                Positioned(
                  bottom: -60 + (t2 * 60),
                  right: -60 + (t2 * 30),
                  child: _auroraOrb(300, 300, c2.withValues(alpha: 0.34)),
                ),
                Positioned(
                  top: 300 + (t3 * -60),
                  left: -40 + (t3 * 100),
                  child: _auroraOrb(220, 220, c3.withValues(alpha: 0.22)),
                ),
                Positioned(
                  top: 140 + (t1 * 80),
                  right: -30,
                  child: _auroraOrb(180, 180, c1.withValues(alpha: 0.18)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _auroraOrb(double w, double h, Color color) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final screenH = MediaQuery.of(context).size.height;
    final double topPad = screenH < 700 ? 6.0 : 10.0;
    final double botPad = screenH < 700 ? 4.0 : 6.0;
    final double logoFontSize = screenH < 700 ? 26.0 : 30.0;
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: botPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AhviHomeText(
            color: _textHeading,
            fontSize: logoFontSize,
            letterSpacing: 3.2,
            fontWeight: FontWeight.w400,
          ),
          _buildProfileAvatar(),
        ],
      ),
    );
  }

  // ── Fixed logo bar — stays put regardless of home collapse animation ──
  Widget _buildFixedLogoBar() {
    // Delegated to AhviHeader — same spacing on all screens, keyboard-safe
    return AhviHeader(frosted: false, right: _buildProfileAvatar());
  }

  Widget _buildProfileAvatar() {
    // ✅ FIX: ProfileController ని watch చేసి avatarPath directly వాడు
    // profile లో photo మారినప్పుడు ఇక్కడ automatically rebuild అవుతుంది
    final avatarPath = context
        .watch<profile.ProfileController>()
        .state
        .avatarPath;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context)
            .push(
              PageRouteBuilder<void>(
                transitionDuration: const Duration(milliseconds: 350),
                reverseTransitionDuration: const Duration(milliseconds: 350),
                pageBuilder: (context, animation, secondary) =>
                    const profile.ProfileScreen(),
                transitionsBuilder: (context, animation, secondary, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
              ),
            )
            .then((_) {
              // userName refresh కోసం మాత్రమే
              if (mounted) _fetchUserProfile();
            });
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _panel,
          border: Border.all(
            color: _accent.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _shadowMedium,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarPath != null && avatarPath.isNotEmpty
            ? Align(
                alignment: Alignment.center,
                child: Image.file(
                  File(avatarPath),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person_rounded,
                    size: 22,
                    color: _accent.withValues(alpha: 0.7),
                  ),
                ),
              )
            : _avatarBytes != null
            ? Align(
                alignment: Alignment.center,
                child: Image.memory(
                  _avatarBytes!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              )
            : Icon(
                Icons.person_rounded,
                size: 22,
                color: _accent.withValues(alpha: 0.7),
              ),
      ),
    );
  }

  Widget _buildGreetingBlock() {
    final screenH = MediaQuery.of(context).size.height;
    final double greetFontSize = screenH < 700 ? 20.0 : 24.0;
    final double botPad = screenH < 700 ? 4.0 : 6.0;
    return Padding(
      padding: EdgeInsets.only(bottom: botPad),
      child: ValueListenableBuilder<_ClockState>(
        valueListenable: _clockState,
        builder: (context, clock, _) {
          // 🆕 greeting key ని translate చేస్తున్నాం
          final greetingText = AppLocalizations.t(context, clock.greeting);

          // ProfileController నుండి name చదువు — onboarding లో enter చేసిన name వస్తుంది
          final profileName =
              context.watch<profile.ProfileController>().state.name ?? '';
          final displayName = profileName.isNotEmpty
              ? profileName.split(' ').first
              : _userName;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clock.date.isEmpty ? 'Fri, 6 Mar' : clock.date,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 3.0),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: greetFontSize,
                    fontWeight: FontWeight.w400,
                    color: _textHeading,
                    letterSpacing: -0.56,
                    height: 1.1,
                  ),
                  children: [
                    if (displayName.isNotEmpty) ...[
                      TextSpan(text: '$greetingText, '), // 🆕 translated
                      WidgetSpan(
                        child: _GradientText(
                          '$displayName.',
                          fontSize: greetFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ] else
                      TextSpan(
                        text: '$greetingText.',
                      ), // login కాలేదు — name లేదు
                  ],
                ),
              ),
              const SizedBox(height: 6.0),
              ValueListenableBuilder<_SuggestionState>(
                valueListenable: _suggestionState,
                builder: (context, suggestion, _) {
                  return _AnimatedPressable(
                    liftY: -1.5,
                    scalePressed: 0.98,
                    onTap: () =>
                        _openChatWithPrompt(_aiSuggestions[suggestion.index]),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface.withValues(alpha: 0.80),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                        boxShadow: [
                          BoxShadow(color: _shadowMedium, blurRadius: 10),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  _accent.withValues(alpha: 0.15),
                                  _accentTertiary.withValues(alpha: 0.15),
                                ],
                              ),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: ShaderMask(
                                shaderCallback: (b) =>
                                    _accentGradient.createShader(b),
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: _textHeading,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: suggestion.opacity,
                              duration: const Duration(milliseconds: 350),
                              child: Text(
                                // 🆕 suggestion key translate చేస్తున్నాం
                                AppLocalizations.t(
                                  context,
                                  _aiSuggestionKeys[suggestion.index],
                                ),
                                style: TextStyle(
                                  color: _textSub,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _accent.withValues(alpha: 0.65),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPromptChipsRow() {
    // 🆕 Chips localized
    final chips = [
      (
        '✦',
        AppLocalizations.t(context, 'chip_outfit_idea'),
        AppLocalizations.t(context, 'chip_prompt_outfit'),
      ),
      (
        '◎',
        AppLocalizations.t(context, 'chip_daily_plan'),
        AppLocalizations.t(context, 'chip_prompt_daily_plan'),
      ),
      (
        '⊹',
        AppLocalizations.t(context, 'chip_workout'),
        AppLocalizations.t(context, 'chip_prompt_workout'),
      ),
      (
        '◈',
        AppLocalizations.t(context, 'chip_meal_plan'),
        AppLocalizations.t(context, 'chip_prompt_meal_plan'),
      ),
      (
        '◷',
        AppLocalizations.t(context, 'chip_schedule'),
        AppLocalizations.t(context, 'chip_prompt_schedule'),
      ),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: chips.length,
        separatorBuilder: (_, i2) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return _AnimatedPressable(
            liftY: -2.0,
            scalePressed: 0.95,
            onTap: () => _openChatWithPrompt(chips[i].$3),
            child: Container(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(color: _shadowMedium, blurRadius: 8),
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (b) => _accentGradient.createShader(b),
                    child: Text(
                      chips[i].$1,
                      style: TextStyle(color: _textHeading, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    chips[i].$2,
                    style: TextStyle(
                      color: _textSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.01,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrepareBottomQuickChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        itemCount: _prepareChipKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          // 🆕 label localized, prompt English గా పంపుతున్నాం
          return _PrepareQuickChip(
            label: AppLocalizations.t(context, _prepareChipKeys[i].$1),
            onSend: () => _handlePrepareChipSend(_prepareChipKeys[i].$2),
            accent: _accent,
            accentSecondary: _accentSecondary,
            panel: _panel,
            border: _border,
            activeText: _textHeading,
            textMuted: _textMuted,
          );
        },
      ),
    );
  }

  Widget _buildHeroCard() {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmerCtrl, _breatheCtrl]),
        builder: (context, _) {
          final breatheOpacity = 0.14 + 0.12 * _breatheCtrl.value;

          return _CardPressable(
            onTap: () => _openModuleChat('style'),
            builder: (_) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: _surface,
                border: Border.all(
                  color: _accent.withValues(alpha: 0.20),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _shadowStrong,
                    blurRadius: 56,
                    offset: Offset(0, 16),
                  ),
                  BoxShadow(
                    color: _shadowMedium,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.12),
                    blurRadius: 30,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.8, 0.1),
                          radius: 1.2,
                          colors: [
                            _accentSecondary.withValues(alpha: 0.20),
                            _transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: _accent.withValues(alpha: breatheOpacity),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _transparent,
                            _accent.withValues(
                              alpha:
                                  0.6 *
                                  (0.5 +
                                      0.5 *
                                          math.sin(
                                            _shimmerCtrl.value * math.pi * 2,
                                          )),
                            ),
                            _accentTertiary.withValues(alpha: 0.55),
                            _transparent,
                          ],
                          stops: const [0.0, 0.28, 0.60, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 188,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.network(
                            'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=420&h=450&fit=crop&crop=top&auto=format',
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            cacheWidth:
                                (224 * MediaQuery.of(context).devicePixelRatio)
                                    .round(),
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_ctx, _err, _st) => Container(
                              color: _accent.withValues(alpha: 0.1),
                              child: Icon(Icons.image, color: _textMuted),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 56,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [_surface, _transparent],
                                stops: const [0.75, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 220,
                    child: LayoutBuilder(
                      builder: (context, heroConstraints) {
                        final heroH = heroConstraints.maxHeight;
                        // All values scale proportionally to available height
                        // heroH is typically 113–160px depending on device
                        final pad = (heroH * 0.11).clamp(8.0, 20.0);
                        final titleFontSize = (heroH * 0.21).clamp(18.0, 40.0);
                        final subtitleFontSize = (heroH * 0.065).clamp(
                          8.0,
                          12.0,
                        );
                        final gap1 = (heroH * 0.014).clamp(1.0, 4.0);
                        final gap2 = (heroH * 0.022).clamp(2.0, 7.0);
                        final btnPadH = (heroH * 0.088).clamp(8.0, 17.0);
                        final btnPadV = (heroH * 0.030).clamp(3.0, 9.0);
                        return ClipRect(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pad,
                              pad,
                              pad * 0.7,
                              pad * 0.7,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Expanded(
                                  child: OverflowBox(
                                    alignment: Alignment.topLeft,
                                    maxHeight: double.infinity,
                                    child: ClipRect(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            AppLocalizations.t(
                                              context,
                                              'hero_ai_stylist_label',
                                            ), // 🆕
                                            style: TextStyle(
                                              color: _accent.withValues(
                                                alpha: 0.85,
                                              ),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 1.4,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          SizedBox(height: gap1),
                                          ShaderMask(
                                            shaderCallback: (b) =>
                                                _accentGradient.createShader(b),
                                            child: Text(
                                              AppLocalizations.t(
                                                context,
                                                'hero_style_title',
                                              ), // 🆕
                                              style: TextStyle(
                                                color: _textHeading,
                                                fontSize: titleFontSize,
                                                fontWeight: FontWeight.w300,
                                                letterSpacing: -1.05,
                                                height: 0.93,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SizedBox(height: gap2),
                                          Text(
                                            AppLocalizations.t(
                                              context,
                                              'hero_style_subtitle',
                                            ), // 🆕
                                            style: TextStyle(
                                              color: _textSub.withValues(
                                                alpha: 0.80,
                                              ),
                                              fontSize: subtitleFontSize,
                                              fontWeight: FontWeight.w300,
                                              height: 1.4,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _AnimatedPressable(
                                  liftY: -2.0,
                                  scalePressed: 0.95,
                                  onTap: () => _openModuleChat('style'),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [_accent, _accentTertiary],
                                      ),
                                      borderRadius: BorderRadius.circular(100),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _accent.withValues(
                                            alpha: 0.40,
                                          ),
                                          blurRadius: 20,
                                          offset: const Offset(0, 6),
                                        ),
                                        BoxShadow(
                                          color: _accentTertiary.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: btnPadH,
                                      vertical: btnPadV,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppLocalizations.t(
                                            context,
                                            'hero_start_styling',
                                          ), // 🆕
                                          style: TextStyle(
                                            color: _onAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.36,
                                          ),
                                        ),
                                        SizedBox(width: 5),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          color: _onAccent,
                                          size: 11,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSecondaryRow() {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildSecCard(
            icon: Icons.grid_view_rounded,
            title: AppLocalizations.t(context, 'sec_plan_title'),
            subtitle: AppLocalizations.t(context, 'sec_plan_subtitle'),
            ctaKey: 'sec_plan_cta',
            intent: 'organize',
            assetImage: 'assets/images/plan_card.jpg',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSecCard(
            icon: Icons.calendar_month_outlined,
            title: AppLocalizations.t(context, 'sec_prep_title'),
            subtitle: AppLocalizations.t(context, 'sec_prep_subtitle'),
            ctaKey: 'sec_prep_cta',
            intent: 'plan',
            assetImage: 'assets/images/prep_card.jpg',
          ),
        ),
      ],
    );
  }

  Widget _buildSecCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String ctaKey,
    required String intent,
    String? imageUrl,
    String? assetImage,
  }) {
    final screenH = MediaQuery.of(context).size.height;
    // CTA label from localization key
    final ctaLabel = AppLocalizations.t(context, ctaKey);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmerCtrl, _breatheCtrl]),
        builder: (context, _) {
          // 🔧 Fresh read inside builder — palette switch అయినప్పుడు stale అవ్వవు
          final accentColor = context.themeTokens.accent.primary;
          final accentTertiary = context.themeTokens.accent.tertiary;
          final breatheOpacity = 0.10 + 0.10 * _breatheCtrl.value;
          final shimmerAlpha =
              0.5 + 0.5 * math.sin(_shimmerCtrl.value * math.pi * 2);

          return _CardPressable(
            onTap: () => _openModuleChat(intent),
            builder: (isHovered) {
              return Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.20),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _shadowMedium,
                      blurRadius: isHovered ? 52 : 28,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: isHovered ? 0.15 : 0.08,
                      ),
                      blurRadius: 20,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Radial glow background
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.8, -0.5),
                            radius: 1.4,
                            colors: [
                              accentColor.withValues(alpha: 0.18),
                              _transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Hero-card style: image on right, left-edge fade
                    if (assetImage != null || imageUrl != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 110,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: assetImage != null
                                  ? Image.asset(
                                      assetImage,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      filterQuality: FilterQuality.low,
                                      errorBuilder: (_ctx, _err, _st) =>
                                          const SizedBox.shrink(),
                                    )
                                  : Image.network(
                                      imageUrl!,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      cacheWidth:
                                          (130 *
                                                  MediaQuery.of(
                                                    context,
                                                  ).devicePixelRatio)
                                              .round(),
                                      filterQuality: FilterQuality.low,
                                      errorBuilder: (_ctx, _err, _st) =>
                                          const SizedBox.shrink(),
                                    ),
                            ),
                            // Left fade — blends into card surface
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [_surface, _transparent],
                                    stops: const [0.72, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Animated breathing border overlay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accentColor.withValues(
                                alpha: breatheOpacity,
                              ),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Shimmer top line
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _transparent,
                              accentColor.withValues(
                                alpha: 0.55 * shimmerAlpha,
                              ),
                              accentColor.withValues(alpha: 0.35),
                              _transparent,
                            ],
                            stops: const [0.0, 0.30, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Card content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // Limit text content width to not overlap the image (image width=110, fade=48)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(
                                          alpha: isHovered ? 0.16 : 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: accentColor.withValues(
                                            alpha: 0.18,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Icon(
                                        icon,
                                        color: isHovered
                                            ? accentColor
                                            : _textMuted,
                                        size: 18,
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: accentColor.withValues(
                                          alpha: isHovered ? 0.18 : 0.06,
                                        ),
                                        border: Border.all(
                                          color: accentColor.withValues(
                                            alpha: isHovered ? 0.30 : 0.15,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Transform.translate(
                                        offset: Offset(
                                          isHovered ? 2.0 : 0.0,
                                          0,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: isHovered
                                              ? accentColor
                                              : _textMuted,
                                          size: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: _textHeading,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: _textMuted,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w300,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Gradient CTA button — Daily Wear style (primary → tertiary)
                          _AnimatedPressable(
                            liftY: -2.0,
                            scalePressed: 0.95,
                            onTap: () => _openModuleChat(intent),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    accentColor,
                                    context.themeTokens.accent.tertiary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.40),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: context.themeTokens.accent.tertiary
                                        .withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    ctaLabel,
                                    style: TextStyle(
                                      color: _onAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.30,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _onAccent,
                                    size: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHead() {
    final screenH = MediaQuery.of(context).size.height;
    const double topPad = 18.0;
    const double botPad = 12.0;
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: botPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                AppLocalizations.t(context, 'picks_section_title'), // 🆕
                style: TextStyle(
                  color: _textHeading,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
                child: Text(
                  AppLocalizations.t(context, 'picks_ai_curated'), // 🆕
                  style: TextStyle(
                    color: _accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: _openSeeAll,
            child: Text(
              AppLocalizations.t(context, 'picks_see_all'), // 🆕
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicksStrip() {
    // 🆕 Picks localized
    final picks = [
      (
        AppLocalizations.t(context, 'pick_minimal_chic'),
        AppLocalizations.t(context, 'pick_minimal_chic_tag'),
        'https://images.unsplash.com/photo-1594938298603-c8148c4b9c2b?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_street_edit'),
        AppLocalizations.t(context, 'pick_street_edit_tag'),
        'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_office_look'),
        AppLocalizations.t(context, 'pick_office_look_tag'),
        'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_evening'),
        AppLocalizations.t(context, 'pick_evening_tag'),
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=220&h=260&fit=crop&crop=top&auto=format',
      ),
    ];
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    return SizedBox(
      height: isTablet
          ? (MediaQuery.of(context).size.height * 0.26).clamp(200.0, 280.0)
          : (MediaQuery.of(context).size.height * 0.22).clamp(150.0, 190.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: picks.length,
        separatorBuilder: (_, i2) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          return _buildPickCard(
            cardIdx: i,
            name: picks[i].$1,
            tag: picks[i].$2,
            imageUrl: picks[i].$3,
            liked: _likedState[i],
          );
        },
      ),
    );
  }

  Widget _buildPickCard({
    required int cardIdx,
    required String name,
    required String tag,
    required String imageUrl,
    required bool liked,
  }) {
    // Responsive card width: tablet=22%, phone=28%, clamped per form factor
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    final cardW = isTablet
        ? (screenW * 0.18).clamp(140.0, 200.0)
        : (screenW * 0.28).clamp(88.0, 130.0);
    return _AnimatedPressable(
      liftY: -4.0,
      scaleHover: 1.03,
      scalePressed: 0.97,
      onTap: () => _openPickSheet(name, tag),
      child: Container(
        width: cardW,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_surface, _bgSecondary],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border, width: 1),
          boxShadow: [
            BoxShadow(
              color: _shadowMedium,
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
            BoxShadow(color: _shadowLight, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth:
                          (112 * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_ctx, _err, _st) => Container(
                        color: _accent.withValues(alpha: 0.1),
                        child: Icon(Icons.image, color: _textMuted),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildLikeButton(cardIdx, liked),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _textHeading,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tag,
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikeButton(int cardIdx, bool liked) {
    return AnimatedBuilder(
      animation: _heartPopCtrls[cardIdx],
      builder: (context, _) {
        final t = _heartPopCtrls[cardIdx].value;
        double scale = 1.0;
        if (t < 0.40) {
          scale = 1.0 + (0.38 * (t / 0.40));
        } else if (t < 0.70) {
          scale = 1.38 - (0.50 * ((t - 0.40) / 0.30));
        } else {
          scale = 0.88 + (0.12 * ((t - 0.70) / 0.30));
        }
        return GestureDetector(
          onTap: () => _toggleLike(cardIdx),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: liked ? _accent.withValues(alpha: 0.20) : _shadowStrong,
                border: liked
                    ? Border.all(
                        color: _accent.withValues(alpha: 0.50),
                        width: 1,
                      )
                    : null,
              ),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked
                    ? _accentSecondary
                    : _textHeading.withValues(alpha: 0.7),
                size: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatWrap() {
    return AhviChatPromptBar(
      controller: _chatController,
      focusNode: _chatFocusNode,
      hintText: _chatPlaceholder,
      hasTextListenable: _chatController,
      surface: _surface,
      border: _border,
      accent: _accent,
      accentSecondary: _accentSecondary,
      textHeading: _textHeading,
      textMuted: _textMuted,
      shadowMedium: _shadowMedium,
      onAccent: _onAccent,
      onVoiceTap: _toggleListening,
      isListening: _isListening,
      // onPlusTap not set — widget opens lens sheet using its own Builder context
      padding: EdgeInsets.zero,
      onSendMessage: (text) {
        _chatFocusNode.unfocus();
        _openChatWithPrompt(text);
      },
      themeTokens: _t,
      onVisualSearch: () => _showComingSoon(),
      onFindSimilar: () => _showComingSoon(),
      onAddToWardrobe:
          null, // uses showAddToWardrobeModal default in lens sheet
    );
  }

  // ── ChatGPT-style plus menu ───────────────────────────────────────────────
  Widget _buildPlusMenu() {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // Position it just above the chat bar
    final menuBottom = safeBottom + 86.0 + 72.0 + 8.0;

    const menuItems = [
      (Icons.camera_alt_outlined, 'Camera', 'Take a photo'),
      (Icons.photo_library_outlined, 'Photo Library', 'Choose from gallery'),
      (Icons.insert_drive_file_outlined, 'Files', 'Upload a document'),
      (Icons.browse_gallery_outlined, 'Browse', 'Search the web'),
    ];

    return Positioned.fill(
      child: GestureDetector(
        onTap: _closePlusMenu,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned(
              left: 20,
              bottom: menuBottom,
              child: AnimatedBuilder(
                animation: _plusMenuCtrl,
                builder: (context, _) {
                  final t = _plusMenuCtrl.value;
                  return Transform.translate(
                    offset: Offset(0, 16 * (1 - t)),
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: GestureDetector(
                        onTap: () {}, // prevent tap-through
                        child: Container(
                          width: 220,
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.18),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _bgPrimary.withValues(alpha: 0.40),
                                blurRadius: 32,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.08),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(menuItems.length, (i) {
                              final item = menuItems[i];
                              final isLast = i == menuItems.length - 1;
                              return _PlusMenuItem(
                                icon: item.$1,
                                title: item.$2,
                                subtitle: item.$3,
                                accent: _accent,
                                accentSecondary: _accentSecondary,
                                textHeading: _textHeading,
                                textMuted: _textMuted,
                                panel: _panel,
                                border: _border,
                                showDivider: !isLast,
                                delayT: (i * 0.06).clamp(0.0, 0.3),
                                animT: t,
                                onTap: () {
                                  _closePlusMenu();
                                  _showComingSoon();
                                },
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    // 🆕 Nav labels localized
    final navLabelKeys = [
      'nav_home',
      'nav_wardrobe',
      'nav_planner',
      'nav_explore',
    ];
    final items = _homeNavItems;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;
    const double pillH = 62.0;
    const double maxBulge = 18.0;
    const double totalH = pillH + maxBulge + 6.0;
    const double iconContainerSize = 42.0;
    const double iconSize = 20.0;

    // On tablet, constrain nav to a max width and center it
    final navMaxW = isTablet ? 480.0 : double.infinity;

    return SizedBox(
      height: totalH,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: navMaxW),
          child: AnimatedBuilder(
            animation: Listenable.merge(_navRiseCtrls),
            builder: (context, _) {
              final activeIdx = _activeNavIdx;
              final bulgeT = _navRiseCtrls[activeIdx].value;

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: totalH,
                    child: CustomPaint(
                      painter: _NavPillPainter(
                        activeIdx: activeIdx,
                        itemCount: items.length,
                        bulgeT: bulgeT,
                        pillH: pillH,
                        maxBulge: maxBulge,
                        fillColor: _surface,
                        borderColor: _border,
                        glowColor: _accent,
                        shadowColor: _shadowMedium,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: pillH,
                    child: Row(
                      children: List.generate(items.length, (i) {
                        final active = activeIdx == i;
                        final rise = -10.0 * _navRiseCtrls[i].value;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _handleNavTap(i),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Transform.translate(
                                  offset: Offset(0, rise),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    width: iconContainerSize,
                                    height: iconContainerSize,
                                    decoration: active
                                        ? BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: _accentGradient2,
                                            boxShadow: [
                                              BoxShadow(
                                                color: _accent.withValues(
                                                  alpha: 0.45,
                                                ),
                                                blurRadius: 16,
                                                offset: const Offset(0, 4),
                                              ),
                                              BoxShadow(
                                                color: _accent.withValues(
                                                  alpha: 0.25,
                                                ),
                                                blurRadius: 28,
                                              ),
                                            ],
                                          )
                                        : null,
                                    child: Icon(
                                      items[i].icon,
                                      color: active ? _onAccent : _textMuted,
                                      size: active ? iconSize + 1 : iconSize,
                                    ),
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(0, rise),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    style: TextStyle(
                                      color: active ? _textHeading : _textMuted,
                                      fontSize: 10,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      letterSpacing: -0.01,
                                    ),
                                    // 🆕 label localized
                                    child: Text(
                                      AppLocalizations.t(
                                        context,
                                        navLabelKeys[i],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAiOverlay() {
    final screenH = MediaQuery.of(context).size.height;
    final bottomClearance = (screenH * 0.20).clamp(140.0, 190.0);
    final overlayTopOffset = (screenH * 0.072).clamp(50.0, 72.0);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _overlayFadeCtrl,
        builder: (context, _) => Opacity(
          opacity: _overlayFadeCtrl.value,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _dismissOverlay,
                  child: Container(color: _bgPrimary.withValues(alpha: 0.92)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomClearance,
                child: IgnorePointer(child: const SizedBox.expand()),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: overlayTopOffset,
                bottom: bottomClearance,
                child: Column(
                  children: [
                    Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (b) =>
                              _accentGradient.createShader(b),
                          child: Text(
                            'AHVI',
                            style: TextStyle(
                              color: _textHeading,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          // 🆕 brandSub ఇప్పుడు key — translate చేస్తున్నాం
                          AppLocalizations.t(context, _overlayBrandSub),
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _overlayScrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _EntryFadeSlide(
                          key: ValueKey(
                            '${_overlayState}_${_activeIntent ?? ''}',
                          ),
                          child: _buildOverlayContent(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent() {
    switch (_overlayState) {
      case _OverlayState.suggestions:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.t(context, 'overlay_suggested_for_you'), // 🆕
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(height: 8),
            ..._overlaySuggestions.map(
              (q) => _AnimatedPressable(
                scalePressed: 0.97,
                // 🆕 q ఇప్పుడు key — translate చేసి API కి పంపుతున్నాం
                onTap: () => _handleQuery(
                  AppLocalizations.t(context, q),
                  _activeIntent ?? 'chat',
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: _surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _border),
                    boxShadow: [BoxShadow(color: _shadowMedium, blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          AppLocalizations.t(context, q), // 🆕 translated
                          style: TextStyle(
                            color: _textSub,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

      case _OverlayState.thinking:
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _accent.withValues(alpha: 0.18),
                      _accentSecondary.withValues(alpha: 0.28),
                    ],
                  ),
                  border: Border.all(color: _accent.withValues(alpha: 0.30)),
                ),
                child: Center(
                  child: ShaderMask(
                    shaderCallback: (b) => _accentGradient.createShader(b),
                    child: Icon(
                      Icons.auto_awesome,
                      color: _textHeading,
                      size: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: _thinkingCtrl,
                builder: (_, __) {
                  Widget dot(int i) {
                    const period = 1.0;
                    const phaseShift = 0.125;
                    final t = (_thinkingCtrl.value + i * phaseShift) % period;
                    final sine = math.sin(t * math.pi * 2);
                    final lift = sine > 0 ? sine : 0.0;
                    final dy = -5.0 * lift;
                    final opacity = 0.3 + 0.7 * lift;
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 5.0 : 0),
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Opacity(
                          opacity: opacity.clamp(0.3, 1.0),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _accentGradient,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: _surface.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.10),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [dot(0), dot(1), dot(2)],
                    ),
                  );
                },
              ),
            ],
          ),
        );

      case _OverlayState.response:
        if (_responses.isEmpty) return const SizedBox();
        return Column(
          children: _responses.map((resp) {
            final isLast = resp == _responses.last;
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildResponseContent(
                resp,
                showTags: isLast && _tagsRevealed,
              ),
            );
          }).toList(),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildResponseContent(_ResponseData resp, {bool showTags = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: _phoneShell,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: _accent.withValues(alpha: 0.15)),
            ),
            child: Text(
              resp.question,
              style: TextStyle(
                color: _textHeading,
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    _accent.withValues(alpha: 0.18),
                    _accentSecondary.withValues(alpha: 0.28),
                  ],
                ),
                border: Border.all(color: _accent.withValues(alpha: 0.30)),
              ),
              child: Center(
                child: ShaderMask(
                  shaderCallback: (b) => _accentGradient.createShader(b),
                  child: Icon(
                    Icons.auto_awesome,
                    color: _textHeading,
                    size: 10,
                  ),
                ),
              ),
            ),
            Text(
              'AHVI',
              style: TextStyle(
                color: _textHeading,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (resp.intro.isNotEmpty) ...[
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 40,
            ),
            child: Text(
              resp.intro,
              style: TextStyle(
                color: _textSub,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _buildResponseBody(resp),

        if (showTags) ...[
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _tagsRevealCtrl,
            builder: (_, __) => Opacity(
              opacity: _tagsRevealCtrl.value,
              child: Transform.translate(
                offset: Offset(0, 7 * (1 - _tagsRevealCtrl.value)),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _responseTags
                      .map(
                        (tag) => _AnimatedPressable(
                          scalePressed: 0.96,
                          liftY: -1.5,
                          // 🆕 tag key translate చేసి submit చేస్తున్నాం
                          onTap: () => _submitQuery(_tagValue(tag)),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width - 60,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.20),
                              ),
                            ),
                            child: Text(
                              _tagText(tag),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildResponseBody(_ResponseData resp) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (resp.type) {
      case 'outfits':
        final outfitCardW = (MediaQuery.of(context).size.width * 0.22).clamp(
          76.0,
          96.0,
        );
        final outfitStripH = (MediaQuery.of(context).size.height * 0.185).clamp(
          138.0,
          168.0,
        );
        return SizedBox(
          height: outfitStripH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: resp.outfits.length,
            separatorBuilder: (_, i2) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final o = resp.outfits[i];
              return Container(
                width: outfitCardW,
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: outfitStripH * 0.62,
                      child: Image.network(
                        o.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        cacheWidth:
                            (outfitCardW *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        cacheHeight:
                            (outfitStripH *
                                    0.62 *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_ctx, _err, _st) =>
                            Container(color: _accent.withValues(alpha: 0.1)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.name,
                            style: TextStyle(
                              color: isDark ? _textHeading : _tileText,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 3,
                            children: o.tags
                                .map(
                                  (t) => Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 70,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      t,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _textMuted,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );

      case 'tasks':
        return Column(
          children: resp.tasks.map((t) {
            final dotColor = t.priority == 'high'
                ? _accent
                : t.priority == 'mid'
                ? _accentSecondary
                : _accentTertiary.withValues(alpha: 0.5);
            return Opacity(
              opacity: t.done ? 0.45 : 1.0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _border.withValues(alpha: 0.35)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: t.done
                              ? _accentTertiary.withValues(alpha: 0.5)
                              : _accent.withValues(alpha: 0.3),
                        ),
                        color: t.done
                            ? _accentTertiary.withValues(alpha: 0.15)
                            : _transparent,
                      ),
                      child: t.done
                          ? Icon(Icons.check, color: _accentTertiary, size: 10)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.label,
                            style: TextStyle(
                              color: t.done ? _textMuted : _textHeading,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: t.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.due,
                            style: TextStyle(
                              color: t.priority == 'high'
                                  ? _accentTertiary
                                  : _textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case 'week':
        return LayoutBuilder(
          builder: (context, constraints) {
            final itemCount = resp.weekDays.length;
            final rows = ((itemCount / 7).ceil()).clamp(1, 6);
            const spacing = 4.0;
            final cellWidth = (constraints.maxWidth - (6 * spacing)) / 7;
            final cellHeight = cellWidth / 0.52;
            final gridHeight = (rows * cellHeight) + ((rows - 1) * spacing);
            return SizedBox(
              height: gridHeight,
              child: GridView.builder(
                itemCount: itemCount,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: 0.52,
                ),
                itemBuilder: (_, index) {
                  final d = resp.weekDays[index];
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: d.isToday
                          ? _accent.withValues(alpha: 0.10)
                          : _bgPrimary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: d.isToday
                            ? _accent.withValues(alpha: 0.25)
                            : _border.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          d.day,
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            color: d.isToday ? _accent : _textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          d.label.split(' ').last,
                          style: TextStyle(fontSize: 6.5, color: _textMuted),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 3),
                        ...d.items
                            .take(2)
                            .map(
                              (it) => Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  it,
                                  style: TextStyle(
                                    fontSize: 5.5,
                                    color: _textSub,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );

      case 'plan':
        return Column(
          children: resp.planSections.map((s) {
            final c = s.color(context.themeTokens);
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: TextStyle(
                      color: c,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...s.items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        it,
                        style: TextStyle(
                          color: _textSub,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );

      case 'prepare_exact':
        return _buildPrepareExactChecklistCard(resp.question);

      case 'text':
      default:
        return const SizedBox();
    }
  }

  Widget _buildPrepareExactChecklistCard(String title) {
    final sections = [
      (
        name: 'Documents',
        emoji: '📄',
        color: _accentTertiary,
        items: [
          'Passport / ID',
          'Boarding pass',
          'Travel insurance',
          'Hotel confirmation',
          'Visa (if required)',
        ],
      ),
      (
        name: 'Tech & Power',
        emoji: '🔌',
        color: _accentSecondary,
        items: [
          'Phone + charger',
          'Power bank',
          'Headphones',
          'Laptop or tablet',
          'Universal adapter',
        ],
      ),
      (
        name: 'Comfort',
        emoji: '😴',
        color: _accent,
        items: [
          'Neck pillow',
          'Eye mask',
          'Earplugs',
          'Light jacket',
          'Compression socks',
        ],
      ),
    ];
    const sectionImages = [
      [
        'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1522199755839-a2bacb67c546?w=400&h=260&fit=crop&auto=format',
      ],
      [
        'https://images.unsplash.com/photo-1517336714739-489689fd1ca8?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1525547719571-a2d4ac8945e2?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1583394838336-acd977736f90?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1593344484962-796055d4a3a4?w=400&h=260&fit=crop&auto=format',
      ],
      [
        'https://images.unsplash.com/photo-1520006403909-838d6b92c22e?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1506485338023-6ce5f36692df?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=400&h=260&fit=crop&auto=format',
        'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=400&h=260&fit=crop&auto=format',
      ],
    ];

    final itemsState = _prepareExactItemsByTitle.putIfAbsent(
      title,
      () => sections.map((s) => List<String>.from(s.items)).toList(),
    );
    final addCtrls = _prepareExactAddControllersByTitle.putIfAbsent(
      title,
      () => List.generate(sections.length, (_) => TextEditingController()),
    );
    final checksState = _prepareExactChecksByTitle.putIfAbsent(
      title,
      () => itemsState
          .map(
            (items) => List<bool>.filled(items.length, false, growable: true),
          )
          .toList(),
    );
    final outfitSaved = _prepareExactOutfitSavedByTitle.putIfAbsent(
      title,
      () => List<bool>.filled(3, false, growable: true),
    );
    final isListSaved = _prepareExactSavedByTitle[title] ?? false;

    for (var i = 0; i < itemsState.length; i++) {
      final targetLen = itemsState[i].length;
      if (checksState[i].length < targetLen) {
        checksState[i].addAll(
          List<bool>.filled(
            targetLen - checksState[i].length,
            false,
            growable: true,
          ),
        );
      } else if (checksState[i].length > targetLen) {
        checksState[i] = checksState[i].sublist(0, targetLen);
      }
    }

    return StatefulBuilder(
      builder: (context, checklistSetState) {
        final totalItems = itemsState.fold<int>(
          0,
          (sum, items) => sum + items.length,
        );
        final totalChecked = checksState.fold<int>(
          0,
          (sum, items) => sum + items.where((v) => v).length,
        );
        final progress = totalItems == 0 ? 0.0 : totalChecked / totalItems;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border, width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: _phoneShell,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _textHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Generated for: $title',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$totalChecked of $totalItems items',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _border.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 400),
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(color: _accentTertiary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _border, width: 1)),
                  color: _panel,
                ),
                child: Column(
                  children: List.generate(sections.length, (sIdx) {
                    final s = sections[sIdx];
                    final doneCount = checksState[sIdx].where((v) => v).length;
                    return Container(
                      color: _phoneShell,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      margin: const EdgeInsets.only(bottom: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                s.emoji,
                                style: const TextStyle(fontSize: 15, height: 1),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  s.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _textHeading,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentTertiary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '$doneCount/${itemsState[sIdx].length}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _accentTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 64,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: sectionImages[sIdx].length,
                              itemExtent: 88,
                              itemBuilder: (_, imgIdx) {
                                final img = sectionImages[sIdx][imgIdx];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    right:
                                        imgIdx == sectionImages[sIdx].length - 1
                                        ? 0
                                        : 8,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _border),
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    child: Image.network(
                                      img,
                                      fit: BoxFit.cover,
                                      cacheWidth: 264,
                                      cacheHeight: 192,
                                      errorBuilder: (_ctx, _err, _st) =>
                                          Container(
                                            color: _panel,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.image_outlined,
                                              size: 16,
                                              color: _textMuted,
                                            ),
                                          ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(itemsState[sIdx].length, (i) {
                            final done = checksState[sIdx][i];
                            return GestureDetector(
                              onTap: () => checklistSetState(
                                () => checksState[sIdx][i] = !done,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  border: i < itemsState[sIdx].length - 1
                                      ? Border(
                                          bottom: BorderSide(
                                            color: _border.withValues(
                                              alpha: 0.85,
                                            ),
                                            width: 1,
                                          ),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: done ? s.color : _border,
                                          width: 1.5,
                                        ),
                                        color: done ? s.color : _panel,
                                      ),
                                      alignment: Alignment.center,
                                      child: done
                                          ? const Icon(
                                              Icons.check,
                                              size: 11,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        itemsState[sIdx][i],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: done
                                              ? _textMuted
                                              : _textHeading,
                                          decoration: done
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        checklistSetState(() {
                                          itemsState[sIdx].removeAt(i);
                                          checksState[sIdx].removeAt(i);
                                        });
                                      },
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Center(
                                          child: Text(
                                            '×',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: _textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _bgSecondary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: addCtrls[sIdx],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _textHeading,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '+ Add item…',
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _textMuted,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) {
                                      final val = addCtrls[sIdx].text.trim();
                                      if (val.isEmpty) return;
                                      checklistSetState(() {
                                        itemsState[sIdx].add(val);
                                        checksState[sIdx].add(false);
                                        addCtrls[sIdx].clear();
                                      });
                                    },
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    final val = addCtrls[sIdx].text.trim();
                                    if (val.isEmpty) return;
                                    checklistSetState(() {
                                      itemsState[sIdx].add(val);
                                      checksState[sIdx].add(false);
                                      addCtrls[sIdx].clear();
                                    });
                                  },
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: s.color,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '+',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF10131B),
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              Container(
                color: _phoneShell,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: IgnorePointer(
                  ignoring: isListSaved,
                  child: GestureDetector(
                    onTap: () {
                      const boards = [
                        '🎉 Party Looks',
                        '💍 Occasion',
                        '💼 Office Fit',
                        '✈️ Vacation',
                        '✨ Everything Else',
                      ];
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => Container(
                          decoration: BoxDecoration(
                            color: _bgSecondary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: _border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Save to a Style Board',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _textHeading,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose where this checklist lives',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...boards.map(
                                (label) => GestureDetector(
                                  onTap: () async {
                                    final boardId = _boardIdByLabel[label];
                                    if (boardId == null) {
                                      Navigator.pop(context);
                                      return;
                                    }
                                    Navigator.pop(context);
                                    await _savePrepareExactToBoard(
                                      boardId: boardId,
                                      title: title,
                                      sections: sections,
                                      itemsState: itemsState,
                                      checksState: checksState,
                                      outfitSaved: outfitSaved,
                                    );
                                    if (!mounted) return;
                                    checklistSetState(
                                      () => _prepareExactSavedByTitle[title] =
                                          true,
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _panel,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: _border,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: _textHeading,
                                            ),
                                          ),
                                        ),
                                        if (label.contains('Vacation'))
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _accentSecondary,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                            child: const Text(
                                              'SUGGESTED',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: isListSaved
                            ? LinearGradient(colors: [_accent, _accentTertiary])
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_accent, _accentTertiary],
                              ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isListSaved ? '✅' : '📌',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isListSaved ? 'List Saved!' : 'Save to Style Board',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _onAccent,
                              letterSpacing: 0.14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPickSheet({
    required String name,
    required String tag,
    required VoidCallback onClose,
  }) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_surface, _bgSecondary],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: _accent.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              40 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  name,
                  style: TextStyle(
                    color: _textHeading,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tag,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedPressable(
                        scalePressed: 0.97,
                        onTap: onClose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.20),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Save to Board',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedPressable(
                        scalePressed: 0.97,
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: _accentGradient2,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.35),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Style This ?',
                              style: TextStyle(
                                color: _onAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeeAllPanel() {
    // 🆕 seeAll picks localized
    final seeAllPicks = [
      (
        AppLocalizations.t(context, 'pick_minimal_chic'),
        AppLocalizations.t(context, 'pick_minimal_chic_tag'),
        'https://images.unsplash.com/photo-1594938298603-c8148c4b9c2b?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_street_edit'),
        AppLocalizations.t(context, 'pick_street_edit_tag'),
        'https://images.unsplash.com/photo-1509631179647-0177331693ae?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_office_look'),
        AppLocalizations.t(context, 'pick_office_look_tag'),
        'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        AppLocalizations.t(context, 'pick_evening'),
        AppLocalizations.t(context, 'pick_evening_tag'),
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        'Athleisure',
        'Sport · Morning',
        'https://images.unsplash.com/photo-1538805060514-97d9cc17730c?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
      (
        'Resort Wear',
        'Vacation · Breezy',
        'https://images.unsplash.com/photo-1469334031218-e382a71b716b?w=300&h=280&fit=crop&crop=top&auto=format',
      ),
    ];
    return AnimatedBuilder(
      animation: _seeAllCtrl,
      builder: (context, _) {
        final slideOffset = (1.0 - _seeAllCtrl.value);
        return Transform.translate(
          offset: Offset(MediaQuery.of(context).size.width * slideOffset, 0),
          child: Container(
            color: _bgPrimary,
            child: Column(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _closeSeeAll,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _panel,
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.20),
                                width: 1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: _textMuted,
                              size: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.t(
                            context,
                            'picks_section_title',
                          ), // 🆕
                          style: TextStyle(
                            color: _textHeading,
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: seeAllPicks.length,
                    itemBuilder: (context, i) {
                      return RepaintBoundary(
                        child: _AnimatedPressable(
                          scalePressed: 0.97,
                          onTap: () {
                            _closeSeeAll();
                            Future.delayed(
                              const Duration(milliseconds: 380),
                              () {
                                if (mounted) {
                                  _openPickSheet(
                                    seeAllPicks[i].$1,
                                    seeAllPicks[i].$2,
                                  );
                                }
                              },
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: _surface,
                              border: Border.all(color: _border, width: 1),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Image.network(
                                    seeAllPicks[i].$3,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    cacheWidth:
                                        (240 *
                                                MediaQuery.of(
                                                  context,
                                                ).devicePixelRatio)
                                            .round(),
                                    filterQuality: FilterQuality.low,
                                    errorBuilder: (_ctx, _err, _st) =>
                                        Container(
                                          color: _accent.withValues(alpha: 0.1),
                                          child: Icon(
                                            Icons.image,
                                            color: _textMuted,
                                          ),
                                        ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        seeAllPicks[i].$1,
                                        style: TextStyle(
                                          color: _textHeading,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        seeAllPicks[i].$2,
                                        style: TextStyle(
                                          color: _textMuted,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComingSoonToast() {
    final screenH = MediaQuery.of(context).size.height;
    return Positioned(
      bottom: 110.0,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _toastVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: AnimatedSlide(
            offset: _toastVisible ? Offset.zero : const Offset(0, 0.3),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _bgSecondary.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [BoxShadow(color: _shadowMedium, blurRadius: 28)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_rounded, color: _accent, size: 15),
                    SizedBox(width: 7),
                    Text(
                      AppLocalizations.t(context, 'coming_soon'), // 🆕
                      style: TextStyle(
                        color: _textHeading,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Plus Menu Item ────────────────────────────────────────────────────────────
class _PlusMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accentSecondary;
  final Color textHeading;
  final Color textMuted;
  final Color panel;
  final Color border;
  final bool showDivider;
  final double delayT;
  final double animT;
  final VoidCallback? onTap;

  const _PlusMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentSecondary,
    required this.textHeading,
    required this.textMuted,
    required this.panel,
    required this.border,
    required this.showDivider,
    required this.delayT,
    required this.animT,
    this.onTap,
  });

  @override
  State<_PlusMenuItem> createState() => _PlusMenuItemState();
}

class _PlusMenuItemState extends State<_PlusMenuItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Staggered per-item fade: each item fades in slightly after the previous
    final itemT = ((widget.animT - widget.delayT) / (1.0 - widget.delayT))
        .clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _pressed
                ? widget.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Opacity(
              opacity: itemT,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - itemT)),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.accent.withValues(alpha: 0.20),
                          width: 1,
                        ),
                      ),
                      child: Icon(widget.icon, color: widget.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: widget.textHeading,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              color: widget.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: widget.border.withValues(alpha: 0.6),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _NavPillPainter extends CustomPainter {
  final int activeIdx;
  final int itemCount;
  final double bulgeT;
  final double pillH;
  final double maxBulge;
  final Color fillColor;
  final Color borderColor;
  final Color glowColor;
  final Color shadowColor;

  const _NavPillPainter({
    required this.activeIdx,
    required this.itemCount,
    required this.bulgeT,
    required this.pillH,
    required this.maxBulge,
    required this.fillColor,
    required this.borderColor,
    required this.glowColor,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pillTop = h - pillH;
    final r = pillH / 2;

    final itemW = w / itemCount;
    final cx = itemW * activeIdx + itemW / 2;

    final bulgeH = maxBulge * bulgeT;
    final peakY = pillTop - bulgeH;

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, pillTop, w, pillH),
      Radius.circular(r),
    );
    final pillPath = Path()..addRRect(pillRect);

    final hw = itemW * 0.38;
    final tang = hw * 0.55;
    final lx = cx - hw;
    final rx = cx + hw;

    final bp = Path();
    bp.moveTo(lx, pillTop);
    bp.cubicTo(lx + tang, pillTop, cx - tang, peakY, cx, peakY);
    bp.cubicTo(cx + tang, peakY, rx - tang, pillTop, rx, pillTop);
    bp.close();

    final combined = Path.combine(PathOperation.union, pillPath, bp);

    canvas.drawPath(
      combined.shift(const Offset(0, 8)),
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    if (bulgeH > 1) {
      canvas.drawPath(
        combined,
        Paint()
          ..color = glowColor.withValues(alpha: 0.12 * bulgeT)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    canvas.drawPath(combined, Paint()..color = fillColor);

    canvas.drawPath(
      combined,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_NavPillPainter old) =>
      old.activeIdx != activeIdx ||
      old.bulgeT != bulgeT ||
      old.fillColor != fillColor ||
      old.shadowColor != shadowColor ||
      old.glowColor != glowColor ||
      old.borderColor != borderColor;
}

enum _OverlayState { idle, suggestions, thinking, response }

class _IntentConfig {
  final List<String> suggestions;
  final String brandSub;
  final List<String> responseTags;
  const _IntentConfig({
    required this.suggestions,
    required this.brandSub,
    required this.responseTags,
  });
}

class _ResponseData {
  final String type, question, intro;
  final List<_Outfit> outfits;
  final List<_Task> tasks;
  final List<_WeekDay> weekDays;
  final List<_PlanSection> planSections;
  const _ResponseData({
    required this.type,
    required this.question,
    this.intro = '',
    this.outfits = const [],
    this.tasks = const [],
    this.weekDays = const [],
    this.planSections = const [],
  });
}

class _Outfit {
  final String name, imageUrl;
  final List<String> tags;
  const _Outfit(this.name, this.tags, this.imageUrl);
}

class _Task {
  final String label, due, priority;
  final bool done;
  const _Task(this.label, this.due, this.priority, this.done);
}

class _WeekDay {
  final String day, label;
  final List<String> items;
  final bool done, isToday;
  const _WeekDay(
    this.day,
    this.label,
    this.items, {
    this.done = false,
    this.isToday = false,
  });
}

class _PlanSection {
  final String title;
  final Color Function(AppThemeTokens) color;
  final List<String> items;
  const _PlanSection(this.title, this.color, this.items);
}

// 🆕 Intent config ఇప్పుడు localization keys use చేస్తోంది
// Runtime లో AppLocalizations.t() తో translate అవుతాయి
const _intentConfig = {
  'style': _IntentConfig(
    suggestions: ['intent_style_s1', 'intent_style_s2', 'intent_style_s3'],
    brandSub: 'intent_style_sub',
    responseTags: [
      'intent_style_tag1',
      'intent_style_tag2',
      'intent_style_tag3',
    ],
  ),
  'organize': _IntentConfig(
    suggestions: [
      'intent_organize_s1',
      'intent_organize_s2',
      'intent_organize_s3',
      'intent_organize_s4',
      'intent_organize_s5',
      'intent_organize_s6',
      'intent_organize_s7',
      'intent_organize_s8',
    ],
    brandSub: 'intent_organize_sub',
    responseTags: [],
  ),
  'prepare': _IntentConfig(
    suggestions: [
      'intent_prepare_s1',
      'intent_prepare_s2',
      'intent_prepare_s3',
    ],
    brandSub: 'intent_prepare_sub',
    responseTags: [
      'intent_prepare_tag1',
      'intent_prepare_tag2',
      'intent_prepare_tag3',
    ],
  ),
  'chat': _IntentConfig(
    suggestions: ['intent_chat_s1', 'intent_chat_s2', 'intent_chat_s3'],
    brandSub: 'intent_chat_sub',
    responseTags: ['intent_chat_tag1', 'intent_chat_tag2', 'intent_chat_tag3'],
  ),
};

// 🆕 _intentPlaceholder ఇప్పుడు JSON keys — AppLocalizations.t() తో translate అవుతాయి
// placeholder_chat, placeholder_style, placeholder_organize, placeholder_prepare
// _setPlaceholder('chat') → 'placeholder_chat' → JSON లో translate అవుతుంది

class _GradientText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;

  const _GradientText(
    this.text, {
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.accent.primary, t.accent.tertiary],
      ).createShader(bounds),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: -0.56,
          height: 1.1,
        ),
      ),
    );
  }
}

class _EntryFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double dy;
  final Duration delay;

  const _EntryFadeSlide({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOut,
    this.dy = 24.0,
    this.delay = Duration.zero,
  });

  @override
  State<_EntryFadeSlide> createState() => _EntryFadeSlideState();
}

class _EntryFadeSlideState extends State<_EntryFadeSlide> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double h = constraints.biggest.height;
        if (h == 0 || h == double.infinity) {
          h = MediaQuery.of(context).size.height;
        }

        final frac = widget.dy / h;
        return AnimatedOpacity(
          opacity: _show ? 1.0 : 0.0,
          duration: widget.duration,
          curve: widget.curve,
          child: AnimatedSlide(
            offset: _show ? Offset.zero : Offset(0, frac),
            duration: widget.duration,
            curve: widget.curve,
            child: widget.child,
          ),
        );
      },
    );
  }
}

const _cardTapDuration = Duration(milliseconds: 200);
const _cardTapCurve = Cubic(0.34, 1.56, 0.64, 1.0);

class _CardPressable extends StatefulWidget {
  final Widget Function(bool isHovered) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final Offset pressedOffset;

  const _CardPressable({
    required this.builder,
    this.onTap,
    this.pressedScale = 0.97,
    this.pressedOffset = Offset.zero,
  });

  @override
  State<_CardPressable> createState() => _CardPressableState();
}

class _CardPressableState extends State<_CardPressable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedSlide(
          offset: _pressed ? widget.pressedOffset : Offset.zero,
          duration: _cardTapDuration,
          curve: _cardTapCurve,
          child: AnimatedScale(
            scale: _pressed ? widget.pressedScale : 1.0,
            duration: _cardTapDuration,
            curve: _cardTapCurve,
            child: widget.builder(_hovered),
          ),
        ),
      ),
    );
  }
}

class _PrepareQuickChip extends StatefulWidget {
  final String label;
  final VoidCallback onSend;
  final Color accent;
  final Color accentSecondary;
  final Color panel;
  final Color border;
  final Color activeText;
  final Color textMuted;

  const _PrepareQuickChip({
    required this.label,
    required this.onSend,
    required this.accent,
    required this.accentSecondary,
    required this.panel,
    required this.border,
    required this.activeText,
    required this.textMuted,
  });

  @override
  State<_PrepareQuickChip> createState() => _PrepareQuickChipState();
}

class _PrepareQuickChipState extends State<_PrepareQuickChip> {
  bool _active = false;
  bool _hovered = false;

  void _activateAndSend() {
    setState(() => _active = true);
    widget.onSend();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _active = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered && !_active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _activateAndSend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: _active
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [widget.accent, widget.accentSecondary],
                  )
                : null,
            color: _active
                ? null
                : hovered
                ? widget.accent.withValues(alpha: 0.15)
                : widget.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _active
                  ? Colors.transparent
                  : hovered
                  ? widget.accent.withValues(alpha: 0.5)
                  : widget.border,
              width: 1.5,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _active
                  ? widget.activeText
                  : hovered
                  ? widget.accent
                  : widget.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedPressable extends StatefulWidget {
  final Widget? child;
  final Widget Function(bool isHovered, bool isPressed)? builder;
  final VoidCallback? onTap;
  final double liftY;
  final double scaleHover;
  final double scalePressed;

  const _AnimatedPressable({
    this.child,
    this.builder,
    this.onTap,
    this.liftY = 0.0,
    this.scaleHover = 1.0,
    this.scalePressed = 0.97,
  }) : assert(child != null || builder != null);

  @override
  State<_AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<_AnimatedPressable> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    double scale = 1.0;
    double dy = 0.0;
    if (_isPressed) {
      scale = widget.scalePressed;
    } else if (_isHovered) {
      scale = widget.scaleHover;
      dy = -widget.liftY;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: _isPressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 340),
          curve: _isPressed
              ? const Cubic(0.4, 0.0, 1.0, 1.0)
              : const Cubic(0.34, 1.40, 0.64, 1.0),
          transform: Matrix4.translationValues(0.0, _isPressed ? 0.0 : dy, 0.0)
            ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0)),
          transformAlignment: Alignment.center,
          child: widget.builder != null
              ? widget.builder!(_isHovered, _isPressed)
              : widget.child!,
        ),
      ),
    );
  }
}

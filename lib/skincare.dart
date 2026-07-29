import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/theme/theme_controller.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:myapp/widgets/ahvi_lens_sheet.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  BEHAVIORAL DIFF ANALYSIS REPORT
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//
// PHASE 1 â€” STRUCTURAL SCAN SUMMARY
//
// CSS Transitions / Animations found:
//   â€¢ .back-btn:hover              â†’ scale(1.06) translateX(-1px), 0.2s
//   â€¢ .step                        â†’ @keyframes slideUp (opacity 0â†’1, translateY 16pxâ†’0), 0.35s, staggered delay i*0.06s
//   â€¢ .step:hover                  â†’ translateY(-3px), 0.28s
//   â€¢ .progress-fill               â†’ width transition, 0.5s cubic-bezier(.25,.8,.25,1)
//   â€¢ .chat-btn:hover              â†’ translateY(-2px), 0.25s cubic-bezier(0.34,1.56,0.64,1)
//   â€¢ .chat-btn-pulse              â†’ @keyframes pulse (scale 1â†’1.04, opacity 0.6â†’0), 2.5s infinite
//   â€¢ .chat-overlay                â†’ opacity 0â†’1, 0.3s  +  .chat-modal translateY(100%)â†’0, 0.42s
//   â€¢ .qpill:active                â†’ gradient fill flash
//   â€¢ .send-btn:active             â†’ scale(0.9), 0.2s
//   â€¢ .send-btn:disabled           â†’ opacity 0.28
//   â€¢ .mic-btn.listening           â†’ gradient bg + @keyframes micPulse scale 1â†’1.08, 1.2s infinite
//   â€¢ .typing-dot                  â†’ @keyframes typBounce translateY(0â†’-5pxâ†’0) + color change, 1.2s staggered
//   â€¢ .msg-row                     â†’ @keyframes slideUp on each new message
//   â€¢ .chat-input-wrap:focus-within â†’ border-color accent blue
//
// JS Behaviors found:
//   â€¢ openChat()        â†’ on chat-btn click, adds .open to overlay (opacity + slide modal up), auto-sends welcome AI msg
//   â€¢ closeChat()       â†’ removes .open (fade + slide down)
//   â€¢ sendMsg()         â†’ real Anthropic API call with conversation history + skin context, disables send-btn while busy
//   â€¢ sendQ(btn)        â†’ quick-pill click fills input and calls sendMsg(), hides quick-pills after first send
//   â€¢ chatKey(e)        â†’ Enter key (no shift) submits message
//   â€¢ autoResize(el)    â†’ textarea auto-resizes up to 120px height
//   â€¢ toggleVoice()     â†’ SpeechRecognition toggle; mic-btn gets .listening class (gradient + micPulse animation)
//   â€¢ renderSteps()     â†’ re-renders step cards with slideUp animation and staggered delay on routine change
//   â€¢ markStep(el)      â†’ one-way toggle done state, increments counter
//   â€¢ getCtx()          â†’ builds system prompt context from current skin/concern/routine state
//
// PHASE 2 â€” INTERACTION EXTRACTION
//
// F01 | .back-btn        | hover      | CSS  | scale(1.06) + translateX(-1px) | transform | 0.2s
// F02 | .step (each)     | render     | CSS  | slideUp (opacity+translateY)   | keyframe  | 0.35s + stagger i*0.06s
// F03 | .step            | hover      | CSS  | translateY(-3px)              | transform | 0.28s
// F04 | .progress-fill   | state change| CSS | width 0â†’pct%                  | layout    | 0.5s cubic
// F05 | .chat-btn        | hover      | CSS  | translateY(-2px) + shadow     | transform | 0.25s spring
// F06 | .chat-btn-pulse  | always     | CSS  | scale + opacity loop          | keyframe  | 2.5s infinite
// F07 | .chat-overlay    | openChat() | JS   | opacity 0â†’1 + modal slide up  | combined  | 0.3s / 0.42s
// F08 | .send-btn        | tap        | CSS  | scale(0.9)                    | transform | 0.2s
// F09 | .send-btn        | busy       | CSS  | opacity 0.28                  | opacity   | instant
// F10 | .mic-btn         | listening  | CSS  | gradient + scale pulse 1.08   | keyframe  | 1.2s infinite
// F11 | .typing-dot      | visible    | CSS  | bounce Y-5px + color accent   | keyframe  | 1.2s staggered
// F12 | .msg-row         | added      | CSS  | slideUp per message           | keyframe  | 0.32s
// F13 | sendMsg()        | tap send   | JS   | real Anthropic API, history   | network   | async
// F14 | sendQ()          | pill tap   | JS   | fill input + sendMsg()        | state     | instant
// F15 | chatKey()        | keyboard   | JS   | Enter submits                 | event     | instant
// F16 | toggleVoice()    | mic tap    | JS   | SpeechRecognition + listening | state     | instant
// F17 | quick-pills hide | first send | JS   | pills disappear               | state     | instant
// F18 | welcome AI msg   | openChat() | JS   | AI sends greeting 400ms delay | async     | 400ms delay
// F19 | chat-input focus | tap input  | CSS  | border-color accent 0.45      | border    | instant
// F20 | renderSteps      | toggle     | JS   | re-render + slideUp stagger   | combined  | on switch
//
// PHASE 3 â€” FLUTTER COMPARISON
//
// F01 back-btn hover          â†’ MISSING   (MouseRegion not used; no scale/translate effect)
// F02 step slideUp on render  â†’ MISSING   (AnimationController per step with stagger not present)
// F03 step hover lift         â†’ MISSING   (No MouseRegion/hover on step cards)
// F04 progress width anim     â†’ PARTIAL   (FractionallySizedBox used but no explicit curve/duration)
// F05 chat-btn hover lift     â†’ MISSING   (No MouseRegion on chat button)
// F06 chat-btn pulse ring     â†’ MISSING   (Pulse animation widget absent)
// F07 chat overlay slide+fade â†’ PARTIAL   (SlideTransition present; backdrop opacity fade MISSING)
// F08 send-btn tap scale      â†’ MISSING   (GestureDetector present but no scale feedback)
// F09 send-btn disabled opacityâ†’ MISSING  (No opacity change when _isBusy)
// F10 mic listening pulse     â†’ MISSING   (No animation when listening; no state change in Flutter)
// F11 typing dot color change â†’ PARTIAL   (Bounce present; color transition at peak MISSING)
// F12 msg-row slideUp         â†’ MISSING   (New messages appear without slideUp animation)
// F13 real Anthropic API call â†’ MISSING   (Fallback tips only; no real HTTP call, no history, no context)
// F14 quick-pill sends text   â†’ IMPLEMENTED
// F15 Enter key submit        â†’ IMPLEMENTED (onSubmitted)
// F16 voice / mic toggle      â†’ MISSING   (mic button is static; no speech recognition)
// F17 quick-pills hide        â†’ IMPLEMENTED
// F18 welcome AI greeting     â†’ MISSING   (static welcome widget; no AI-generated greeting on open)
// F19 input focus border      â†’ MISSING   (no FocusNode border change)
// F20 step re-render stagger  â†’ MISSING   (steps re-render but no slideUp stagger on routine switch)
//
// PHASE 4 â€” FLUTTER IMPLEMENTATION PLAN
//
// F01 â†’ MouseRegion + AnimatedContainer (scale + translateX)
// F02 â†’ Per-step AnimationController list rebuilt on routine change, staggered forward()
// F03 â†’ MouseRegion(_hovering) + AnimatedContainer translateY on each step card
// F04 â†’ AnimatedFractionallySizedBox or TweenAnimationBuilder with cubic curve 0.5s
// F05 â†’ MouseRegion + AnimatedContainer translateY on chat button
// F06 â†’ AnimationController.repeat() + ScaleTransition + FadeTransition pulse ring
// F07 â†’ AnimatedOpacity for backdrop + existing SlideTransition (already present)
// F08 â†’ GestureDetector onTapDown/onTapUp + AnimatedScale
// F09 â†’ AnimatedOpacity wrapping send button, opacity driven by _isBusy
// F10 â†’ AnimationController.repeat() in _ChatOverlayState, driven by _isListening
// F11 â†’ Tween color at peak via ColorTween in _TypingDotState
// F12 â†’ Wrap each new message row in a _SlideUpMessage widget with its own controller
// F13 â†’ http.post to Anthropic API, maintain List<Map> _chatHistory, use getCtx() system prompt
// F16 â†’ voice input placeholder (graceful no-op if unavailable; visual state only)
// F18 â†’ openChat triggers Future.delayed(400ms) â†’ sendMessage with empty trigger â†’ AI greeting
// F19 â†’ FocusNode + AnimatedContainer border color
// F20 â†’ _rebuildStepAnimations() called in _setRoutine()
//
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Color constants
AppThemeTokens? _skinTokens;
void _setSkinTokens(AppThemeTokens t) => _skinTokens = t;
AppThemeTokens get _t => _skinTokens!;

Color get _bg => _t.backgroundPrimary;
Color get _bg2 => _t.backgroundSecondary;
Color get _panel => _t.panel;
Color get _panel2 => _t.panelBorder;
Color get _card => _t.card;
Color get _cardBorder => _t.cardBorder;
Color get _text => _t.textPrimary;
Color get _muted => _t.mutedText;
Color get _tileText => _t.tileText;
Color get _accent => _t.accent.primary;
Color get _accent2 => _t.accent.secondary;
Color get _accent3 => _t.accent.tertiary;
Color get _accent4 => Color.lerp(_accent, _accent2, 0.55)!;
Color get _accent5 => Color.lerp(_accent2, _accent3, 0.55)!;
Color get _phoneShell => _t.phoneShell;
Color get _phoneShell2 => _t.phoneShellInner;
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Data
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _dayRoutineKeys = [
  'skin_cleanser',
  'skin_toner',
  'skin_vitamin_c',
  'skin_moisturizer',
  'skin_sunscreen',
];
const _nightRoutineKeys = [
  'skin_cleanser',
  'skin_toner',
  'skin_retinol',
  'skin_night_cream',
  'skin_lip_care',
];

List<Color> get _stepColors => [
  _accent,
  _accent4,
  _accent2,
  _accent3,
  _accent5,
];
List<Color> get _stepBgColors => [
  _accent.withValues(alpha: 0.15),
  _accent4.withValues(alpha: 0.15),
  _accent2.withValues(alpha: 0.15),
  _accent3.withValues(alpha: 0.12),
  _accent5.withValues(alpha: 0.12),
];
List<Color> get _stepBorderColors => [
  _accent.withValues(alpha: 0.25),
  _accent4.withValues(alpha: 0.25),
  _accent2.withValues(alpha: 0.25),
  _accent3.withValues(alpha: 0.22),
  _accent5.withValues(alpha: 0.22),
];

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Main Screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class SkincareScreen extends StatefulWidget {
  const SkincareScreen({super.key});
  @override
  State<SkincareScreen> createState() => _SkincareScreenState();
}

class _SkincareScreenState extends State<SkincareScreen>
    with TickerProviderStateMixin {
  bool _isNight = false;
  String _skinType = '';
  List<String> _concerns = [];
  Set<int> _dayCompletedSteps = {};
  Set<int> _nightCompletedSteps = {};
  bool _chatOpen = false;
  String? _profileDocumentId;
  bool _profileLoading = false;

  // â”€â”€ F01: back-btn hover state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // â”€â”€ F06: chat-btn pulse animation controller â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  // â”€â”€ F05: chat-btn hover state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final bool _chatBtnHovered = false;

  // â”€â”€ F02/F20: per-step slide-up controllers (rebuilt on routine toggle) â”€â”€â”€â”€â”€
  late List<AnimationController> _stepAnimCtrls;
  late List<Animation<double>> _stepSlideAnims;
  late List<Animation<double>> _stepFadeAnims;

  // Raw keys â€” safe to use in initState / animation setup (no context needed)
  List<String> get _currentRoutineKeys =>
      _isNight ? _nightRoutineKeys : _dayRoutineKeys;

  // Translated labels â€” only call inside build() or methods called from build()
  List<String> _currentRoutine(BuildContext ctx) =>
      _currentRoutineKeys.map((k) => AppLocalizations.t(ctx, k)).toList();
  Set<int> get _completedSteps =>
      _isNight ? _nightCompletedSteps : _dayCompletedSteps;
  set _completedSteps(Set<int> value) {
    if (_isNight) {
      _nightCompletedSteps = value;
    } else {
      _dayCompletedSteps = value;
    }
  }

  int get _completed => _completedSteps.length;
  int get _total => _currentRoutineKeys.length;
  double get _progressPct => _total == 0 ? 0 : _completed / _total;

  String get _infoText {
    if (_skinType.isEmpty) {
      return AppLocalizations.t(context, 'skin_select_type_hint');
    }
    if (_concerns.isEmpty) {
      return '$_skinType skin Â· ${_isNight ? 'night' : 'day'} routine Â· Pick your concerns';
    }
    if (_completed == 0) {
      return '$_skinType Â· ${_concerns.join(', ')} Â· Tap a step to start!';
    }
    if (_completed < _total) {
      final rem = _total - _completed;
      return '${(_progressPct * 100).round()}% done Â· $rem step${rem > 1 ? 's' : ''} remaining';
    }
    return AppLocalizations.t(
      context,
      _isNight ? 'skin_all_done_night' : 'skin_all_done_day',
    );
  }

  @override
  void initState() {
    super.initState();

    // â”€â”€ F06: Init pulse animation (2.5s infinite) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _pulseScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );
    _pulseOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // â”€â”€ F02: Init step animations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    _buildStepAnimations();
    _playStepAnimations();
    _loadSkincareProfile();
  }

  List<int> _intList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e is int ? e : int.tryParse(e.toString()))
        .whereType<int>()
        .toList();
  }

  // A saved routine only counts as "today's" progress if it was last
  // updated on the current calendar day. Anything older is a stale
  // completion from a previous day and must not block today's routine.
  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _loadSkincareProfile() async {
    if (_profileLoading) return;
    _profileLoading = true;
    try {
      final service = Provider.of<AppwriteService>(context, listen: false);
      final doc = await service.getSkincareProfile();
      if (!mounted || doc == null) return;
      final data = doc.data;

      final lastUpdated =
      DateTime.tryParse((data['lastUpdated'] ?? '').toString())?.toLocal();
      final bool isNewDay = lastUpdated == null ||
          !_isSameCalendarDay(lastUpdated, DateTime.now());

      setState(() {
        _profileDocumentId = doc.$id;
        _skinType = (data['skinType'] ?? '').toString();
        _concerns = (data['concerns'] as List? ?? const [])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        // If the last saved progress is from a previous day, start today's
        // routine fresh instead of showing yesterday's steps as already done.
        _dayCompletedSteps =
        isNewDay ? <int>{} : _intList(data['daySteps']).toSet();
        _nightCompletedSteps =
        isNewDay ? <int>{} : _intList(data['nightSteps']).toSet();
      });

      if (isNewDay) {
        // Persist the reset so the stale completion doesn't reappear if the
        // profile is reloaded again before any step is tapped today.
        _saveSkincareProfile();
      }
    } catch (_) {
      // Keep the screen usable offline; the next selection will retry save.
    } finally {
      _profileLoading = false;
    }
  }

  Future<void> _saveSkincareProfile() async {
    try {
      final service = Provider.of<AppwriteService>(context, listen: false);
      var documentId = _profileDocumentId;
      if (documentId == null || documentId.isEmpty) {
        final doc = await service.getSkincareProfile();
        documentId = doc?.$id;
        if (mounted && documentId != null) {
          setState(() => _profileDocumentId = documentId);
        }
      }
      if (documentId == null || documentId.isEmpty) return;
      await service.updateSkincareProfile(
        documentId: documentId,
        skinType: _skinType,
        concerns: List<String>.from(_concerns),
        daySteps: _dayCompletedSteps.toList()..sort(),
        nightSteps: _nightCompletedSteps.toList()..sort(),
      );
    } catch (_) {
      // Non-blocking persistence; UI remains responsive.
    }
  }

  // â”€â”€ F02/F20: Build and stagger step slide-up animations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _buildStepAnimations() {
    // Dispose old controllers if rebuilding
    if (mounted) {
      try {
        for (final c in _stepAnimCtrls) {
          c.dispose();
        }
      } catch (_) {}
    }
    _stepAnimCtrls = List.generate(
      _currentRoutineKeys.length,
          (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350),
      ),
    );
    _stepSlideAnims = _stepAnimCtrls
        .map(
          (ctrl) => Tween<double>(
        begin: 16,
        end: 0,
      ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut)),
    )
        .toList();
    _stepFadeAnims = _stepAnimCtrls
        .map(
          (ctrl) => Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut)),
    )
        .toList();
  }

  void _playStepAnimations() {
    // Stagger: each step fires 60ms after the previous (matches HTML i*0.06s)
    for (int i = 0; i < _stepAnimCtrls.length; i++) {
      Future.delayed(Duration(milliseconds: i * 60), () {
        if (mounted) _stepAnimCtrls[i].forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    for (final c in _stepAnimCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _setRoutine(bool night) {
    setState(() {
      _isNight = night;
    });
    // â”€â”€ F20: Re-trigger step slideUp animations on routine switch â”€â”€â”€â”€â”€â”€â”€â”€â”€
    _buildStepAnimations();
    setState(() {}); // Rebuild with new controllers
    _playStepAnimations();
  }

  void _setSkin(String type) {
    setState(() {
      _skinType = type;
      _concerns = [];
    });
    _saveSkincareProfile();
  }

  void _toggleConcern(String concern) {
    setState(() {
      if (_concerns.contains(concern)) {
        _concerns.remove(concern);
      } else {
        _concerns.add(concern);
      }
    });
    _saveSkincareProfile();
  }

  void _markStep(int index) {
    setState(() {
      final updated = Set<int>.from(_completedSteps);
      if (updated.contains(index)) {
        updated.remove(index);
      } else {
        updated.add(index);
      }
      _completedSteps = updated;
    });
    _saveSkincareProfile();
  }

  @override
  Widget build(BuildContext context) {
    _setSkinTokens(context.themeTokens);
    return PopScope(
      canPop: !_chatOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _chatOpen) {
          setState(() => _chatOpen = false);
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 112,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildHeader(), _buildContent()],
              ),
            ),
            // â”€â”€ Chat FAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _chatOpen,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: 20,
                      bottom: MediaQuery.paddingOf(context).bottom + 30,
                    ),
                    child: _AskAhviFab(
                      onTap: () => showAhviStylistChatSheet(
                        context,
                        moduleContext: 'skincare',
                        contextData: {
                          'profile': {
                            'type': _skinType.isNotEmpty
                                ? _skinType
                                : 'Unknown',
                            'concerns': _concerns.isNotEmpty
                                ? _concerns.join(', ')
                                : 'None specified',
                          },
                          'routine': _currentRoutine(context),
                          'routine_mode': _isNight ? 'night' : 'morning',
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // â”€â”€ F07: Chat overlay â€“ AnimatedOpacity for backdrop fade â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _chatOpen ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_chatOpen,
                child: _ChatOverlay(
                  skinType: _skinType,
                  concerns: _concerns,
                  isNight: _isNight,
                  completedSteps: _completedSteps.length,
                  onClose: () => setState(() => _chatOpen = false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 4,
        20,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _cardBorder),
              ),
              child: Icon(Icons.chevron_left_rounded, color: _text, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Skincare',
            style: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.w600,
              color: _text,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(_buildRoutineToggle()),
          const SizedBox(height: 16),
          _buildCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSecLabel(AppLocalizations.t(context, 'skin_skin_type')),
                _buildSkinBar(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSecLabel(AppLocalizations.t(context, 'skin_concerns')),
                _buildConcernPills(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoBar(),
          const SizedBox(height: 16),
          _buildCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.t(context, 'skin_daily_progress'),
                      style: TextStyle(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${(_progressPct * 100).round()}%',
                      style: TextStyle(
                        fontSize: 13,
                        color: _accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildProgressTrack(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSecLabel(
                  AppLocalizations.t(
                    context,
                    _isNight ? 'skin_night_routine' : 'skin_morning_routine',
                  ),
                ),
                _buildStepsGrid(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildTipCard(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // â”€â”€ Routine Toggle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildRoutineToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _phoneShell,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          Expanded(child: _buildRtBtn(isDay: true)),
          const SizedBox(width: 5),
          Expanded(child: _buildRtBtn(isDay: false)),
        ],
      ),
    );
  }

  Widget _buildRtBtn({required bool isDay}) {
    final bool isActive = isDay ? !_isNight : _isNight;
    Color bgColor = kTransparent;
    Color textColor = _muted;
    Color iconColor = _muted;
    List<BoxShadow> shadows = [];

    if (isActive) {
      if (isDay) {
        bgColor = _accent5;
        textColor = _tileText;
        iconColor = _tileText;
        shadows = [
          BoxShadow(
            color: _accent5.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: Offset(0, 3),
          ),
        ];
      } else {
        bgColor = _accent2;
        textColor = _text;
        iconColor = _text;
        shadows = [
          BoxShadow(
            color: _accent2.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: Offset(0, 3),
          ),
        ];
      }
    }

    return GestureDetector(
      onTap: () => _setRoutine(!isDay),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: shadows,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDay ? Icons.wb_sunny_outlined : Icons.nightlight_round,
              size: 15,
              color: iconColor,
            ),
            const SizedBox(width: 7),
            Text(
              isDay
                  ? AppLocalizations.t(context, 'skin_morning')
                  : AppLocalizations.t(context, 'skin_night'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Skin Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSkinBar() {
    final List<_SkinData> skins = [
      _SkinData(
        AppLocalizations.t(context, 'skin_type_oily'),
        Icons.water_drop_outlined,
        _accent,
        _accent.withValues(alpha: 0.40),
      ),
      _SkinData(
        AppLocalizations.t(context, 'skin_type_dry'),
        Icons.wb_sunny_outlined,
        _accent5,
        _accent5.withValues(alpha: 0.40),
      ),
      _SkinData(
        AppLocalizations.t(context, 'skin_type_normal'),
        Icons.eco_outlined,
        _accent3,
        _accent3.withValues(alpha: 0.40),
      ),
      _SkinData(
        AppLocalizations.t(context, 'skin_type_combo'),
        Icons.add,
        _accent2,
        _accent2.withValues(alpha: 0.40),
      ),
      _SkinData(
        AppLocalizations.t(context, 'skin_type_sensitive'),
        Icons.favorite_outline,
        _accent4,
        _accent4.withValues(alpha: 0.40),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _phoneShell,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: skins.map((s) {
          final isActive = _skinType == s.label;
          return Expanded(
            child: GestureDetector(
              onTap: () => _setSkin(s.label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                decoration: BoxDecoration(
                  color: isActive ? s.activeColor : kTransparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isActive
                      ? [
                    BoxShadow(
                      color: s.shadowColor,
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                      : [],
                ),
                child: Column(
                  children: [
                    Icon(
                      s.icon,
                      size: 15,
                      color: isActive ? _tileText : _muted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isActive ? _tileText : _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // â”€â”€ Concern Pills â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildConcernPills() {
    final List<_ConcernData> concerns = [
      _ConcernData(
        AppLocalizations.t(context, 'skin_concern_acne'),
        Icons.shield_outlined,
        _accent4,
        _accent4.withValues(alpha: 0.12),
        _accent4.withValues(alpha: 0.28),
        _accent4.withValues(alpha: 0.40),
      ),
      _ConcernData(
        AppLocalizations.t(context, 'skin_concern_pigmentation'),
        Icons.grain,
        _accent2,
        _accent2.withValues(alpha: 0.12),
        _accent2.withValues(alpha: 0.28),
        _accent2.withValues(alpha: 0.40),
      ),
      _ConcernData(
        AppLocalizations.t(context, 'skin_concern_aging'),
        Icons.auto_awesome_outlined,
        _accent5,
        _accent5.withValues(alpha: 0.12),
        _accent5.withValues(alpha: 0.28),
        _accent5.withValues(alpha: 0.45),
      ),
      _ConcernData(
        AppLocalizations.t(context, 'skin_concern_dullness'),
        Icons.wb_sunny_outlined,
        _accent,
        _accent.withValues(alpha: 0.12),
        _accent.withValues(alpha: 0.28),
        _accent.withValues(alpha: 0.45),
      ),
      _ConcernData(
        AppLocalizations.t(context, 'skin_concern_dryness'),
        Icons.water_drop_outlined,
        _accent3,
        _accent3.withValues(alpha: 0.12),
        _accent3.withValues(alpha: 0.28),
        _accent3.withValues(alpha: 0.45),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: concerns.map((c) {
        final isActive = _concerns.contains(c.label);
        return GestureDetector(
          onTap: () => _toggleConcern(c.label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? c.activeColor : c.bgColor,
              border: Border.all(
                color: isActive ? c.activeColor : c.borderColor,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: isActive
                  ? [
                BoxShadow(
                  color: c.shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.icon,
                  size: 13,
                  color: isActive ? _tileText : c.activeColor,
                ),
                const SizedBox(width: 6),
                Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? _tileText : c.activeColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // â”€â”€ Info Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: _accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _infoText,
              style: TextStyle(fontSize: 11.5, color: _accent),
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Progress Track â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildProgressTrack() {
    return Container(
      height: 7,
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.hardEdge,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _progressPct),
        duration: const Duration(milliseconds: 500),
        curve: const Cubic(0.25, 0.8, 0.25, 1.0),
        builder: (context, value, child) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_accent, _accent2, _accent3]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.40),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // â”€â”€ Steps Grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildStepsGrid() {
    final steps = _currentRoutine(context);
    final List<Widget> rows = [];
    for (int i = 0; i < steps.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: _buildStepCard(i, steps[i])),
            const SizedBox(width: 9),
            if (i + 1 < steps.length)
              Expanded(child: _buildStepCard(i + 1, steps[i + 1]))
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < steps.length) rows.add(const SizedBox(height: 9));
    }
    return Column(children: rows);
  }

  Widget _buildStepCard(int index, String name) {
    final isDone = _completedSteps.contains(index);
    final color = _stepColors[index % _stepColors.length];
    final bg = _stepBgColors[index % _stepBgColors.length];
    final border = _stepBorderColors[index % _stepBorderColors.length];

    return _StepCard(
      index: index,
      name: name,
      isDone: isDone,
      color: color,
      bg: bg,
      border: border,
      slideAnim: index < _stepSlideAnims.length ? _stepSlideAnims[index] : null,
      fadeAnim: index < _stepFadeAnims.length ? _stepFadeAnims[index] : null,
      onTap: () => _markStep(index),
      stepIconData: _stepIcon(name),
      stepImageUrl: _stepImageUrl(name),
    );
  }

  String? _stepImageUrl(String name) {
    final Map<String, String> urlMap = {
      AppLocalizations.t(
        context,
        'skin_cleanser',
      ): 'https://images.unsplash.com/photo-1556228724-4f3e2f3bb7f1?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_toner',
      ): 'https://images.unsplash.com/photo-1629198735660-e39ea93f5b49?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_vitamin_c',
      ): 'https://images.unsplash.com/photo-1571781418606-70265b9cce90?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_moisturizer',
      ): 'https://images.unsplash.com/photo-1625772452859-1c03d5bf1137?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_sunscreen',
      ): 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_retinol',
      ): 'https://images.unsplash.com/photo-1612817288484-6f916006741a?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_night_cream',
      ): 'https://images.unsplash.com/photo-1611080541599-8c6dbde6ed28?auto=format&fit=crop&w=120&q=80',
      AppLocalizations.t(
        context,
        'skin_lip_care',
      ): 'https://images.unsplash.com/photo-1586495777744-4413f21062fa?auto=format&fit=crop&w=120&q=80',
    };
    return urlMap[name];
  }

  IconData _stepIcon(String name) {
    final Map<String, IconData> iconMap = {
      AppLocalizations.t(context, 'skin_cleanser'): Icons.water_drop_outlined,
      AppLocalizations.t(context, 'skin_toner'): Icons.grid_view_outlined,
      AppLocalizations.t(context, 'skin_vitamin_c'): Icons.science_outlined,
      AppLocalizations.t(context, 'skin_moisturizer'): Icons.opacity,
      AppLocalizations.t(context, 'skin_sunscreen'): Icons.light_mode_outlined,
      AppLocalizations.t(context, 'skin_retinol'): Icons.biotech_outlined,
      AppLocalizations.t(context, 'skin_night_cream'): Icons.bedtime_outlined,
      AppLocalizations.t(context, 'skin_lip_care'):
      Icons.face_retouching_natural,
    };
    return iconMap[name] ?? Icons.spa_outlined;
  }

  // â”€â”€ Tip Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accent.withValues(alpha: 0.15),
                  _accent2.withValues(alpha: 0.15),
                ],
              ),
              border: Border.all(color: _cardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('💡', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            // FIX: removed `const` â€” RichText uses runtime color getters _muted and _accent5
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
                children: [
                  TextSpan(
                    text: 'Pro tip: ',
                    style: TextStyle(
                      color: _accent5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: AppLocalizations.t(context, 'skin_pro_tip_text'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Chat Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSection(Widget child) => child;

  Widget _buildCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _buildSecLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.14 * 10,
              color: _muted,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_accent.withValues(alpha: 0.30), kTransparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  F02 + F03: Step Card â€” SlideUp on render + Hover lift (-3px)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _StepCard extends StatefulWidget {
  final int index;
  final String name;
  final bool isDone;
  final Color color;
  final Color bg;
  final Color border;
  final Animation<double>? slideAnim;
  final Animation<double>? fadeAnim;
  final VoidCallback onTap;
  final IconData stepIconData;
  final String? stepImageUrl;

  const _StepCard({
    required this.index,
    required this.name,
    required this.isDone,
    required this.color,
    required this.bg,
    required this.border,
    this.slideAnim,
    this.fadeAnim,
    required this.onTap,
    required this.stepIconData,
    this.stepImageUrl,
  });

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          transform: Matrix4.translationValues(0, _hovered ? -3.0 : 0.0, 0),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: widget.isDone ? _bg.withValues(alpha: 0.20) : widget.bg,
            gradient: widget.isDone
                ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _accent.withValues(alpha: 0.20),
                _accent2.withValues(alpha: 0.20),
              ],
            )
                : null,
            border: Border.all(
              color: widget.isDone
                  ? _accent.withValues(alpha: 0.40)
                  : widget.border,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _panel2,
                  border: Border.all(color: _cardBorder),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _bg.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    widget.stepIconData,
                    size: 16,
                    color: widget.isDone ? _accent : widget.color,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: widget.isDone ? _accent : widget.color,
                  decoration: widget.isDone
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: widget.isDone
                      ? _accent.withValues(alpha: 0.65)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.slideAnim != null && widget.fadeAnim != null) {
      return AnimatedBuilder(
        animation: widget.slideAnim!,
        builder: (context, child) {
          return Opacity(
            opacity: widget.fadeAnim!.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, widget.slideAnim!.value),
              child: child,
            ),
          );
        },
        child: card,
      );
    }
    return card;
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Chat Overlay
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ChatMessage {
  final bool isUser;
  final String text;
  final String time;
  _ChatMessage({required this.isUser, required this.text, required this.time});
}

class _ChatOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final String skinType;
  final List<String> concerns;
  final bool isNight;
  final int completedSteps;

  const _ChatOverlay({
    required this.onClose,
    required this.skinType,
    required this.concerns,
    required this.isNight,
    required this.completedSteps,
  });

  @override
  State<_ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<_ChatOverlay>
    with TickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _showWelcome = true;
  bool _isBusy = false;
  bool _showQuickPills = true;
  final List<Map<String, String>> _chatHistory = [];

  bool _isListening = false;
  late AnimationController _micPulseCtrl;
  late Animation<double> _micPulseAnim;

  final FocusNode _inputFocus = FocusNode();
  bool _inputFocused = false;

  late List<String> _quickPills;

  String _ts() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _getCtx() {
    return 'User skin: ${widget.skinType.isEmpty ? 'unset' : widget.skinType}. '
        'Concerns: ${widget.concerns.isEmpty ? 'none' : widget.concerns.join(', ')}. '
        'Routine: ${widget.isNight ? 'night' : 'morning'}. '
        'Steps done: ${widget.completedSteps}.';
  }

  bool _quickPillsInited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_quickPillsInited) {
      _quickPills = [
        AppLocalizations.t(context, 'skin_chip_oily'),
        AppLocalizations.t(context, 'skin_chip_morning_order'),
        AppLocalizations.t(context, 'skin_chip_vitamin_c'),
        AppLocalizations.t(context, 'skin_chip_retinol'),
        AppLocalizations.t(context, 'skin_chip_acne'),
      ];
      _quickPillsInited = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Cubic(0.32, 0.72, 0.0, 1.0),
      ),
    );
    _animCtrl.forward();

    _micPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _micPulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _micPulseCtrl, curve: Curves.easeInOut));

    _inputFocus.addListener(() {
      setState(() => _inputFocused = _inputFocus.hasFocus);
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _addAIGreeting();
    });
  }

  Future<void> _addAIGreeting() async {
    setState(() {
      _isBusy = true;
    });
    const greetPrompt =
        'Greet the user warmly as AHVI skincare advisor. '
        'Introduce yourself in 1-2 sentences and invite them to ask about their skin. '
        'Be friendly and use 1 emoji max.';

    try {
      final response = await BackendService().sendModuleChat(
        domain: 'skincare',
        message: greetPrompt,
        chatHistory: const [],
      );
      final rawMessage = response['message'];
      final text =
      (response['message_text'] ??
          (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
          response['response'] ??
          '')
          .toString()
          .trim();

      if (mounted && text.isNotEmpty) {
        setState(() {
          _isBusy = false;
          _messages.add(_ChatMessage(isUser: false, text: text, time: _ts()));
          _chatHistory.add({'role': 'assistant', 'content': text});
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          final greeting = AppLocalizations.t(context, 'skin_ahvi_greeting');
          _messages.add(
            _ChatMessage(isUser: false, text: greeting, time: _ts()),
          );
          _chatHistory.add({'role': 'assistant', 'content': greeting});
        });
        _scrollToBottom();
      }
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _micPulseCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _close() {
    _animCtrl.reverse().then((_) => widget.onClose());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty || _isBusy) return;
    _inputCtrl.clear();

    setState(() {
      _showWelcome = false;
      _showQuickPills = false;
      _isBusy = true;
      _messages.add(_ChatMessage(isUser: true, text: text.trim(), time: _ts()));
      _chatHistory.add({'role': 'user', 'content': text.trim()});
    });
    _scrollToBottom();

    try {
      final response = await BackendService().sendModuleChat(
        domain: 'skincare',
        message: 'Context: ${_getCtx()}\n\n${text.trim()}',
        chatHistory: List<Map<String, String>>.from(_chatHistory),
      );
      final rawMessage = response['message'];
      final aiText =
      (response['message_text'] ??
          (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
          response['response'] ??
          response['reply'] ??
          '')
          .toString()
          .trim();

      debugPrint(
        'AHVI_SKINCARE_RESP type=${response['type']} '
            'has_text=${aiText.isNotEmpty} '
            'used_fallback=${response['meta']?['used_local_fallback']} '
            'keys=${response.keys.toList()}',
      );

      if (mounted) {
        final reply = aiText.isNotEmpty
            ? aiText
            : "AHVI didn't return a skincare answer this time. Please try again.";
        setState(() {
          _isBusy = false;
          _messages.add(_ChatMessage(isUser: false, text: reply, time: _ts()));
          _chatHistory.add({'role': 'assistant', 'content': reply});
        });
        _scrollToBottom();
      }
    } catch (_) {
      const fallback =
          "I couldn't reach AHVI for skincare right now. Please try again.";
      if (mounted) {
        setState(() {
          _isBusy = false;
          _messages.add(
            _ChatMessage(isUser: false, text: fallback, time: _ts()),
          );
          _chatHistory.add({'role': 'assistant', 'content': fallback});
        });
        _scrollToBottom();
      }
    }
  }

  void _toggleVoice() {
    setState(() => _isListening = !_isListening);
    if (_isListening) {
      _micPulseCtrl.repeat(reverse: true);
      _inputCtrl.text = '';
    } else {
      _micPulseCtrl.stop();
      _micPulseCtrl.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _close,
      child: Container(
        color: _bg.withValues(alpha: 0.75),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: SlideTransition(position: _slideAnim, child: _buildModal()),
          ),
        ),
      ),
    );
  }

  Widget _buildModal() {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      width: 390,
      height: screenH * 0.82,
      decoration: BoxDecoration(
        color: _bg2,
        border: Border.all(color: _cardBorder),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.15),
            blurRadius: 50,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.fromLTRB(0, 14, 0, 6),
            decoration: BoxDecoration(
              color: _panel2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildModalHeader(),
          Expanded(child: _buildMessages()),
          if (_showQuickPills) _buildQuickPills(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildModalHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _phoneShell2,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _bg.withValues(alpha: 0.30),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            // FIX: removed `const` â€” Text style uses runtime color getter _accent
            child: Center(
              child: Text(
                '✦',
                style: TextStyle(fontSize: 18, color: _accent),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.t(context, 'skin_chat_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _accent3,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _accent3.withValues(alpha: 0.60),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppLocalizations.t(context, 'skin_chat_subtitle'),
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _close,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _panel,
                shape: BoxShape.circle,
                border: Border.all(color: _cardBorder),
              ),
              // FIX: removed `const` â€” Text style uses runtime color getter _muted
              child: Center(
                child: Text(
                  '✕',
                  style: TextStyle(fontSize: 14, color: _muted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    final itemCount =
        (_showWelcome ? 1 : 0) + _messages.length + (_isBusy ? 1 : 0);
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        var cursor = 0;
        if (_showWelcome) {
          if (index == 0) return _buildWelcome();
          cursor = 1;
        }
        final messageIndex = index - cursor;
        if (messageIndex < _messages.length) {
          return RepaintBoundary(
            child: _SlideUpMessage(
              child: _buildMsgRow(_messages[messageIndex]),
            ),
          );
        }
        return RepaintBoundary(child: _buildTypingIndicator());
      },
    );
  }

  Widget _buildWelcome() {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _phoneShell2,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.20),
                blurRadius: 24,
                offset: Offset(0, 6),
              ),
            ],
          ),
          // FIX: removed `const` â€” Text style uses runtime color getter _accent
          child: Center(
            child: Text('✦', style: TextStyle(fontSize: 24, color: _accent)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.t(context, 'skin_chat_welcome_title'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.t(context, 'skin_chat_welcome_desc'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _muted, height: 1.55),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMsgRow(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: msg.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: msg.isUser
            ? [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _panel2,
                    border: Border.all(color: _cardBorder, width: 1.5),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    // FIX: removed `const` from BoxShadow list â€” uses runtime getter _bg
                    boxShadow: [
                      BoxShadow(
                        color: _bg.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: _text,
                      height: 1.6,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Text(
                    msg.time,
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _panel,
              shape: BoxShape.circle,
              border: Border.all(color: _cardBorder),
            ),
            child: const Center(
              child: Text('👤', style: TextStyle(fontSize: 11)),
            ),
          ),
        ]
            : [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _phoneShell2,
              shape: BoxShape.circle,
            ),
            // FIX: removed `const` â€” Text style uses runtime getter _accent
            child: Center(
              child: Text(
                '✦',
                style: TextStyle(fontSize: 12, color: _accent),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _panel,
                    border: Border.all(color: _cardBorder),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    // FIX: removed `const` from BoxShadow list â€” uses runtime getter _bg
                    boxShadow: [
                      BoxShadow(
                        color: _bg.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: _text,
                      height: 1.6,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    msg.time,
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _phoneShell2,
            shape: BoxShape.circle,
          ),
          // FIX: removed `const` â€” Text style uses runtime getter _accent
          child: Center(
            child: Text('✦', style: TextStyle(fontSize: 12, color: _accent)),
          ),
        ),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _cardBorder),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
                  (i) => _TypingDot(delay: Duration(milliseconds: i * 180)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPills() {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: _quickPills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _QuickPillButton(
          label: _quickPills[i],
          onTap: () => _sendMessage(_quickPills[i]),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SkincarePlusButton(
            panel: _panel,
            panel2: _panel2,
            cardBorder: _cardBorder,
            accent: _accent,
            text: _text,
            muted: _muted,
            onCameraSelected: () =>
                showAhviLensSheet(context, t: context.themeTokens),
          ),
          const SizedBox(width: 9),
          GestureDetector(
            onTap: _toggleVoice,
            child: AnimatedBuilder(
              animation: _micPulseAnim,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? _micPulseAnim.value : 1.0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: _isListening
                          ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_accent4, _accent2],
                      )
                          : null,
                      color: _isListening ? null : _panel,
                      shape: BoxShape.circle,
                      border: _isListening
                          ? null
                          : Border.all(color: _cardBorder, width: 1.5),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.mic_outlined,
                        size: 16,
                        color: _isListening ? _text : _muted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
              decoration: BoxDecoration(
                color: _panel2,
                border: Border.all(
                  color: _inputFocused
                      ? _accent.withValues(alpha: 0.45)
                      : _cardBorder,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputCtrl,
                focusNode: _inputFocus,
                style: TextStyle(fontSize: 14, color: _text),
                maxLines: 5,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _isListening
                      ? AppLocalizations.t(context, 'skin_chat_listening')
                      : AppLocalizations.t(context, 'skin_chat_hint'),
                  hintStyle: TextStyle(color: _muted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (v) => _sendMessage(v),
              ),
            ),
          ),
          const SizedBox(width: 9),
          // â”€â”€ AHVI Lens search button â”€â”€
          _ScaleOnTapButton(
            onTap: () => showAhviLensSheet(context, t: context.themeTokens),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _panel,
                shape: BoxShape.circle,
                border: Border.all(color: _cardBorder, width: 1.5),
              ),
              child: Center(
                child: Icon(Icons.search_rounded, size: 18, color: _muted),
              ),
            ),
          ),
          const SizedBox(width: 9),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _isBusy ? 0.28 : 1.0,
            child: _ScaleOnTapButton(
              onTap: _isBusy ? null : () => _sendMessage(_inputCtrl.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_accent, _accent2],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(Icons.send_rounded, size: 16, color: _text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  F12: SlideUp wrapper for each new chat message
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SlideUpMessage extends StatefulWidget {
  final Widget child;
  const _SlideUpMessage({required this.child});
  @override
  State<_SlideUpMessage> createState() => _SlideUpMessageState();
}

class _SlideUpMessageState extends State<_SlideUpMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _slide = Tween<double>(
      begin: 16,
      end: 0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  F08: Scale-on-tap button
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ScaleOnTapButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _ScaleOnTapButton({required this.child, this.onTap});
  @override
  State<_ScaleOnTapButton> createState() => _ScaleOnTapButtonState();
}

class _ScaleOnTapButtonState extends State<_ScaleOnTapButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: widget.child,
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  F14: Quick pill button
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _QuickPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickPillButton({required this.label, required this.onTap});
  @override
  State<_QuickPillButton> createState() => _QuickPillButtonState();
}

class _QuickPillButtonState extends State<_QuickPillButton> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _active = true),
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _active = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          gradient: _active
              ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_accent, _accent2],
          )
              : null,
          color: _active ? null : _panel,
          border: Border.all(color: _active ? kTransparent : _cardBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _active ? _text : _accent,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  F11: Typing dot â€” bounce + color change at peak
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _TypingDot extends StatefulWidget {
  final Duration delay;
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _yAnim;
  late Animation<Color?> _colorAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _yAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -5), weight: 30),
      TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0, end: 0), weight: 40),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _colorAnim = TweenSequence<Color?>([
      TweenSequenceItem(
        tween: ColorTween(begin: _accent.withValues(alpha: 0.50), end: _accent),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: ColorTween(begin: _accent, end: _accent.withValues(alpha: 0.50)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: _accent.withValues(alpha: 0.50),
          end: _accent.withValues(alpha: 0.50),
        ),
        weight: 40,
      ),
    ]).animate(_ctrl);

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Transform.translate(
        offset: Offset(0, _yAnim.value),
        child: Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration: BoxDecoration(
            color: _colorAnim.value ?? _accent.withValues(alpha: 0.50),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Helper data classes
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SkinData {
  final String label;
  final IconData icon;
  final Color activeColor;
  final Color shadowColor;
  const _SkinData(this.label, this.icon, this.activeColor, this.shadowColor);
}

class _ConcernData {
  final String label;
  final IconData icon;
  final Color activeColor;
  final Color bgColor;
  final Color borderColor;
  final Color shadowColor;
  const _ConcernData(
      this.label,
      this.icon,
      this.activeColor,
      this.bgColor,
      this.borderColor,
      this.shadowColor,
      );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// ASK AHVI FAB
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _AskAhviFab extends StatefulWidget {
  final VoidCallback onTap;
  const _AskAhviFab({required this.onTap});

  @override
  State<_AskAhviFab> createState() => _AskAhviFabState();
}

class _AskAhviFabState extends State<_AskAhviFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context
        .watch<
        ThemeController
    >(); // theme change à°…à°¯à°¿à°¨à°ªà±à°ªà±à°¡à± rebuild à°…à°µà±à°¤à±à°‚à°¦à°¿
    final t = context.themeTokens;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => Stack(
            clipBehavior: Clip.none,
            children: [
              // Pulse ring â€” Positioned.fill, same as Daily Wear
              Positioned.fill(
                child: Opacity(
                  opacity: _pulseOpacity.value,
                  child: Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: t.accent.primary.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
            decoration: BoxDecoration(
              color: t.accent.primary,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: t.accent.primary.withValues(alpha: 0.40),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  AppLocalizations.t(context, 'ask_ahvi'),
                  style: GoogleFonts.anton(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Skincare Chat Plus Button (ChatGPT-style attach menu)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SkincarePlusButton extends StatefulWidget {
  final Color panel, panel2, cardBorder, accent, text, muted;
  final VoidCallback? onCameraSelected;
  const _SkincarePlusButton({
    required this.panel,
    required this.panel2,
    required this.cardBorder,
    required this.accent,
    required this.text,
    required this.muted,
    this.onCameraSelected,
  });
  @override
  State<_SkincarePlusButton> createState() => _SkincarePlusButtonState();
}

class _SkincarePlusButtonState extends State<_SkincarePlusButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rotateAnim;
  bool _menuOpen = false;
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _rotateAnim = Tween<double>(
      begin: 0.0,
      end: 0.125,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _closeMenu();
    _ctrl.dispose();
    super.dispose();
  }

  void _openMenu() {
    if (_menuOpen) {
      _closeMenu();
      return;
    }
    setState(() => _menuOpen = true);
    _ctrl.forward();
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    final actions = [
      (Icons.camera_alt_outlined, 'Camera', const Color(0xFFFF6B6B)),
      (Icons.photo_library_outlined, 'Photos', const Color(0xFF4ECDC4)),
      (Icons.attach_file_rounded, 'Files', const Color(0xFF45B7D1)),
      (Icons.search_rounded, 'Search Skincare', const Color(0xFF96CEB4)),
    ];

    _overlay = OverlayEntry(
      builder: (_) {
        return GestureDetector(
          onTap: _closeMenu,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              Positioned(
                left: offset.dx - 10,
                bottom: MediaQuery.of(context).size.height - offset.dy + 8,
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: widget.cardBorder, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: actions
                            .map(
                              (a) => _SkincarePlusMenuRow(
                            icon: a.$1,
                            label: a.$2,
                            color: a.$3,
                            text: widget.text,
                            onTap: () {
                              _closeMenu();
                              widget.onCameraSelected?.call();
                            },
                          ),
                        )
                            .toList(),
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
    Overlay.of(context).insert(_overlay!);
  }

  void _closeMenu() {
    _overlay?.remove();
    _overlay = null;
    _ctrl.reverse();
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openMenu,
      child: AnimatedBuilder(
        animation: _rotateAnim,
        builder: (_, child) => Transform.rotate(
          angle: _rotateAnim.value * 2 * 3.14159,
          child: child,
        ),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _menuOpen
                ? widget.accent.withValues(alpha: 0.15)
                : widget.panel,
            shape: BoxShape.circle,
            border: Border.all(
              color: _menuOpen
                  ? widget.accent.withValues(alpha: 0.5)
                  : widget.cardBorder,
              width: 1.5,
            ),
          ),
          child: Icon(Icons.add_rounded, color: widget.accent, size: 20),
        ),
      ),
    );
  }
}

class _SkincarePlusMenuRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color, text;
  final VoidCallback onTap;
  const _SkincarePlusMenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.text,
    required this.onTap,
  });
  @override
  State<_SkincarePlusMenuRow> createState() => _SkincarePlusMenuRowState();
}

class _SkincarePlusMenuRowState extends State<_SkincarePlusMenuRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.icon, color: widget.color, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
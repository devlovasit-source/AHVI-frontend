// boards.dart — Premium UX Upgrade
// Implements all F1–F12 animations + haptics + iOS scroll + DRY refactor

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/calendar.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/daily_wear.dart' as daily_wear;
// ── Master Board Import ──
import 'package:myapp/occasion.dart'; // Handles Daily Wear, Office, Party, Vacation, etc.

// ── Specific Board Imports ──
import 'package:myapp/everything_else.dart' as everything_else;
import 'package:myapp/home_and_utilities.dart' as home_utils;
import 'package:myapp/skincare.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/widgets/ahvi_header.dart';
import 'package:myapp/diet_fitness.dart' as diet_fitness;

class ShellBackNavigationNotification extends Notification {
  const ShellBackNavigationNotification();
}

// ─────────────────────────────────────────────────────────────────────────────
//  CALENDAR CARD (glass + inline expandable panel)
// ─────────────────────────────────────────────────────────────────────────────
class CalendarCard extends StatefulWidget {
  final Color cardColor;
  final Color borderColor;
  final Color panelColor;
  final Color panelBorder;
  final Color textColor;
  final Color mutedColor;
  final Color accent;
  final Color accentSoft;
  final Color shellColor;
  final Color iconColor;

  const CalendarCard({
    super.key,
    required this.cardColor,
    required this.borderColor,
    required this.panelColor,
    required this.panelBorder,
    required this.textColor,
    required this.mutedColor,
    required this.accent,
    required this.accentSoft,
    required this.shellColor,
    required this.iconColor,
  });

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  final int _totalPlans = 0;
  final int _todayPlans = 0;

  void _openCalendar() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CalendarShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _GlassCard(
        borderColor: widget.borderColor,
        glow: widget.accent.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _S.base,
            _S.base,
            _S.base,
            _S.base,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openCalendar,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.borderColor, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: widget.iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.t(context, 'boards_schedule_calendar'),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: widget.textColor,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '• $_totalPlans outfit plans • $_todayPlans today',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: widget.textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: widget.mutedColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final Color glow;

  const _GlassCard({
    required this.child,
    required this.borderColor,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.themeTokens.accent.secondary.withValues(alpha: 0.85),
                context.themeTokens.accent.tertiary,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: context.themeTokens.accent.primary.withValues(
                  alpha: 0.4,
                ),
                blurRadius: 32,
                spreadRadius: 1,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SPACING CONSTANTS  (4-pt grid)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _S {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 24;
  static const double xl = 32;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ANIMATION CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _A {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration entry = Duration(milliseconds: 500);
  static const Duration page = Duration(milliseconds: 600);

  static const Curve spring = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Curve pageEntry = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve ease = Curves.easeOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
//  BOARDS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class BoardsScreen extends StatefulWidget {
  const BoardsScreen({super.key});

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen>
    with TickerProviderStateMixin {
  AppThemeTokens get _theme => context.themeTokens;
  Color get _bg2 => _theme.backgroundSecondary;
  Color get _panel => _theme.panel;
  Color get _panelBorder => _theme.panelBorder;
  Color get _card => _theme.card;
  Color get _cardBorder => _theme.cardBorder;
  Color get _text => _theme.textPrimary;
  Color get _muted => _theme.mutedText;
  Color get _accent => _theme.accent.primary;
  Color get _accent2 => _theme.accent.secondary;
  Color get _shell => _theme.phoneShell;
  Color get _cardIconColor => Theme.of(context).brightness == Brightness.light
      ? Colors.black
      : Colors.white;

  bool _isLifeTab = true;
  bool _hasStartedAnimations =
  false; // <-- FIX: Tracks if entry animations fired
  bool _tabSwitching = false;
  final List<String> _customBoardNames = [];
  final TextEditingController _createBoardController = TextEditingController();
  final FocusNode _createBoardFocusNode = FocusNode();

  late final AnimationController _headerCtrl;
  late final Animation<double> _headerOpacity;
  late final Animation<Offset> _headerSlide;

  late final AnimationController _toggleCtrl;
  late final Animation<double> _toggleOpacity;
  late final Animation<Offset> _toggleSlide;

  late final AnimationController _sectionCtrl;
  late final Animation<double> _sectionOpacity;
  late final Animation<Offset> _sectionSlide;

  @override
  void initState() {
    super.initState();

    _headerCtrl = AnimationController(vsync: this, duration: _A.page);
    _headerOpacity = CurvedAnimation(parent: _headerCtrl, curve: _A.pageEntry);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerCtrl, curve: _A.pageEntry));

    _toggleCtrl = AnimationController(vsync: this, duration: _A.page);
    _toggleOpacity = CurvedAnimation(parent: _toggleCtrl, curve: _A.pageEntry);
    _toggleSlide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _toggleCtrl, curve: _A.pageEntry));

    _sectionCtrl = AnimationController(vsync: this, duration: _A.slow);
    _sectionOpacity = CurvedAnimation(parent: _sectionCtrl, curve: Curves.ease);
    _sectionSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _sectionCtrl, curve: Curves.ease));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasStartedAnimations) return;
      _hasStartedAnimations = true;
      _headerCtrl.forward();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _toggleCtrl.forward();
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _sectionCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _toggleCtrl.dispose();
    _sectionCtrl.dispose();
    _createBoardController.dispose();
    _createBoardFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When TickerMode re-enables this tab, push any stalled controllers to 1.0
    // so the screen never appears faded on re-visit.
    if (_hasStartedAnimations) {
      if (_headerCtrl.value < 1.0) _headerCtrl.forward();
      if (_toggleCtrl.value < 1.0) _toggleCtrl.forward();
      if (_sectionCtrl.value < 1.0 && !_tabSwitching) _sectionCtrl.forward();
    }
  }

  void _switchTab(bool isLife) {
    if (_isLifeTab == isLife) return;
    HapticFeedback.selectionClick();
    setState(() => _isLifeTab = isLife);
    _sectionCtrl
      ..reset()
      ..forward();
  }

  void _push(Widget page) {
    HapticFeedback.lightImpact();
    // Dismiss any active modal / bottom-sheet / lens overlay before
    // navigating. Without this a stale modal scrim can sit on top of
    // the next screen — that's the root of the reported "permanent
    // faded overlay over Daily Wear" symptom when transitioning from
    // Home with a chat sheet still mounted.
    final nav = Navigator.of(context);
    while (nav.canPop()) {
      final route = ModalRoute.of(context);
      // Only pop transient overlays (bottom sheets / dialogs). Don't
      // pop the underlying page route itself.
      if (route is PopupRoute || route is RawDialogRoute) {
        nav.pop();
      } else {
        break;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();

    nav.push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: _A.slow,
        reverseTransitionDuration: _A.slow,
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: _A.pageEntry,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
        maintainState: true,
      ),
    );
  }

  void _openCreateBoardDialog() {
    _createBoardController.clear();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _CreateBoardDialog(
        controller: _createBoardController,
        focusNode: _createBoardFocusNode,
        accent: _accent,
        card: _card,
        cardBorder: _cardBorder,
        text: _text,
        muted: _muted,
        onSubmit: _submitCreateBoard,
      ),
    );
  }

  void _submitCreateBoard() {
    final trimmed = _createBoardController.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.t(context, 'boards_please_enter')),
        ),
      );
      return;
    }

    final alreadyExists = _customBoardNames.any(
          (name) => name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (alreadyExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.t(context, 'boards_already_exists')),
        ),
      );
      return;
    }

    setState(() {
      _customBoardNames.add(trimmed);
    });
    _createBoardFocusNode.unfocus();
    _createBoardController.clear();
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _deleteCustomBoard(String boardName) {
    setState(() {
      _customBoardNames.remove(boardName);
    });
  }

  List<_BoardCardConfig> _predefinedBoardCards() {
    return [
      _BoardCardConfig(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFB08F), Color(0xFFFF8F72)],
        ),
        shadowColor: const Color(0xFFFF8F72).withValues(alpha: 0.30),
        iconBg: _panel,
        icon: Icons.celebration_rounded,
        title: AppLocalizations.t(context, 'boards_party_looks'),
        subtitle: AppLocalizations.t(context, 'boards_party_looks_sub'),
        onTap: () => _push(
          OccasionBoard(
            occasion: 'Party',
            titleKey: 'boards_party_looks',
            subtitleKey: 'boards_party_looks_sub',
            emptyEmoji: '🎊',
          ),
        ),
      ),
      _BoardCardConfig(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE07E), Color(0xFFFFC956)],
        ),
        shadowColor: const Color(0xFFFFC956).withValues(alpha: 0.30),
        iconBg: _panel,
        icon: Icons.business_center_rounded,
        title: AppLocalizations.t(context, 'boards_office_fits'),
        subtitle: AppLocalizations.t(context, 'boards_office_fits_sub'),
        onTap: () => _push(
          OccasionBoard(
            occasion: 'Office',
            titleKey: 'boards_office_fits',
            subtitleKey: 'boards_office_fits_sub',
            emptyEmoji: '💼',
          ),
        ),
      ),
      _BoardCardConfig(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9AF0D3), Color(0xFF58DCB0)],
        ),
        shadowColor: const Color(0xFF58DCB0).withValues(alpha: 0.25),
        iconBg: _panel,
        icon: Icons.beach_access_rounded,
        title: AppLocalizations.t(context, 'boards_vacation'),
        subtitle: AppLocalizations.t(context, 'boards_vacation_sub'),
        onTap: () => _push(
          OccasionBoard(
            occasion: 'Vacation',
            titleKey: 'boards_vacation',
            subtitleKey: 'boards_vacation_sub',
            emptyEmoji: '✈️',
          ),
        ),
      ),
      _BoardCardConfig(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9DCBFF), Color(0xFF77A8FF)],
        ),
        shadowColor: const Color(0xFF77A8FF).withValues(alpha: 0.28),
        iconBg: _card,
        icon: Icons.auto_awesome_rounded,
        title: AppLocalizations.t(context, 'boards_occasion'),
        subtitle: AppLocalizations.t(context, 'boards_occasion_sub'),
        onTap: () => _push(
          OccasionBoard(
            occasion: 'Occasion',
            titleKey: 'boards_occasion',
            subtitleKey: 'boards_occasion_sub',
            emptyEmoji: '✨',
          ),
        ),
      ),
    ];
  }

  List<_BoardCardConfig> _customBoardCards() {
    const palette = [
      [Color(0xFF8EC5FC), Color(0xFF5F8BFF)],
      [Color(0xFFFFC58B), Color(0xFFFF9F68)],
      [Color(0xFF9EE6C9), Color(0xFF58D7A8)],
      [Color(0xFFD2B7FF), Color(0xFFA586FF)],
      [Color(0xFFFFB7D4), Color(0xFFFF8FC4)],
      [Color(0xFFF7E08B), Color(0xFFEBC85B)],
    ];

    return _customBoardNames.asMap().entries.map((entry) {
      final index = entry.key;
      final boardName = entry.value;
      final colors = palette[index % palette.length];
      return _BoardCardConfig(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        shadowColor: colors[1].withValues(alpha: 0.28),
        iconBg: _panel,
        icon: Icons.dashboard_customize_rounded,
        title: boardName,
        subtitle: AppLocalizations.t(context, 'boards_custom_sub'),
        onTap: () => _push(
          OccasionBoard(
            occasion: 'Custom:$boardName',
            titleLabel: boardName,
            subtitleLabel: AppLocalizations.t(context, 'boards_custom_sub'),
            emptyEmoji: '🧩',
          ),
        ),
        onDelete: () => _deleteCustomBoard(boardName),
      );
    }).toList();
  }

  Widget _buildBoardCard(
      _BoardCardConfig config, {
        required bool fullWidth,
        required int delayMs,
      }) {
    return _StaggeredCard(
      delay: Duration(milliseconds: delayMs),
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            child: _VCard(
              fullWidth: fullWidth,
              gradient: config.gradient,
              shadowColor: config.shadowColor,
              badge: null,
              badgeTextColor: Colors.transparent,
              badgeBg: Colors.transparent,
              badgeBorderColor: Colors.transparent,
              iconBg: config.iconBg,
              iconWidget: Icon(config.icon, size: 26, color: _cardIconColor),
              title: config.title,
              titleColor: Colors.white,
              titleSize: 15,
              subtitle: config.subtitle,
              subtitleColor: Colors.white,
              arrowBg: config.iconBg,
              arrowColor: _cardIconColor,
              shellColor: _shell,
              onTap: config.onTap,
            ),
          ),
          if (config.onDelete != null)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: config.onDelete,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.26),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTwoColumnBoardGrid(
      List<_BoardCardConfig> cards, {
        int startDelayMs = 80,
      }) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    var cardIndex = 0;

    while (cardIndex < cards.length) {
      final remaining = cards.length - cardIndex;

      if (remaining == 1) {
        rows.add(
          _buildBoardCard(
            cards[cardIndex],
            fullWidth: true,
            delayMs: startDelayMs + (cardIndex * 80),
          ),
        );
        cardIndex += 1;
      } else {
        rows.add(
          Row(
            children: [
              Expanded(
                child: _buildBoardCard(
                  cards[cardIndex],
                  fullWidth: false,
                  delayMs: startDelayMs + (cardIndex * 80),
                ),
              ),
              const SizedBox(width: _S.md),
              Expanded(
                child: _buildBoardCard(
                  cards[cardIndex + 1],
                  fullWidth: false,
                  delayMs: startDelayMs + ((cardIndex + 1) * 80),
                ),
              ),
            ],
          ),
        );
        cardIndex += 2;
      }

      if (cardIndex < cards.length) {
        rows.add(const SizedBox(height: _S.md));
      }
    }

    return Column(children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg2,
      body: Stack(
        children: [
          Positioned.fill(child: _buildAmbientBg()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Fixed logo header — AhviHeader (same position on all screens) ──
                const AhviHeader(),
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 132),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            FadeTransition(
                              opacity: _headerOpacity,
                              child: SlideTransition(
                                position: _headerSlide,
                                child: _buildHeader(),
                              ),
                            ),
                            const SizedBox(height: _S.lg),
                            FadeTransition(
                              opacity: _toggleOpacity,
                              child: SlideTransition(
                                position: _toggleSlide,
                                child: _buildToggle(),
                              ),
                            ),
                            const SizedBox(height: _S.base + _S.xs),
                            FadeTransition(
                              opacity: _sectionOpacity,
                              child: SlideTransition(
                                position: _sectionSlide,
                                child: AnimatedSwitcher(
                                  duration: _A.slow,
                                  switchInCurve: _A.ease,
                                  switchOutCurve: _A.ease,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                  child: KeyedSubtree(
                                    key: ValueKey(_isLifeTab),
                                    child: _isLifeTab
                                        ? _buildLifeSection()
                                        : _buildBoardsSection(),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ), // Expanded(CustomScrollView)
              ],
            ),
          ), // SafeArea(Column)
        ],
      ),
    );
  }

  // _buildCreateBoardOverlay removed — now uses showDialog via _openCreateBoardDialog

  Widget _buildAmbientBg() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.8),
              radius: 1.0,
              colors: [
                _accent2.withValues(alpha: 0.20),
                _card.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.6, 0.6),
              radius: 1.0,
              colors: [
                _accent2.withValues(alpha: 0.14),
                _card.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.t(context, 'boards_planner'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: -0.8,
                color: _text,
              ),
            ),
          ],
        ),
        const SizedBox(height: _S.sm),
        Text(
          AppLocalizations.t(context, 'boards_life_tagline'),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: _muted,
            letterSpacing: 0.15,
          ),
        ),
      ],
    );
  }

  Widget _buildToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _panelBorder, width: 1.5),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(_S.xs),
      child: Row(
        children: [
          Expanded(
            child: _ToggleButton(
              label: AppLocalizations.t(context, 'boards_life'),
              icon: Icons.auto_awesome_rounded,
              isActive: _isLifeTab,
              activeShellColor: _text,
              activeTextColor: _theme.backgroundPrimary,
              inactiveTextColor: _muted,
              accentColor: _accent,
              onTap: () => _switchTab(true),
            ),
          ),
          Expanded(
            child: _ToggleButton(
              label: AppLocalizations.t(context, 'boards_boards'),
              icon: Icons.grid_view_rounded,
              isActive: !_isLifeTab,
              activeShellColor: _text,
              activeTextColor: _theme.backgroundPrimary,
              inactiveTextColor: _muted,
              accentColor: _accent,
              onTap: () => _switchTab(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifeSection() {
    const lifeContentColor = Colors.white;

    return Column(
      children: [
        _StaggeredCard(
          delay: const Duration(milliseconds: 100),
          child: CalendarCard(
            cardColor: _card,
            borderColor: _cardBorder,
            panelColor: _panel,
            panelBorder: _panelBorder,
            textColor: lifeContentColor,
            mutedColor: _muted,
            accent: const Color(0xFFB48EFF),
            accentSoft: const Color(0xFFD4B8FF),
            shellColor: _shell,
            iconColor: _cardIconColor,
          ),
        ),
        const SizedBox(height: _S.md),

        Row(
          children: [
            Expanded(
              child: _StaggeredCard(
                delay: const Duration(milliseconds: 170),
                child: _VCard(
                  fullWidth: false,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFB08F), Color(0xFFFF8F72)],
                  ),
                  shadowColor: const Color(0xFFFF8F72).withValues(alpha: 0.30),
                  badge: '12',
                  badgeTextColor: _accent,
                  badgeBg: _card,
                  badgeBorderColor: _accent.withValues(alpha: 0.25),
                  iconBg: _card,
                  iconWidget: Icon(
                    Icons.checkroom_rounded,
                    size: 32,
                    color: _cardIconColor,
                  ),
                  title: AppLocalizations.t(context, 'boards_daily_wear'),
                  titleColor: lifeContentColor,
                  subtitle: AppLocalizations.t(
                    context,
                    'boards_daily_wear_sub',
                  ),
                  subtitleColor: lifeContentColor,
                  arrowBg: _card,
                  arrowColor: _cardIconColor,
                  shellColor: _shell,
                  onTap: () => _push(
                    const daily_wear.DailyWearScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: _S.md),
            Expanded(
              child: _StaggeredCard(
                delay: const Duration(milliseconds: 240),
                child: _VCard(
                  fullWidth: false,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFE07E), Color(0xFFFFC956)],
                  ),
                  shadowColor: const Color(0xFFFFC956).withValues(alpha: 0.30),
                  badge: '5',
                  badgeTextColor: _accent2,
                  badgeBg: _card,
                  badgeBorderColor: _accent2.withValues(alpha: 0.25),
                  iconBg: _card,
                  iconWidget: Icon(
                    Icons.home_rounded,
                    size: 32,
                    color: _cardIconColor,
                  ),
                  title: AppLocalizations.t(context, 'boards_home_utilities'),
                  titleColor: lifeContentColor,
                  subtitle: AppLocalizations.t(
                    context,
                    'boards_home_utilities_sub',
                  ),
                  subtitleColor: lifeContentColor,
                  arrowBg: _card,
                  arrowColor: _cardIconColor,
                  shellColor: _shell,
                  // <-- FIX: Now properly points to BillsScreen!
                  onTap: () => _push(const home_utils.HomeUtilitiesScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: _S.md),
        Row(
          children: [
            Expanded(
              child: _StaggeredCard(
                delay: const Duration(milliseconds: 310),
                child: _VCard(
                  fullWidth: false,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFBFDC), Color(0xFFFF96C7)],
                  ),
                  shadowColor: const Color(0xFFFF96C7).withValues(alpha: 0.30),
                  badge: 'AM · PM',
                  badgeTextColor: _accent,
                  badgeBg: _panelBorder,
                  badgeBorderColor: _cardBorder,
                  iconBg: _panel,
                  iconWidget: Icon(
                    Icons.water_drop_rounded,
                    size: 32,
                    color: _cardIconColor,
                  ),
                  title: AppLocalizations.t(context, 'boards_skincare'),
                  titleColor: lifeContentColor,
                  subtitle: AppLocalizations.t(context, 'boards_skincare_sub'),
                  subtitleColor: lifeContentColor,
                  arrowBg: _panel,
                  arrowColor: _cardIconColor,
                  shellColor: _shell,
                  onTap: () => _push(const SkincareScreen()),
                ),
              ),
            ),
            const SizedBox(width: _S.md),
            Expanded(
              child: _StaggeredCard(
                delay: const Duration(milliseconds: 380),
                child: _VCard(
                  fullWidth: false,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF6EE7B7), Color(0xFF34D399)],
                  ),
                  shadowColor: const Color(0xFF34D399).withValues(alpha: 0.30),
                  badge: 'Track',
                  badgeTextColor: _accent,
                  badgeBg: _panelBorder,
                  badgeBorderColor: _cardBorder,
                  iconBg: _panel,
                  iconWidget: Icon(
                    Icons.monitor_heart_rounded,
                    size: 32,
                    color: _cardIconColor,
                  ),
                  title: AppLocalizations.t(context, 'boards_diet_fitness'),
                  titleColor: lifeContentColor,
                  subtitle: AppLocalizations.t(
                    context,
                    'boards_diet_fitness_sub',
                  ),
                  subtitleColor: lifeContentColor,
                  arrowBg: _panel,
                  arrowColor: _cardIconColor,
                  shellColor: _shell,
                  onTap: () => _push(const diet_fitness.DietAndFitnessScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBoardsSection() {
    final predefinedBoards = _predefinedBoardCards();
    final customBoards = _customBoardCards();

    return Column(
      children: [
        _StaggeredCard(
          delay: const Duration(milliseconds: 180),
          child: _VCard(
            fullWidth: true,
            minHeight: 92,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFC7B6FF), Color(0xFF9A84FF)],
            ),
            shadowColor: const Color(0xFF9A84FF).withValues(alpha: 0.28),
            badge: null,
            badgeTextColor: Colors.transparent,
            badgeBg: Colors.transparent,
            badgeBorderColor: Colors.transparent,
            iconBg: _panel,
            iconWidget: Icon(
              Icons.add_circle_outline_rounded,
              size: 28,
              color: _cardIconColor,
            ),
            title: AppLocalizations.t(context, 'boards_create_own'),
            titleColor: Colors.white,
            titleSize: 15,
            subtitle: AppLocalizations.t(context, 'boards_create_own_sub'),
            subtitleColor: Colors.white,
            arrowBg: _panel,
            arrowColor: _cardIconColor,
            shellColor: _shell,
            onTap: _openCreateBoardDialog,
          ),
        ),
        const SizedBox(height: _S.md),
        _buildTwoColumnBoardGrid(predefinedBoards, startDelayMs: 80),
        const SizedBox(height: _S.md),
        if (customBoards.isNotEmpty) ...[
          _buildTwoColumnBoardGrid(customBoards, startDelayMs: 260),
          const SizedBox(height: _S.md),
        ],
        _StaggeredCard(
          delay: const Duration(milliseconds: 320),
          child: _EverythingElseCard(
            gradientStart: const Color(0xFFFFBFDC),
            gradientEnd: const Color(0xFFFF96C7),
            cardColor: _card,
            textColor: Colors.white,
            iconColor: _cardIconColor,
            panelColor: _panel,
            shellColor: _shell,
            onTap: () => _push(const everything_else.EverythingElseScreen()),
          ),
        ),
        const SizedBox(height: _S.md),
        _StaggeredCard(
          delay: const Duration(milliseconds: 400),
          child: _FavouritesCard(
            gradientStart: const Color(0xFFFF8FAB),
            gradientEnd: const Color(0xFFFF5C87),
            cardColor: _card,
            textColor: Colors.white,
            iconColor: _cardIconColor,
            panelColor: _panel,
            shellColor: _shell,
            onTap: () => _push(
              OccasionBoard(
                occasion: 'Favourites',
                titleKey: 'boards_favourites',
                subtitleKey: 'boards_favourites_sub',
                emptyEmoji: '❤️',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BoardCardConfig {
  final Gradient gradient;
  final Color shadowColor;
  final Color iconBg;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _BoardCardConfig({
    required this.gradient,
    required this.shadowColor,
    required this.iconBg,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onDelete,
  });
}

class _ToggleButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeShellColor;
  final Color activeTextColor;
  final Color inactiveTextColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeShellColor,
    required this.activeTextColor,
    required this.inactiveTextColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: _A.slow,
      value: widget.isActive ? 1.0 : 0.0,
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(parent: _scaleCtrl, curve: _A.spring));
  }

  @override
  void didUpdateWidget(_ToggleButton old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        _scaleCtrl.forward();
      } else {
        _scaleCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: _A.slow,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: widget.isActive ? widget.activeShellColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: widget.isActive
              ? [
            BoxShadow(
              color: widget.accentColor.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ]
              : null,
        ),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: widget.isActive
                    ? widget.activeTextColor
                    : widget.inactiveTextColor,
              ),
              const SizedBox(width: 7),
              AnimatedDefaultTextStyle(
                duration: _A.slow,
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.isActive
                      ? widget.activeTextColor
                      : widget.inactiveTextColor,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Matrix4 _scaleTranslate(double scale, double dy) {
  return Matrix4.translationValues(0.0, dy, 0.0)
    ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0));
}

class _VCard extends StatefulWidget {
  final bool fullWidth;
  final double minHeight;
  final Gradient gradient;
  final Color shadowColor;
  final String? badge;
  final Color badgeTextColor;
  final Color badgeBg;
  final Color badgeBorderColor;
  final Color iconBg;
  final Widget iconWidget;
  final String title;
  final Color titleColor;
  final double titleSize;
  final String subtitle;
  final Color subtitleColor;
  final Color arrowBg;
  final Color arrowColor;
  final Color shellColor;
  final VoidCallback? onTap;

  const _VCard({
    required this.fullWidth,
    this.minHeight = 130,
    required this.gradient,
    required this.shadowColor,
    required this.badge,
    required this.badgeTextColor,
    required this.badgeBg,
    required this.badgeBorderColor,
    required this.iconBg,
    required this.iconWidget,
    required this.title,
    required this.titleColor,
    this.titleSize = 13.5,
    required this.subtitle,
    required this.subtitleColor,
    required this.arrowBg,
    required this.arrowColor,
    required this.shellColor,
    this.onTap,
  });

  @override
  State<_VCard> createState() => _VCardState();
}

class _VCardState extends State<_VCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  late final AnimationController _iconCtrl;
  late final Animation<double> _iconRotate;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    _iconCtrl = AnimationController(vsync: this, duration: _A.normal);
    _iconRotate = Tween<double>(
      begin: 0.0,
      end: -6 * math.pi / 180,
    ).animate(CurvedAnimation(parent: _iconCtrl, curve: _A.spring));
    _iconScale = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _iconCtrl, curve: _A.spring));
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    super.dispose();
  }

  void _onEnter() {
    setState(() => _isHovered = true);
    _iconCtrl.forward();
  }

  void _onExit() {
    setState(() {
      _isHovered = false;
      _isPressed = false;
    });
    _iconCtrl.reverse();
  }

  double get _scale {
    if (_isPressed) return 0.97;
    if (_isHovered) return 1.02;
    return 1.0;
  }

  double get _yOffset => _isHovered && !_isPressed ? -4.0 : 0.0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: _A.normal,
          curve: _A.spring,
          width: widget.fullWidth ? double.infinity : null,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          transform: _scaleTranslate(_scale, _yOffset),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: widget.shadowColor,
                blurRadius: _isHovered
                    ? math.max(0.0, (widget.fullWidth ? 28 : 20) + 18.0)
                    : (widget.fullWidth ? 28.0 : 20.0),
                offset: Offset(0, widget.fullWidth ? 8 : 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            _S.base,
            _S.base + _S.xs,
            _S.base,
            _S.base,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _iconCtrl,
                    builder: (_, child) => Transform.rotate(
                      angle: _iconRotate.value,
                      child: Transform.scale(
                        scale: _iconScale.value,
                        child: child,
                      ),
                    ),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.iconBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(child: widget.iconWidget),
                    ),
                  ),
                  const SizedBox(height: _S.sm + _S.xs),
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: widget.titleSize,
                      fontWeight: FontWeight.w700,
                      color: widget.titleColor,
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: _S.xs),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11.5,
                      color: widget.subtitleColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: _S.xl),
                ],
              ),
              if (widget.badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.badgeBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.badgeBorderColor),
                    ),
                    child: Text(
                      widget.badge!,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: widget.badgeTextColor,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                right: 0,
                child: AnimatedContainer(
                  duration: _A.medium,
                  curve: _A.spring,
                  width: 22,
                  height: 22,
                  transform: Matrix4.translationValues(
                    _isHovered ? 2.0 : 0.0,
                    0.0,
                    0.0,
                  ),
                  decoration: BoxDecoration(
                    color: _isHovered ? widget.shellColor : widget.arrowBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: _A.fast,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        key: ValueKey(_isHovered),
                        size: 14,
                        color: _isHovered
                            ? context.themeTokens.textPrimary
                            : widget.arrowColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EverythingElseCard extends StatefulWidget {
  final Color gradientStart;
  final Color gradientEnd;
  final Color cardColor;
  final Color textColor;
  final Color iconColor;
  final Color panelColor;
  final Color shellColor;
  final VoidCallback? onTap;

  const _EverythingElseCard({
    required this.gradientStart,
    required this.gradientEnd,
    required this.cardColor,
    required this.textColor,
    required this.iconColor,
    required this.panelColor,
    required this.shellColor,
    this.onTap,
  });

  @override
  State<_EverythingElseCard> createState() => _EverythingElseCardState();
}

class _EverythingElseCardState extends State<_EverythingElseCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  double get _scale {
    if (_isPressed) return 0.97;
    if (_isHovered) return 1.02;
    return 1.0;
  }

  double get _yOffset => _isHovered && !_isPressed ? -4.0 : 0.0;

  @override
  Widget build(BuildContext context) {
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
          duration: _A.normal,
          curve: _A.spring,
          transform: _scaleTranslate(_scale, _yOffset),
          transformAlignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 110),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [widget.gradientStart, widget.gradientEnd],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: widget.gradientEnd.withValues(alpha: 0.30),
                blurRadius: _isHovered ? 46 : 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            _S.base,
            _S.base + _S.xs,
            _S.base,
            _S.base,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.cardColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    Icons.explore_rounded,
                    size: 26,
                    color: widget.iconColor,
                  ),
                ),
              ),
              const SizedBox(width: _S.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.t(context, 'boards_everything_else'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: widget.textColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: _S.xs - 1),
                    Text(
                      AppLocalizations.t(context, 'boards_everything_else_sub'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: _A.medium,
                curve: _A.spring,
                width: 22,
                height: 22,
                transform: Matrix4.translationValues(
                  _isHovered ? 2.0 : 0.0,
                  0.0,
                  0.0,
                ),
                decoration: BoxDecoration(
                  color: _isHovered ? widget.shellColor : widget.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: _isHovered
                        ? context.themeTokens.textPrimary
                        : widget.iconColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Favourites Card ───────────────────────────────────────────────────────────
class _FavouritesCard extends StatefulWidget {
  final Color gradientStart;
  final Color gradientEnd;
  final Color cardColor;
  final Color textColor;
  final Color iconColor;
  final Color panelColor;
  final Color shellColor;
  final VoidCallback? onTap;

  const _FavouritesCard({
    required this.gradientStart,
    required this.gradientEnd,
    required this.cardColor,
    required this.textColor,
    required this.iconColor,
    required this.panelColor,
    required this.shellColor,
    this.onTap,
  });

  @override
  State<_FavouritesCard> createState() => _FavouritesCardState();
}

class _FavouritesCardState extends State<_FavouritesCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  double get _scale {
    if (_isPressed) return 0.97;
    if (_isHovered) return 1.02;
    return 1.0;
  }

  double get _yOffset => _isHovered && !_isPressed ? -4.0 : 0.0;

  @override
  Widget build(BuildContext context) {
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
          duration: _A.normal,
          curve: _A.spring,
          transform: _scaleTranslate(_scale, _yOffset),
          transformAlignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 110),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [widget.gradientStart, widget.gradientEnd],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: widget.gradientEnd.withValues(alpha: 0.30),
                blurRadius: _isHovered ? 46 : 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            _S.base,
            _S.base + _S.xs,
            _S.base,
            _S.base,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.cardColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 26,
                    color: widget.iconColor,
                  ),
                ),
              ),
              const SizedBox(width: _S.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.t(context, 'boards_favourites'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: widget.textColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: _S.xs - 1),
                    Text(
                      AppLocalizations.t(context, 'boards_favourites_sub'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: _A.medium,
                curve: _A.spring,
                width: 22,
                height: 22,
                transform: Matrix4.translationValues(
                  _isHovered ? 2.0 : 0.0,
                  0.0,
                  0.0,
                ),
                decoration: BoxDecoration(
                  color: _isHovered ? widget.shellColor : widget.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: _isHovered
                        ? context.themeTokens.textPrimary
                        : widget.iconColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Staggered entrance animation used for board cards.
class _StaggeredCard extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _StaggeredCard({required this.child, required this.delay});

  @override
  State<_StaggeredCard> createState() => _StaggeredCardState();
}

class _StaggeredCardState extends State<_StaggeredCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _A.entry);
    _opacity = CurvedAnimation(parent: _ctrl, curve: _A.pageEntry);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: _A.pageEntry));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasStarted) return;
      _hasStarted = true;
      Future.delayed(widget.delay, () {
        if (!mounted) return;
        if (_ctrl.value < 1.0) _ctrl.forward();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When TickerMode re-enables (tab re-selected), ensure card is fully visible.
    if (_hasStarted && _ctrl.value < 1.0) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _HoverPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  // ignore: unused_element_parameter
  final double hoverScale;
  final double pressScale;

  const _HoverPressButton({
    required this.child,
    required this.onTap,
    this.hoverScale = 1.05,
    this.pressScale = 0.95,
  });

  @override
  State<_HoverPressButton> createState() => _HoverPressButtonState();
}

class _HoverPressButtonState extends State<_HoverPressButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  double get _scale {
    if (_isPressed) return widget.pressScale;
    if (_isHovered) return widget.hoverScale;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
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
          duration: _A.fast,
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(_scale, _scale, 1.0),
          transformAlignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Create Board Dialog ────────────────────────────────────────────────────────
class _CreateBoardDialog extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final Color card;
  final Color cardBorder;
  final Color text;
  final Color muted;
  final VoidCallback onSubmit;

  const _CreateBoardDialog({
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.muted,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use explicit opaque colors so dialog never bleeds background cards through
    final dialogBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final inputFill = isDark
        ? const Color(0xFF2A2A3E)
        : const Color(0xFFF3F3F7);

    return Dialog(
      backgroundColor: dialogBg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.t(context, 'boards_create_own'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.t(context, 'boards_create_own_sub'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: muted,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: text,
                ),
                decoration: InputDecoration(
                  labelText: AppLocalizations.t(context, 'boards_name_it'),
                  labelStyle: TextStyle(
                    fontFamily: 'Inter',
                    color: muted,
                    fontSize: 13,
                  ),
                  hintText: AppLocalizations.t(context, 'boards_enter_name'),
                  hintStyle: TextStyle(fontFamily: 'Inter', color: muted),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                    child: Text(
                      AppLocalizations.t(context, 'common_cancel'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: onSubmit,
                    child: Text(
                      AppLocalizations.t(context, 'common_create'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
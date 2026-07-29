import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/medi_tracker.dart' as medi_tracker;
import 'package:myapp/bills_page.dart' as bills;
import 'package:myapp/contacts.dart' as contacts;
import 'package:myapp/theme/theme_tokens.dart';

// ─────────────────────────────────────────────
//  CUSTOM PAINTERS (unchanged from original)
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
//  HOME & UTILITIES SCREEN — Premium upgrade
//  • Uses AppThemeTokens for consistent theming
//  • Staggered entrance animation on header + tabs
//  • Haptic feedback on tab switches
//  • Custom styled header (matching boards.dart)
// ─────────────────────────────────────────────
class HomeUtilitiesScreen extends StatefulWidget {
  const HomeUtilitiesScreen({super.key});

  @override
  State<HomeUtilitiesScreen> createState() => _HomeUtilitiesScreenState();
}

class _HomeUtilitiesScreenState extends State<HomeUtilitiesScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // ── Entrance animation ──
  late final AnimationController _entranceCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _tabsFade;
  late final Animation<Offset> _tabsSlide;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        HapticFeedback.selectionClick();
      } else if (mounted) {
        setState(() {});
      }
    });

    // Staggered entrance: header 0–50%, tabs 25–75%
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _headerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
      ),
    );
    _headerSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
          ),
        );

    _tabsFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.25, 0.75, curve: Curves.easeOutCubic),
      ),
    );
    _tabsSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.25, 0.75, curve: Curves.easeOutCubic),
          ),
        );

    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;

    return Scaffold(
      backgroundColor: t.backgroundPrimary,
      body: Column(
        children: [
          // ── Custom header (replaces plain AppBar) ──
          AnimatedBuilder(
            animation: _entranceCtrl,
            builder: (context, child) => FadeTransition(
              opacity: _headerFade,
              child: SlideTransition(position: _headerSlide, child: child),
            ),
            child: _buildHeader(t),
          ),

          // ── Custom tab bar ──
          AnimatedBuilder(
            animation: _entranceCtrl,
            builder: (context, child) => FadeTransition(
              opacity: _tabsFade,
              child: SlideTransition(position: _tabsSlide, child: child),
            ),
            child: _buildTabBar(t),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabController.index,
              children: const [
                RepaintBoundary(child: medi_tracker.MediTrackScreen()),
                RepaintBoundary(child: bills.BillsScreen()),
                RepaintBoundary(child: contacts.ContactsScreen()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader(AppThemeTokens t) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 8,
        20,
        8,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.cardBorder),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                color: t.textPrimary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: AppLocalizations.t(context, 'home_title_bold'),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                TextSpan(
                  text: AppLocalizations.t(context, 'home_title_light'),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ──
  Widget _buildTabBar(AppThemeTokens t) {
    return ClipRect(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.cardBorder),
        ),
        child: TabBar(
          controller: _tabController,
          padding: EdgeInsets.zero,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          indicator: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.accent.primary, t.accent.tertiary],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: t.accent.primary.withValues(alpha: 0.30),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: t.tileText,
          unselectedLabelColor: t.mutedText,
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: [
            Tab(text: AppLocalizations.t(context, 'home_tab_medi')),
            Tab(text: AppLocalizations.t(context, 'home_tab_bills')),
            Tab(text: AppLocalizations.t(context, 'home_tab_contacts')),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Press-scale feedback button
// ─────────────────────────────────────────────
class _PressScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressScaleButton({required this.child, required this.onTap});

  @override
  State<_PressScaleButton> createState() => _PressScaleButtonState();
}

class _PressScaleButtonState extends State<_PressScaleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

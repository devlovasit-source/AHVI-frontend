import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myapp/navigation/ahvi_back_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:myapp/boards.dart';
import 'package:myapp/home.dart' as home;
import 'package:myapp/onboarding1.dart';
import 'package:myapp/onboarding2.dart';
import 'package:myapp/onboarding3.dart';
import 'package:myapp/profile.dart';
import 'package:myapp/signin.dart';
import 'package:myapp/app_routes.dart';
import 'package:myapp/splash_screen.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/config/env.dart';
import 'package:myapp/home_card_summary_provider.dart';

// ─── NEW FEATURE IMPORTS ───
import 'package:myapp/skincare.dart';
import 'package:myapp/bills_page.dart';
import 'package:myapp/calendar.dart';
import 'package:myapp/diet_fitness.dart';
import 'package:myapp/medi_tracker.dart';

import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/base_theme.dart';
import 'package:myapp/theme/theme_controller.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/backend_service.dart'; // <-- Added Backend Service
import 'package:myapp/services/connectivity_watcher.dart';
import 'package:myapp/services/notification_service.dart';
import 'package:myapp/services/offline_cache.dart';
import 'package:myapp/services/offline_sync_bootstrap.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // 🆕 Localization
import 'package:myapp/app_localizations.dart'; // 🆕 Localization

final GlobalKey<NavigatorState> ahviNavigatorKey =
    GlobalKey<NavigatorState>();

void _openMediFromNotification(Map<String, String> data) {
  void push() {
    final navigator = ahviNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushNamed(AppRoutes.medi, arguments: data);
  }

  if (ahviNavigatorKey.currentState == null) {
    Future<void>.delayed(const Duration(milliseconds: 600), push);
    return;
  }

  push();
}

Future<void> main() async {
  // Ensure Flutter bindings are initialized before calling async methods
  WidgetsFlutterBinding.ensureInitialized();

  // Load the .env file
  await dotenv.load(fileName: ".env");
  Env.debugPrintMissingConfig();
  Env.debugPrintRuntimeTarget();
  AhviNotificationService.instance.configureMediReminderHandler(
    _openMediFromNotification,
  );

  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
//  SPACING CONSTANTS  (4-pt grid)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _S {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double base = 16.0;
  static const double xl = 32.0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ANIMATION CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
abstract final class _A {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration sheet = Duration(milliseconds: 420);

  static const Curve spring = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Curve sheetIn = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve ease = Curves.easeOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────────────────────────────────────
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // 🆕 ఏ screen నుండైనా language మార్చడానికి
  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Maps profile language name → locale code
  static Locale _langToLocale(String lang) {
    const map = {
      'English': 'en',
      'Hindi': 'hi',
      'Tamil': 'ta',
      'Telugu': 'te',
      'Kannada': 'kn',
      'Malayalam': 'ml',
      'Bengali': 'bn',
      'Marathi': 'mr',
    };
    return Locale(map[lang] ?? 'en');
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => ThemeController()..loadTheme(),
        ),
        ChangeNotifierProvider(create: (context) => ProfileController()),
        ChangeNotifierProvider<AppwriteService>(
          create: (_) => AppwriteService(),
        ),
        ProxyProvider<AppwriteService, BackendService>(
          update: (_, appwrite, _) => BackendService(appwriteService: appwrite),
        ),
        ChangeNotifierProvider<ConnectivityWatcher>(
          create: (_) => ConnectivityWatcher()..init(),
        ),
        ChangeNotifierProvider<OfflineCache>(create: (_) => OfflineCache()),
        ChangeNotifierProxyProvider2<AppwriteService, BackendService,
            HomeCardSummaryProvider>(
          create: (_) => HomeCardSummaryProvider(),
          update: (_, appwrite, backend, p) =>
              p!..configure(backend, appwrite),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, controller, child) {
          final accent = getAccentPalette(controller.currentTheme);
          final lightTokens = AppThemeTokens.light(accent);
          final darkTokens = AppThemeTokens.dark(accent);
          final lightTheme = BaseTheme.light.copyWith(
            colorScheme: BaseTheme.light.colorScheme.copyWith(
              primary: accent.primary,
              secondary: accent.secondary,
              tertiary: accent.tertiary,
            ),
            extensions: [lightTokens],
          );
          final darkTheme = BaseTheme.dark.copyWith(
            colorScheme: BaseTheme.dark.colorScheme.copyWith(
              primary: accent.primary,
              secondary: accent.secondary,
              tertiary: accent.tertiary,
            ),
            extensions: [darkTokens],
          );
          return Selector<ProfileController, String>(
            // Only rebuild MaterialApp when lang actually changes — not on every notifyListeners()
            selector: (_, p) => p.state.lang,
            builder: (context, lang, _) {
              return MaterialApp(
                navigatorKey: ahviNavigatorKey,
                debugShowCheckedModeBanner: false,
                theme: lightTheme,
                darkTheme: darkTheme,
                themeMode: controller.themeMode,
                // Disable theme lerp animation — prevents the washed-out fade
                // that occurs while colors interpolate between light ↔ dark tokens.
                themeAnimationDuration: Duration.zero,

                // Locale driven directly by ProfileController — updates all screens
                locale: _langToLocale(lang),
                supportedLocales: const [
                  Locale('en'),
                  Locale('hi'),
                  Locale('ta'),
                  Locale('te'),
                  Locale('kn'),
                  Locale('ml'),
                  Locale('bn'),
                  Locale('mr'),
                ],
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],

                home: const OfflineSyncBootstrap(child: AuthWrapper()),

                routes: {
                  AppRoutes.intro: (_) => const SignInScreen(),
                  AppRoutes.signin: (_) => const SignInScreen(),
                  AppRoutes.emailAuth: (_) => const EmailOTPLoginScreen(),
                  AppRoutes.main: (_) => const MainNavigationShell(),
                  AppRoutes.onboarding1: (_) => const Screen1(),
                  AppRoutes.onboarding2: (_) => const Screen2(),
                  AppRoutes.onboarding3: (_) => const Screen3(),

                  // ─── NEW FEATURE ROUTES REGISTERED HERE ───
                  AppRoutes.skincare: (_) => const SkincareScreen(),
                  AppRoutes.bills: (_) => const BillsScreen(),
                  AppRoutes.wardrobe: (_) => const WardrobeScreen(),
                  AppRoutes.calendar: (_) => const CalendarShell(),
                  AppRoutes.boards: (_) => const BoardsScreen(),
                  AppRoutes.medi: (_) =>
                      const MediTrackScreen(fromHome: true),
                },

                // DailyWear uses PageRouteBuilder to skip the default
                // slide+fade transition that causes the washed-out look on APK.
                onGenerateRoute: (settings) {
                  if (settings.name == AppRoutes.workout) {
                    return PageRouteBuilder(
                      settings: settings,
                      pageBuilder: (_, _, _) => const DietAndFitnessScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      transitionsBuilder: (_, _, _, child) => child,
                    );
                  }
                  return null; // fall through to routes map
                },
              ); // MaterialApp
            }, // Selector builder
          ); // Selector
        }, // Consumer
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NAV ITEMS
// ─────────────────────────────────────────────────────────────────────────────
// Nav items are now built dynamically inside _buildBottomNav()
// so they respond to locale changes automatically.

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN NAVIGATION SHELL
// ─────────────────────────────────────────────────────────────────────────────
class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _toastVisible = false;
  Timer? _toastTimer;
  final List<int> _tabHistory = <int>[];

  late final List<AnimationController> _navRiseCtrls;

  // Pages are built in build() so locale changes trigger proper rebuilds.
  // PageStorageKey preserves scroll state across tab switches.

  // 🔧 FIX: Palette switch tracking
  Color? _cachedAccent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tok = Theme.of(context).extension<AppThemeTokens>();
    final newAccent = tok?.accent.primary;
    if (_cachedAccent != null && _cachedAccent != newAccent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _cachedAccent = newAccent;
  }

  @override
  void initState() {
    super.initState();

    _navRiseCtrls = List.generate(
      5,
          (i) => AnimationController(vsync: this, duration: _A.normal, value: 0.0),
    );

    // Home tab (index 0) active గా start చేయి
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _navRiseCtrls[0].animateTo(1.0, curve: _A.spring);
      }
    });
  }

  @override
  void dispose() {
    for (final ctrl in _navRiseCtrls) {
      ctrl.dispose();
    }
    _toastTimer?.cancel();
    super.dispose();
  }

  // ── Tab switching ──────────────────────────────────────────────────────────
  void _switchToIndex(int index, {bool addToHistory = true}) {
    if (index == _currentIndex) return;
    if (addToHistory && _currentIndex != -1) {
      _tabHistory.remove(index);
      _tabHistory.add(_currentIndex);
    }
    HapticFeedback.selectionClick();
    if (_currentIndex != -1) {
      _navRiseCtrls[_currentIndex].animateTo(
        0.0,
        curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      );
    }
    _navRiseCtrls[index].animateTo(1.0, curve: _A.spring);
    setState(() => _currentIndex = index);
  }

  bool _handleShellBack() {
    if (_tabHistory.isNotEmpty) {
      final previousIndex = _tabHistory.removeLast();
      _switchToIndex(previousIndex, addToHistory: false);
      return true;
    }
    // No tab history — if we're not already on Home (0), go there.
    // This prevents Android's predictive-back gesture from closing the
    // app when the user back-swipes on Wardrobe (or any non-Home tab)
    // without having navigated from another tab first.
    if (_currentIndex != 0) {
      _switchToIndex(0, addToHistory: false);
      return true;
    }
    // Already on Home with no history → allow the OS to exit the app normally.
    return false;
  }

  void _handleNavTap(int idx) {
    if (idx == 4) {
      _showComingSoon();
      return;
    }
    _switchToIndex(idx);
  }

  // ── Coming-soon toast ──────────────────────────────────────────────────────
  void _showComingSoon() {
    HapticFeedback.lightImpact();
    setState(() => _toastVisible = true);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ✅ Built here so locale changes rebuild nav labels automatically
    final l = AppLocalizations.of(context);
    final navItems = <({IconData icon, String label})>[
      (icon: Icons.home_outlined, label: l?.translate('home') ?? 'Home'),
      (
      icon: Icons.dry_cleaning_outlined,
      label: l?.translate('wardrobe') ?? 'Wardrobe',
      ),
      (
      icon: Icons.grid_view_rounded,
      label: l?.translate('planner') ?? 'Planner',
      ),
      (
      icon: Icons.explore_outlined,
      label: l?.translate('explore') ?? 'Explore',
      ),
    ];

    // ✅ Built here so locale changes cause a full rebuild of all screens
    // Order must match navItems exactly: Home(0), Wardrobe(1), Planner(2), Explore(3)
    final pages = <Widget>[
      _HomePageHost(
        key: const PageStorageKey('home'),
        onNavTapRequested: _switchToIndex,
      ),
      const WardrobeScreen(key: PageStorageKey('wardrobe')),
      const BoardsScreen(key: PageStorageKey('boards')),
      const _ExploreComingSoon(key: PageStorageKey('explore')),
    ];
    return NotificationListener<ShellBackNavigationNotification>(
      onNotification: (notification) => _handleShellBack(),
      child: AhviShellBackScope(
        // 🔧 FIX: was `canPop: _tabHistory.isEmpty`, which toggled true/false
        // based on tab history. That let the OS start a *real* interactive
        // swipe-back / predictive-back transition whenever history was empty,
        // then flip to false mid-gesture in other cases — the interactive
        // pop animation and our manual IndexedStack index swap (setState in
        // _switchToIndex) would race, leaving the screen visually stuck
        // half-swiped. Keeping canPop constantly false means the swipe/back
        // gesture is *never* treated as a real route pop here — it's always
        // a clean, instant tab switch via onPopInvokedWithResult, so there's
        // no interactive transition left half-finished.
        onBack: _handleShellBack,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          // 🔧 FIX: Keyboard open అయినా nav bar పైకి వెళ్ళకూడదు
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // Page content
              Positioned.fill(
                child: IndexedStack(
                  index: _currentIndex,
                  children: List<Widget>.generate(navItems.length, (index) {
                    return TickerMode(
                      enabled: index == _currentIndex,
                      child: pages[index],
                    );
                  }),
                ),
              ),

              // Floating bottom nav — keyboard వచ్చినా fixed గా ఉంటుంది
              Positioned(
                left: _S.base,
                right: _S.base,
                bottom: MediaQuery.paddingOf(context).bottom + _S.sm,
                child: _buildBottomNav(navItems),
              ),

              // Coming-soon toast
              _buildComingSoonToast(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav(List<({IconData icon, String label})> navItems) {
    const pillH = 64.0;
    const maxBulge = 11.0;
    const totalH = pillH + maxBulge + 6.0;

    return SizedBox(
      height: totalH,
      child: AnimatedBuilder(
        animation: Listenable.merge(_navRiseCtrls),
        builder: (context, child) {
          // 🔧 FIX: builder లోపల read చేయాలి — palette switch కి respond అవ్వాలి
          final t = context.themeTokens;
          final activeIdx = _currentIndex;
          final bulgeT = _navRiseCtrls[activeIdx].value;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Morphing pill background
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: totalH,
                child: CustomPaint(
                  painter: _NavPillPainter(
                    activeIdx: activeIdx,
                    itemCount: navItems.length,
                    bulgeT: bulgeT,
                    pillH: pillH,
                    maxBulge: maxBulge,
                    fillColor: t.phoneShellInner,
                    borderColor: t.cardBorder,
                    glowColor: t.accent.primary,
                  ),
                ),
              ),

              // Nav item row
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: pillH,
                child: Row(
                  children: List.generate(navItems.length, (i) {
                    final active = activeIdx == i;
                    final rise = -10.0 * _navRiseCtrls[i].value;
                    final item = navItems[i];

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _handleNavTap(i),
                        behavior: HitTestBehavior.opaque,
                        child: Transform.translate(
                          offset: Offset(0, rise),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: _A.medium,
                                curve: Curves.easeOut,
                                width: 44,
                                height: 44,
                                decoration: active
                                    ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      t.accent.primary,
                                      t.accent.secondary,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: t.accent.primary.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: t.accent.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 28,
                                    ),
                                  ],
                                )
                                    : null,
                                child: Icon(
                                  item.icon,
                                  color: active ? t.textPrimary : t.mutedText,
                                  size: active ? 21 : 20,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AnimatedDefaultTextStyle(
                                duration: _A.medium,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: active ? t.textPrimary : t.mutedText,
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                                child: Text(item.label),
                              ),
                            ],
                          ),
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
    );
  }

  // ── Coming-soon toast ──────────────────────────────────────────────────────
  Widget _buildComingSoonToast() {
    final t = context.themeTokens;
    return Positioned(
      bottom: 110,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _toastVisible ? 1.0 : 0.0,
          duration: _A.normal,
          child: AnimatedSlide(
            offset: _toastVisible ? Offset.zero : const Offset(0, 0.3),
            duration: _A.normal,
            curve: Curves.easeOutBack,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: t.backgroundSecondary.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.cardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: t.backgroundPrimary.withValues(alpha: 0.18),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      color: t.accent.primary,
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Coming Soon',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: t.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
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

// ═════════════════════════════════════════════════════════════════════════════
//  LENS SHEET CONTENT
// ═════════════════════════════════════════════════════════════════════════════
class _LensSheetContent extends StatelessWidget {
  final AppThemeTokens t;
  final VoidCallback onClose;

  const _LensSheetContent({required this.t, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.phoneShellInner, t.backgroundSecondary],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: t.accent.primary.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: t.accent.primary.withValues(alpha: 0.15),
            blurRadius: 48,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(_S.base, 0, _S.base, _S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: _S.md),
            decoration: BoxDecoration(
              color: t.accent.primary.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: _S.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Title + icon
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: t.accent.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: t.accent.primary.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.search,
                        color: t.accent.primary,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: _S.sm),
                    Text(
                      'AHVI Lens',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),

                // Close button
                _PressButton(
                  onTap: onClose,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.accent.primary.withValues(alpha: 0.08),
                      border: Border.all(
                        color: t.accent.primary.withValues(alpha: 0.20),
                        width: 1,
                      ),
                    ),
                    child: Icon(Icons.close, color: t.mutedText, size: 14),
                  ),
                ),
              ],
            ),
          ),

          // "Visual AI Search" banner card
          Container(
            margin: const EdgeInsets.only(bottom: _S.sm),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.panel,
              border: Border.all(
                color: t.accent.primary.withValues(alpha: 0.15),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.center_focus_strong,
                  color: t.accent.primary,
                  size: 24,
                ),
                const SizedBox(width: _S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visual AI Search',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Point at any item to find, save, or get styling advice.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: t.mutedText,
                          fontSize: 11.5,
                          height: 1.5,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action options
          _LensOption(
            icon: Icons.search,
            name: 'Find Similar',
            desc: 'Discover similar items with shopping links',
            color: t.accent.primary,
            panelColor: t.panel,
            textColor: t.textPrimary,
            mutedColor: t.mutedText,
          ),
          _LensOption(
            icon: Icons.add_photo_alternate_outlined,
            name: 'Add to Wardrobe',
            desc: 'Save to your collection',
            color: t.accent.secondary,
            panelColor: t.panel,
            textColor: t.textPrimary,
            mutedColor: t.mutedText,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  LENS OPTION ROW
// ═════════════════════════════════════════════════════════════════════════════
class _LensOption extends StatefulWidget {
  final IconData icon;
  final String name;
  final String desc;
  final Color color;
  final Color panelColor;
  final Color textColor;
  final Color mutedColor;

  const _LensOption({
    required this.icon,
    required this.name,
    required this.desc,
    required this.color,
    required this.panelColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  State<_LensOption> createState() => _LensOptionState();
}

class _LensOptionState extends State<_LensOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: _A.fast,
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: _S.sm),
        padding: const EdgeInsets.all(_S.md),
        transform: Matrix4.diagonal3Values(
          _pressed ? 0.97 : 1.0,
          _pressed ? 0.97 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.panelColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.color.withValues(alpha: _pressed ? 0.35 : 0.20),
            width: 1,
          ),
          boxShadow: _pressed
              ? []
              : [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(widget.icon, color: widget.color, size: 18),
            ),
            const SizedBox(width: _S.sm + _S.xs), // 12
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: widget.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.desc,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: widget.mutedColor,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: _A.fast,
              transform: Matrix4.translationValues(
                _pressed ? 3.0 : 0.0,
                0.0,
                0.0,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: widget.color,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PRESS BUTTON
// ═════════════════════════════════════════════════════════════════════════════
class _PressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressButton({required this.child, required this.onTap});

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: _A.fast,
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(
          _pressed ? 0.90 : 1.0,
          _pressed ? 0.90 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  HOME PAGE HOST
// ═════════════════════════════════════════════════════════════════════════════
class _HomePageHost extends StatelessWidget {
  const _HomePageHost({super.key, required this.onNavTapRequested});
  final ValueChanged<int> onNavTapRequested;

  @override
  Widget build(BuildContext context) {
    return ClipRect(child: home.Screen4(onShellNavTap: onNavTapRequested));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  NAV PILL PAINTER
// ═════════════════════════════════════════════════════════════════════════════
class _NavPillPainter extends CustomPainter {
  final int activeIdx;
  final int itemCount;
  final double bulgeT;
  final double pillH;
  final double maxBulge;
  final Color fillColor;
  final Color borderColor;
  final Color glowColor;

  const _NavPillPainter({
    required this.activeIdx,
    required this.itemCount,
    required this.bulgeT,
    required this.pillH,
    required this.maxBulge,
    required this.fillColor,
    required this.borderColor,
    required this.glowColor,
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

    // Base pill path
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, pillTop, w, pillH),
      Radius.circular(r),
    );
    final pillPath = Path()..addRRect(pillRect);

    // Bulge bezier path
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

    // Outer drop shadow / glow
    canvas.drawPath(
      combined.shift(const Offset(0, 8)),
      Paint()
        ..color = glowColor.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Active bulge glow
    if (bulgeH > 1) {
      canvas.drawPath(
        combined,
        Paint()
          ..color = glowColor.withValues(alpha: 0.12 * bulgeT)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    // Fill
    canvas.drawPath(combined, Paint()..color = fillColor);

    // Border stroke
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
          old.glowColor != glowColor ||
          old.borderColor != borderColor;
}

// ═════════════════════════════════════════════════════════════════════════════
//  AUTH WRAPPER
//  Shows SplashScreen while auth check runs in parallel.
//  Navigates only after BOTH the splash animation finishes (2.8 s) AND the
//  auth result is known — whichever takes longer wins, so there is no flicker.
// ═════════════════════════════════════════════════════════════════════════════
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  static const Duration _startupAuthTimeout = Duration(seconds: 8);
  static const Duration _startupProfileTimeout = Duration(seconds: 10);

  bool _splashDone = false;
  bool _authDone = false;
  bool _authCheckStarted = false;

  // null = not yet known, true = logged in, false = not logged in
  bool? _isLoggedIn;
  // null = not yet known, true = first time, false = returning user
  bool? _isFirstTime;
  String? _nextRoute;

  String _nextRouteForProfile(Map<String, dynamic>? profile) {
    if (profile?['onboarding1'] != true) return AppRoutes.onboarding1;
    if (profile?['onboarding2'] != true) return AppRoutes.onboarding2;
    if (profile?['onboarding3'] != true) return AppRoutes.onboarding3;
    return AppRoutes.main;
  }

  @override
  void initState() {
    super.initState();
    // Provider.of(context) is NOT safe in initState.
    // _checkAuth() is called from didChangeDependencies instead.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_authCheckStarted) {
      _authCheckStarted = true;
      _checkAuth();
    }
  }

  Future<void> _checkAuth() async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      final profileController = Provider.of<ProfileController>(
        context,
        listen: false,
      );
      final user = await appwrite.getCurrentUser().timeout(_startupAuthTimeout);
      Map<String, dynamic>? profile;
      if (user != null) {
        // AHVI auth persistence fix:
        // Appwrite session survives restart, but ProfileController is in-memory.
        // Rehydrate it on cold start so UI does not fall back to "New User".
        try {
          profileController.loadFromAccount(name: user.name, email: user.email);
        } catch (e) {
          debugPrint("Profile hydration skipped: $e");
        }

        unawaited(
          AhviNotificationService.instance.registerForCurrentUser(appwrite),
        );

        try {
          profile = await (() async {
            await appwrite.cacheCurrentUser();
            await appwrite.ensureCurrentUserProfile();
            return appwrite.refreshCurrentUserProfile();
          })().timeout(_startupProfileTimeout);
        } catch (e) {
          debugPrint('Cold-start profile hydration failed: $e');
          profile = appwrite.cachedUserProfileData;
        }

        // AHVI fix: `profile` was previously only used for routing below —
        // gender/dob/skinTone/faceShape/bodyShape/styles/shopPrefs were
        // fetched but never pushed into ProfileController, so the UI fell
        // back to ProfileState()'s hardcoded defaults (gender: 'Female')
        // on every cold start regardless of what the user had picked.
        try {
          profileController.hydrateFromProfileDoc(profile);
        } catch (e) {
          debugPrint('Profile field hydration skipped: $e');
        }
      }

      // Appwrite users document is the source of truth.
      // SharedPreferences is only a local cache and is refreshed from Appwrite.
      final nextRoute = user != null
          ? _nextRouteForProfile(profile)
          : AppRoutes.signin;
      final onboardingDone = nextRoute == AppRoutes.main;

      debugPrint(
        'AHVI_AUTH_START user=${user?.$id} onboardingDone=$onboardingDone',
      );

      if (mounted) {
        setState(() {
          _isLoggedIn = user != null;
          _isFirstTime = user != null ? !onboardingDone : true;
          _nextRoute = nextRoute;
          _authDone = true;
        });
        _maybeNavigate();
      }
    } catch (e) {
      debugPrint("Auth Check Error: $e");
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _isFirstTime = true;
          _nextRoute = AppRoutes.signin;
          _authDone = true;
        });
        _maybeNavigate();
      }
    }
  }

  /// Navigates only after BOTH splash animation AND auth check are done.
  void _maybeNavigate() {
    if (!_splashDone || !_authDone) return;
    if (!mounted) return;

    Widget destination;

    if (_isLoggedIn == true) {
      // Logged in user — check if they completed onboarding
      if (_isFirstTime == true) {
        // DON'T mark onboardingComplete here — only mark it in onboarding3
        // when user actually taps "Save & Continue"
        destination = switch (_nextRoute) {
          AppRoutes.onboarding2 => const Screen2(),
          AppRoutes.onboarding3 => const Screen3(),
          _ => const Screen1(),
        };
      } else {
        destination = const MainNavigationShell();
      }
    } else {
      // Not logged in → SignIn page
      // After sign-in, signin.dart handles onboarding routing via isFirstTimeUser
      destination = const SignInScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => destination,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _onSplashFinished() {
    if (!mounted) return;
    setState(() => _splashDone = true);
    _maybeNavigate();
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen(onFinished: _onSplashFinished);
  }
}

class _ExploreComingSoon extends StatelessWidget {
  const _ExploreComingSoon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Explore',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Coming soon - Explore launches with beta.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.7,
                    ),
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

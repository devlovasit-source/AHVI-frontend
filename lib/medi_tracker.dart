import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/widgets/ahvi_stylist_chat.dart';
import 'package:myapp/widgets/ahvi_lens_sheet.dart';

class MediTrackScreen extends StatefulWidget {
  final String? reminderMedId;

  final String? reminderId;

  const MediTrackScreen({super.key, this.reminderMedId, this.reminderId});

  @override
  State<MediTrackScreen> createState() => _MediTrackScreenState();
}

class _MediTrackScreenState extends State<MediTrackScreen>
    with TickerProviderStateMixin {
  // ── Dynamic color palette from theme tokens ──
  AppThemeTokens get _t => context.themeTokens;
  Color get bg => _t.backgroundPrimary;
  Color get bg2 => _t.backgroundSecondary;
  Color get phoneShell => _t.phoneShell;
  Color get phoneShell2 => _t.phoneShellInner;
  Color get panel => _t.panel;
  Color get panel2 => _t.panelBorder;
  Color get cardBorder => _t.cardBorder;
  Color get textColor => _t.textPrimary;
  Color get muted => _t.mutedText;
  Color get accent => _t.accent.primary;
  Color get accent2 => _t.accent.secondary;
  Color get accent3 => _t.accent.tertiary;
  Color get accent4 => _t.accent.primary;
  Color get accent5 => _t.accent.secondary;

  // ── Navigation state ──
  String activeScreen = 'home';
  bool _isLoading = true;

  List<Map<String, dynamic>> meds = [];
  List<Map<String, dynamic>> _log = [];

  // Calendar state
  late int _calYear;
  late int _calMonth;
  String? _selectedDay;

  // Log filter state
  String _logFilter = 'all';

  // Animations
  late AnimationController _shimmerCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _ringCtrl;
  late Animation<double> _ringAnim;
  double _prevRingProgress = 0.0;

  void _syncHomeAnimations() {
    final shouldAnimate = activeScreen == 'home';
    if (shouldAnimate) {
      if (!_shimmerCtrl.isAnimating) _shimmerCtrl.repeat();
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
      return;
    }
    _shimmerCtrl.stop();
    _pulseCtrl.stop();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calYear = now.year;
    _calMonth = now.month;

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _ringAnim = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut));

    _fetchData();

    if ((widget.reminderMedId ?? '').isNotEmpty ||
        (widget.reminderId ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showToast('Medicine reminder opened', '💊');
      });
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  // Helper to resolve colors locally so we don't save raw hex codes to DB
  Color _getColorForCategory(String cat) {
    switch (cat.toLowerCase()) {
      case 'diabetes':
        return accent;
      case 'blood pressure':
        return accent2;
      case 'vitamin/supplement':
        return accent5;
      case 'heart':
        return accent3;
      default:
        return accent4;
    }
  }

  // Checks if the medication was taken *today* based on lastTaken ISO string
  bool _isTakenToday(String? lastTakenIso) {
    if (lastTakenIso == null || lastTakenIso.isEmpty) return false;
    try {
      final last = DateTime.parse(lastTakenIso).toLocal();
      final now = DateTime.now();
      return last.year == now.year &&
          last.month == now.month &&
          last.day == now.day;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchData() async {
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      // Cache user session upfront so subsequent calls don't fail
      await appwrite.cacheCurrentUser();
      final medsDocs = await appwrite.getMeds();
      final logsDocs = await appwrite.getMedLogs();

      if (mounted) {
        setState(() {
          meds = medsDocs
              .map(
                (d) => {
                  'id': d.$id,
                  'name': d.data['name'],
                  'dose': d.data['dose'],
                  'freq': d.data['freq'],
                  'time': d.data['time'],
                  'cat': d.data['cat'],
                  'left': d.data['left'],
                  'total': d.data['total'],
                  'reminder': d.data['reminder'] ?? true,
                  'taken': _isTakenToday(d.data['lastTaken']),
                  'color': _getColorForCategory(d.data['cat']),
                },
              )
              .toList();

          _log = logsDocs
              .map(
                (d) => {
                  'id': d.$id,
                  'medId': d.data['medId'],
                  'medName': d.data['medName'],
                  'dose': d.data['dose'],
                  'time': DateTime.parse(d.data['time']).toLocal(),
                  'status': d.data['status'],
                },
              )
              .toList();

          _isLoading = false;
        });
        _animateRing(_computeRingProgress());
        _syncHomeAnimations();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showToast(AppLocalizations.t(context, 'medi_failed_load'), '❌');
    }
  }

  double _computeRingProgress() {
    final remMeds = meds.where((m) => m['reminder'] == true).toList();
    if (remMeds.isEmpty) return 0.0;
    final taken = remMeds.where((m) => m['taken'] == true).length;
    return taken / remMeds.length;
  }

  void _animateRing(double newProgress) {
    _ringAnim = Tween<double>(
      begin: _prevRingProgress,
      end: newProgress,
    ).animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut));
    _ringCtrl.forward(from: 0);
    _prevRingProgress = newProgress;
  }

  void _markTaken(String id) async {

    debugPrint('AHVI_MED_MARK_TAKEN medId=$id');

    final medIndex = meds.indexWhere((m) => m['id'] == id);
    if (medIndex == -1 || meds[medIndex]['taken']) return;

    final med = meds[medIndex];
    final newLeft = (med['left'] as int) > 0 ? (med['left'] as int) - 1 : 0;
    final now = DateTime.now();

    // Optimistic UI Update
    setState(() {
      meds[medIndex] = {...med, 'taken': true, 'left': newLeft};
      _log.insert(0, {
        'medId': id,
        'medName': med['name'],
        'dose': med['dose'],
        'time': now,
        'status': 'taken',
      });
      _animateRing(_computeRingProgress());
    });
    _showToast(
      AppLocalizations.t(
        context,
        'medi_marked_taken',
      ).replaceAll('{name}', med['name'] as String),
      '✅',
    );

    // DB Update. Appwrite's datetime attributes require an ISO 8601
    // string with a timezone designator; toIso8601String() on a local
    // DateTime omits one, so Appwrite silently rejects the write.
    // Convert to UTC first — that gives a "...Z" suffix Appwrite accepts.
    final nowIso = now.toUtc().toIso8601String();
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      await appwrite.updateMed(id, {'left': newLeft, 'lastTaken': nowIso});
      await appwrite.createMedLog({
        'medId': id,
        'medName': med['name'],
        'dose': med['dose'],
        'time': nowIso,
        'status': 'taken',
      });
    } catch (e) {
      // Surface the raw Appwrite error to the screen so it can be read
      // / screenshotted without adb access. Trimmed to keep the toast
      // sized reasonably.
      final errText = e.toString();
      final shown = errText.length > 200
          ? '${errText.substring(0, 200)}…'
          : errText;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: bg2,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 12),
          content: Text(
            'Sync failed: $shown',
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
  }

  void _deleteMed(String id) async {
    setState(() => meds.removeWhere((m) => m['id'] == id));
    _animateRing(_computeRingProgress());
    try {
      await Provider.of<AppwriteService>(context, listen: false).deleteMed(id);
      _showToast(AppLocalizations.t(context, 'medi_medicine_removed'), '🗑️');
    } catch (e) {
      _showToast(AppLocalizations.t(context, 'medi_remove_failed'), '❌');
    }
  }

  void _showToast(String message, String icon) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg2,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting(BuildContext context) {
    final l = AppLocalizations.t;
    final hour = DateTime.now().hour;
    if (hour < 5) return l(context, 'medi_greeting_latenight');
    if (hour < 12) return l(context, 'medi_greeting_morning');
    if (hour < 18) return l(context, 'medi_greeting_afternoon');
    return l(context, 'medi_greeting_evening');
  }

  String _getGreetingTitle(BuildContext context) {
    final l = AppLocalizations.t;
    final hour = DateTime.now().hour;
    if (hour < 5) return l(context, 'medi_title_latenight');
    if (hour < 12) return l(context, 'medi_title_morning');
    if (hour < 18) return l(context, 'medi_title_afternoon');
    return l(context, 'medi_title_evening');
  }

  void navTo(String screen) {
    setState(() {
      activeScreen = screen;
      _syncHomeAnimations();
      if (screen == 'log') _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: bg,
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: accent))
            : Container(
                width: double.infinity,
                height: double.infinity,
                color: phoneShell,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _buildTopBar(),
                        Expanded(
                          child: Container(
                            color: bg,
                            child: _buildActiveScreen(),
                          ),
                        ),
                      ],
                    ),
                    if (activeScreen != 'medicines')
                      Positioned(bottom: 30, right: 18, child: _buildChatFab()),
                    if (activeScreen == 'medicines')
                      Positioned(bottom: 30, right: 18, child: _buildChatFab()),
                  ],
                ),
              ),
      ),
    );
  }

  // ── TOP BAR ──
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      decoration: BoxDecoration(
        color: phoneShell2,
        border: Border(bottom: BorderSide(color: cardBorder, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent2,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                AppLocalizations.t(context, 'medi_app_name'),
                style: TextStyle(
                  color: textColor,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          _buildIconBtn(
            child: Icon(
              Icons.notifications_outlined,
              size: 17,
              color: textColor,
            ),
            onTap: () => _showToast(
              AppLocalizations.t(context, 'medi_notifications_empty'),
              '🔔',
            ),
            badge: true,
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn({
    required Widget child,
    required VoidCallback onTap,
    bool badge = false,
  }) {
    return _PressScaleButton(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: panel,
              shape: BoxShape.circle,
              border: Border.all(color: cardBorder, width: 1),
            ),
            child: Center(child: child),
          ),
          if (badge)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent4,
                  shape: BoxShape.circle,
                  border: Border.all(color: phoneShell, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── ACTIVE SCREEN ROUTER ──
  Widget _buildActiveScreen() {
    switch (activeScreen) {
      case 'medicines':
        return _buildMedicinesScreen();
      case 'adherence':
        return _buildAdherenceScreen();
      case 'log':
        return _buildLogScreen();
      default:
        return _buildHomeScreen();
    }
  }

  // ── HOME SCREEN ──
  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHomeHero(),
          _buildProgressCard(),
          _buildSectionHeader(
            AppLocalizations.t(context, 'medi_todays_schedule'),
            AppLocalizations.t(context, 'medi_see_all'),
            onLink: () => navTo('medicines'),
          ),
          _buildTodayScroll(),
          const SizedBox(height: 14),
          _buildSectionHeader(
            AppLocalizations.t(context, 'medi_quick_stats'),
            null,
          ),
          _buildQuickStats(),
          _buildSectionHeader(
            AppLocalizations.t(context, 'medi_quick_access'),
            null,
          ),
          _buildNavCards(),
        ],
      ),
    );
  }

  Widget _buildHomeHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(context),
                  style: TextStyle(
                    fontSize: 13,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getGreetingTitle(context),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _getHeroDate(context),
                  style: TextStyle(
                    fontSize: 12,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeroAddButton(onTap: _showAddMedSheet),
        ],
      ),
    );
  }

  String _getHeroDate(BuildContext context) {
    final l = AppLocalizations.t;
    final now = DateTime.now();
    final months = [
      l(context, 'medi_date_short_jan'),
      l(context, 'medi_date_short_feb'),
      l(context, 'medi_date_short_mar'),
      l(context, 'medi_date_short_apr'),
      l(context, 'medi_date_short_may'),
      l(context, 'medi_date_short_jun'),
      l(context, 'medi_date_short_jul'),
      l(context, 'medi_date_short_aug'),
      l(context, 'medi_date_short_sep'),
      l(context, 'medi_date_short_oct'),
      l(context, 'medi_date_short_nov'),
      l(context, 'medi_date_short_dec'),
    ];
    final days = [
      l(context, 'medi_weekday_monday'),
      l(context, 'medi_weekday_tuesday'),
      l(context, 'medi_weekday_wednesday'),
      l(context, 'medi_weekday_thursday'),
      l(context, 'medi_weekday_friday'),
      l(context, 'medi_weekday_saturday'),
      l(context, 'medi_weekday_sunday'),
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  Widget _buildProgressCard() {
    final remMeds = meds.where((m) => m['reminder'] == true).toList();
    final takenCount = remMeds.where((m) => m['taken'] == true).length;
    final pendingCount = remMeds.length - takenCount;
    final pct = remMeds.isEmpty
        ? 0
        : (takenCount / remMeds.length * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent2.withValues(alpha: 0.18),
            accent3.withValues(alpha: 0.12),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AnimatedBuilder(
          animation: _shimmerCtrl,
          builder: (context, child) {
            return Stack(
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ShimmerPainter(progress: _shimmerCtrl.value),
                    ),
                  ),
                ),
              ],
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                SizedBox(
                  width: 82,
                  height: 82,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _ringAnim,
                        builder: (context, _) => CustomPaint(
                          size: const Size(82, 82),
                          painter: _RingPainter(
                            progress: _ringAnim.value,
                            trackColor: accent.withValues(alpha: 0.20),
                            progressColor: accent,
                            strokeWidth: 7,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              height: 1,
                            ),
                          ),
                          Text(
                            AppLocalizations.t(context, 'medi_done'),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: muted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.t(context, 'medi_todays_progress'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _progStat(
                        Colors.white.withValues(alpha: 0.9),
                        AppLocalizations.t(
                          context,
                          'medi_taken_count',
                        ).replaceAll('{n}', '$takenCount'),
                      ),
                      const SizedBox(height: 5),
                      _progStat(
                        Colors.white.withValues(alpha: 0.45),
                        AppLocalizations.t(
                          context,
                          'medi_pending_count',
                        ).replaceAll('{n}', '$pendingCount'),
                      ),
                      const SizedBox(height: 8),
                      _PulseTakeMedsButton(
                        pulseAnim: _pulseAnim,
                        onTap: () => navTo('medicines'),
                        accent: accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progStat(Color dotColor, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    String? linkText, {
    VoidCallback? onLink,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
          if (linkText != null)
            GestureDetector(
              onTap: onLink,
              child: Text(
                linkText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTodayScroll() {
    if (meds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          AppLocalizations.t(context, 'medi_no_medicines_scheduled'),
          style: TextStyle(color: muted),
        ),
      );
    }
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        itemCount: meds.length,
        separatorBuilder: (_, i2) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = meds[i];
          return _buildPillCard(
            id: p['id'] as String,
            name: p['name'] as String,
            dose: p['dose'] as String,
            time: p['time'] as String,
            color: p['color'] as Color,
            taken: p['taken'] as bool,
          );
        },
      ),
    );
  }

  Widget _buildPillCard({
    required String id,
    required String name,
    required String dose,
    required String time,
    required Color color,
    required bool taken,
  }) {
    return _PressScaleButton(
      onTap: () {
        if (!taken) _markTaken(id);
      },
      child: SizedBox(
        width: 230,
        child: Container(
        decoration: BoxDecoration(
          color: taken ? const Color(0x1404D7C8) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: taken ? const Color(0x4D04D7C8) : cardBorder,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('💊', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      Text(
                        dose,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 9, color: color),
                          const SizedBox(width: 3),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      if (!taken) ...[
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () => _markTaken(id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [accent4, accent2],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check,
                                  size: 9,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  AppLocalizations.t(context, 'medi_take'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                  fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                ],
              ),
            ),
            if (taken)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accent3,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    int totalExpected = 0;
    int totalTaken = 0;
    for (var m in meds) {
      int t = m['total'] as int;
      int l = m['left'] as int;
      totalExpected += t;
      totalTaken += (t - l >= 0 ? t - l : 0);
    }
    int adherencePct = totalExpected > 0
        ? ((totalTaken / totalExpected) * 100).toInt().clamp(0, 100)
        : 0;

    final stats = [
      {
        'icon': '💊',
        'val': '${meds.length}',
        'lbl': AppLocalizations.t(context, 'medi_stat_medicines'),
        'sub': AppLocalizations.t(context, 'medi_stat_active'),
        'borderColor': accent4,
      },
      {
        'icon': '📊',
        'val': '$adherencePct%',
        'lbl': AppLocalizations.t(context, 'medi_stat_adherence'),
        'sub': AppLocalizations.t(context, 'medi_stat_overall'),
        'borderColor': accent2,
      },
      {
        'icon': '✅',
        'val': '${meds.where((m) => m['taken'] == true).length}',
        'lbl': AppLocalizations.t(context, 'medi_stat_taken_today'),
        'sub': AppLocalizations.t(
          context,
          'medi_stat_of',
        ).replaceAll('{n}', '${meds.length}'),
        'borderColor': accent3,
      },
      {
        'icon': '⚠️',
        'val': '${meds.where((m) => (m['left'] as int) <= 7).length}',
        'lbl': AppLocalizations.t(context, 'medi_stat_low_supply'),
        'sub': AppLocalizations.t(context, 'medi_stat_refill_soon'),
        'borderColor': accent5,
      },
    ];

    final navTargets = ['medicines', 'adherence', 'medicines', 'medicines'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: List.generate(stats.length, (i) {
          final s = stats[i];
          final bc = s['borderColor'] as Color;
          return _PressScaleButton(
            onTap: () => navTo(navTargets[i]),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    bc.withValues(alpha: 0.18),
                    bc.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: bc, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: bc.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        s['icon'] as String,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s['val'] as String,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s['lbl'] as String,
                    style: TextStyle(
                      fontSize: 11,
                      color: muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s['sub'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavCards() {
    final cards = [
      {
        'icon': Icons.folder_open,
        'iconBg': [accent2, accent],
        'shadowColor': accent2.withValues(alpha: 0.35),
        'labelKey': 'medi_nav_my_medicines',
        'subKey': 'medi_nav_my_medicines_sub',
        'screen': 'medicines',
      },
      {
        'icon': Icons.bar_chart,
        'iconBg': [accent, accent3],
        'shadowColor': accent.withValues(alpha: 0.35),
        'labelKey': 'medi_nav_adherence',
        'subKey': 'medi_nav_adherence_sub',
        'screen': 'adherence',
      },
      {
        'icon': Icons.calendar_today,
        'iconBg': [accent3, accent2],
        'shadowColor': accent3.withValues(alpha: 0.35),
        'labelKey': 'medi_nav_log',
        'subKey': 'medi_nav_log_sub',
        'screen': 'log',
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: cards.map((c) {
          final gradColors = c['iconBg'] as List<Color>;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _NavCardAnimated(
              onTap: () => navTo(c['screen'] as String),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradColors),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: c['shadowColor'] as Color,
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        c['icon'] as IconData,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.t(
                              context,
                              c['labelKey'] as String,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          Text(
                            AppLocalizations.t(context, c['subKey'] as String),
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: muted),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── MEDICINES SCREEN ──
  Widget _buildMedicinesScreen() {
    return Column(
      children: [
        _buildMedicinesBackBar(
          AppLocalizations.t(context, 'medi_screen_my_medicines'),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: meds.isEmpty
                  ? [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            AppLocalizations.t(
                              context,
                              'medi_no_medicines_added',
                            ),
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ),
                    ]
                  : meds.map((m) => _buildMedItem(m)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedItem(Map<String, dynamic> med) {
    final color = med['color'] as Color;
    final left = med['left'] as int;
    final total = med['total'] as int;
    final progress = total > 0 ? left / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _SlideXPressButton(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Center(
                  child: Text('💊', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med['name'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      children: [
                        Text(
                          '${med['dose']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text('·', style: TextStyle(fontSize: 11, color: muted)),
                        Text(
                          '${med['freq']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text('·', style: TextStyle(fontSize: 11, color: muted)),
                        Text(
                          '${med['time']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.t(context, 'medi_supply'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: muted,
                          ),
                        ),
                        Text(
                          '$left / $total',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: panel2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  _PressScaleButton(
                    scaleFactor: 0.9,
                    onTap: () => _showAddMedSheet(editMed: med),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: color.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(Icons.edit_outlined, size: 15, color: color),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _PressScaleButton(
                    scaleFactor: 0.9,
                    onTap: () => _deleteMed(med['id'] as String),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent4.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accent4.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        size: 15,
                        color: accent4,
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

  // ── ADHERENCE SCREEN ──
  Widget _buildAdherenceScreen() {
    return Column(
      children: [
        _buildBackBar(AppLocalizations.t(context, 'medi_screen_adherence')),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: meds.isEmpty
                  ? [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            AppLocalizations.t(
                              context,
                              'medi_no_medicine_data',
                            ),
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ),
                    ]
                  : meds.map((m) {
                      final total = m['total'] as int;
                      final left = m['left'] as int;
                      final taken = total > 0 ? (total - left) : 0;
                      final pct = total > 0
                          ? ((taken / total) * 100).toInt().clamp(0, 100)
                          : 0;

                      String tagKey = 'medi_adherence_poor';
                      Color tagColor = accent4;
                      if (pct >= 90) {
                        tagKey = 'medi_adherence_excellent';
                        tagColor = accent3;
                      } else if (pct >= 70) {
                        tagKey = 'medi_adherence_good';
                        tagColor = accent;
                      } else if (pct >= 50) {
                        tagKey = 'medi_adherence_fair';
                        tagColor = accent5;
                      }
                      final tag = AppLocalizations.t(context, tagKey);
                      final dosesLabel =
                          AppLocalizations.t(context, 'medi_doses_taken')
                              .replaceAll('{taken}', '$taken')
                              .replaceAll('{total}', '$total');

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SlideXPressButton(
                          onTap: () {},
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0x14FFFFFF),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cardBorder, width: 1.5),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m['name'] as String,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: textColor,
                                            ),
                                          ),
                                          Text(
                                            '${m['dose']} · ${m['freq']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: muted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$pct%',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: tagColor,
                                          ),
                                        ),
                                        Text(
                                          dosesLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: muted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: pct / 100,
                                    minHeight: 5,
                                    backgroundColor: panel2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      tagColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      9,
                                      3,
                                      9,
                                      3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tagColor.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: tagColor.withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: tagColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── LOG / CALENDAR SCREEN ──
  Widget _buildLogScreen() {
    return Column(
      children: [
        _buildBackBar(AppLocalizations.t(context, 'medi_screen_log')),
        _buildLogFilterBar(),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _buildCalCard(),
                  const SizedBox(height: 14),
                  _buildLogTimeline(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterBtn(
              AppLocalizations.t(context, 'medi_filter_all'),
              'all',
              _logFilter == 'all',
            ),
            const SizedBox(width: 8),
            _buildFilterBtn(
              AppLocalizations.t(context, 'medi_filter_taken'),
              'taken',
              _logFilter == 'taken',
            ),
            const SizedBox(width: 8),
            _buildFilterBtn(
              AppLocalizations.t(context, 'medi_filter_missed'),
              'missed',
              _logFilter == 'missed',
            ),
            const SizedBox(width: 8),
            _buildFilterBtn(
              AppLocalizations.t(context, 'medi_filter_mark_missed'),
              'mark',
              false,
              isAction: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBtn(
    String label,
    String filter,
    bool active, {
    bool isAction = false,
  }) {
    return GestureDetector(
      onTap: () {
        if (isAction) {
          _showToast(AppLocalizations.t(context, 'medi_mark_missed_soon'), '❌');
        } else {
          setState(() => _logFilter = filter);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? accent
              : isAction
              ? accent2.withValues(alpha: 0.10)
              : panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? accent
                : isAction
                ? accent2
                : cardBorder,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: active
                ? Colors.white
                : isAction
                ? accent2
                : muted,
          ),
        ),
      ),
    );
  }

  Widget _buildCalCard() {
    final monthNames = [
      AppLocalizations.t(context, 'medi_cal_jan'),
      AppLocalizations.t(context, 'medi_cal_feb'),
      AppLocalizations.t(context, 'medi_cal_mar'),
      AppLocalizations.t(context, 'medi_cal_apr'),
      AppLocalizations.t(context, 'medi_cal_may'),
      AppLocalizations.t(context, 'medi_cal_jun'),
      AppLocalizations.t(context, 'medi_cal_jul'),
      AppLocalizations.t(context, 'medi_cal_aug'),
      AppLocalizations.t(context, 'medi_cal_sep'),
      AppLocalizations.t(context, 'medi_cal_oct'),
      AppLocalizations.t(context, 'medi_cal_nov'),
      AppLocalizations.t(context, 'medi_cal_dec'),
    ];
    final monthLabel = '${monthNames[_calMonth - 1]} $_calYear';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0, -1),
          end: Alignment(1, 1),
          colors: [
            accent.withValues(alpha: 0.14),
            accent2.withValues(alpha: 0.12),
            accent3.withValues(alpha: 0.10),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: accent4.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PressScaleButton(
                scaleFactor: 0.93,
                onTap: () {
                  setState(() {
                    _calMonth--;
                    if (_calMonth < 1) {
                      _calMonth = 12;
                      _calYear--;
                    }
                    _selectedDay = null;
                  });
                },
                child: _calNavBtn(Icons.chevron_left),
              ),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [accent, accent4],
                ).createShader(bounds),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              _PressScaleButton(
                scaleFactor: 0.93,
                onTap: () {
                  setState(() {
                    _calMonth++;
                    if (_calMonth > 12) {
                      _calMonth = 1;
                      _calYear++;
                    }
                    _selectedDay = null;
                  });
                },
                child: _calNavBtn(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _legendItem(
                  accent3,
                  AppLocalizations.t(context, 'medi_legend_taken'),
                ),
                _legendItem(
                  const Color(0xFFFF6B7A),
                  AppLocalizations.t(context, 'medi_legend_missed'),
                ),
                _legendItem(
                  accent2,
                  AppLocalizations.t(context, 'medi_legend_pending'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildCalGrid(),
          if (_selectedDay != null) ...[
            const SizedBox(height: 12),
            _buildDayDetailPanel(),
          ],
        ],
      ),
    );
  }

  Widget _calNavBtn(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: accent2),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildCalGrid() {
    final now = DateTime.now();
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    final startWkDay = firstDay.weekday % 7;
    final weekdays = [
      AppLocalizations.t(context, 'medi_wkday_su'),
      AppLocalizations.t(context, 'medi_wkday_mo'),
      AppLocalizations.t(context, 'medi_wkday_tu'),
      AppLocalizations.t(context, 'medi_wkday_we'),
      AppLocalizations.t(context, 'medi_wkday_th'),
      AppLocalizations.t(context, 'medi_wkday_fr'),
      AppLocalizations.t(context, 'medi_wkday_sa'),
    ];

    return Column(
      children: [
        Row(
          children: weekdays
              .map(
                (d) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.75,
          ),
          itemCount: startWkDay + daysInMonth,
          itemBuilder: (context, index) {
            if (index < startWkDay) return const SizedBox.shrink();
            final day = index - startWkDay + 1;
            final isToday =
                day == now.day &&
                _calMonth == now.month &&
                _calYear == now.year;
            final isFuture = DateTime(_calYear, _calMonth, day).isAfter(now);
            final dayKey = '$_calYear-$_calMonth-$day';
            final isSel = _selectedDay == dayKey;

            bool hasTaken = false;
            bool hasMissed = false;
            if (!isFuture && day <= now.day) {
              final dayLogs = _log.where((l) {
                final logTime = l['time'] as DateTime;
                return logTime.year == _calYear &&
                    logTime.month == _calMonth &&
                    logTime.day == day;
              });
              hasTaken = dayLogs.any((l) => l['status'] == 'taken');
              hasMissed = dayLogs.any((l) => l['status'] == 'missed');
            }

            return GestureDetector(
              onTap: () => setState(() {
                _selectedDay = _selectedDay == dayKey ? null : dayKey;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isSel
                        ? [
                            accent4.withValues(alpha: 0.18),
                            accent4.withValues(alpha: 0.10),
                          ]
                        : isToday
                        ? [
                            accent.withValues(alpha: 0.18),
                            accent2.withValues(alpha: 0.10),
                          ]
                        : [
                            accent.withValues(alpha: 0.08),
                            accent2.withValues(alpha: 0.05),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSel
                        ? accent4
                        : isToday
                        ? accent
                        : cardBorder,
                    width: isSel || isToday ? 2 : 1,
                  ),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                            color: accent4.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : isToday
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Opacity(
                  opacity: isFuture ? 0.4 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
                    child: Column(
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isToday ? accent : textColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (hasTaken || hasMissed)
                          Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: hasMissed
                                  ? const Color(0xFFFF6B7A)
                                  : accent3,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDayDetailPanel() {
    final parts = _selectedDay!.split('-');
    final day = int.parse(parts[2]);
    final date = DateTime(_calYear, _calMonth, day);
    final months = [
      AppLocalizations.t(context, 'medi_date_short_jan'),
      AppLocalizations.t(context, 'medi_date_short_feb'),
      AppLocalizations.t(context, 'medi_date_short_mar'),
      AppLocalizations.t(context, 'medi_date_short_apr'),
      AppLocalizations.t(context, 'medi_date_short_may'),
      AppLocalizations.t(context, 'medi_date_short_jun'),
      AppLocalizations.t(context, 'medi_date_short_jul'),
      AppLocalizations.t(context, 'medi_date_short_aug'),
      AppLocalizations.t(context, 'medi_date_short_sep'),
      AppLocalizations.t(context, 'medi_date_short_oct'),
      AppLocalizations.t(context, 'medi_date_short_nov'),
      AppLocalizations.t(context, 'medi_date_short_dec'),
    ];
    final wdays = [
      AppLocalizations.t(context, 'medi_day_mon'),
      AppLocalizations.t(context, 'medi_day_tue'),
      AppLocalizations.t(context, 'medi_day_wed'),
      AppLocalizations.t(context, 'medi_day_thu'),
      AppLocalizations.t(context, 'medi_day_fri'),
      AppLocalizations.t(context, 'medi_day_sat'),
      AppLocalizations.t(context, 'medi_day_sun'),
    ];
    final label = '${wdays[date.weekday - 1]}, ${months[date.month - 1]} $day';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.10),
            accent2.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, size: 13, color: accent2),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...meds.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: m['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m['name'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ),
                    Text(
                      m['dose'] as String,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTimeline() {
    final filtered = _logFilter == 'all'
        ? _log
        : _log.where((e) => e['status'] == _logFilter).toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            _logFilter == 'taken'
                ? AppLocalizations.t(context, 'medi_log_no_taken')
                : _logFilter == 'missed'
                ? AppLocalizations.t(context, 'medi_log_no_missed')
                : AppLocalizations.t(context, 'medi_log_no_entries'),
            style: TextStyle(
              fontSize: 13,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.t(context, 'medi_log_timeline'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
        const SizedBox(height: 10),
        ...filtered.map((e) {
          final mColor =
              meds.firstWhere(
                    (m) => m['id'] == e['medId'],
                    orElse: () => {'color': accent},
                  )['color']
                  as Color;
          final isMissed = e['status'] == 'missed';
          final timeStr = (e['time'] as DateTime).toString().substring(11, 16);
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: isMissed ? accent4 : mColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e['medName'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
                Text(
                  e['dose'] as String,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: Text(
                    timeStr,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBackBar(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _PressScaleButton(
            onTap: () => navTo('home'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: cardBorder, width: 1),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                color: textColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicinesBackBar(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _PressScaleButton(
            onTap: () => navTo('home'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: cardBorder, width: 1),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                color: textColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
          ),
          _PressScaleButton(
            onTap: _showAddMedSheet,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: accent.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Icon(Icons.add, color: accent, size: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLensFab() {
    return GestureDetector(
      onTap: () => showAhviLensSheet(
        context,
        t: _t,
        onVisualSearch: _showAddMedSheet,
        onFindSimilar: _showAddMedSheet,
        onAddToWardrobe: _showAddMedSheet,
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, accent2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.40),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildChatFab() {
    return _AskAhviFab(
      onTap: () => showAhviStylistChatSheet(
        context,
        moduleContext: 'medi',
        contextData: {
          'medications': meds,
          'recent_log': _log.take(10).toList(),
          'taken_today': meds.where((m) => m['taken'] == true).length,
          'pending_today': meds.where((m) => m['taken'] != true).length,
        },
        onRefresh: _fetchData,
      ),
    );
  }

  Widget _buildAddFab() {
    return _PressScaleButton(
      onTap: _showAddMedSheet,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 22),
      ),
    );
  }

  // ── ADD MEDICINE BOTTOM SHEET ──
  final _nameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _supplyCtrl = TextEditingController();
  final _customCatCtrl = TextEditingController();
  String? _selFreq;
  String? _selCat;
  bool _isCustomCat = false;

  void _showAddMedSheet({Map<String, dynamic>? editMed}) {
    final l = AppLocalizations.t;
    final isEditing = editMed != null;
    if (isEditing) {
      // Pre-fill the form from the medicine being edited.
      _nameCtrl.text = (editMed['name'] ?? '').toString();
      _doseCtrl.text = (editMed['dose'] ?? '').toString();
      _timeCtrl.text = (editMed['time'] ?? '').toString();
      final totalVal = editMed['total'] ?? editMed['left'] ?? '';
      _supplyCtrl.text = totalVal.toString();
      _selFreq = (editMed['freq'] ?? l(context, 'medi_freq_once')).toString();
      _selCat = (editMed['cat'] ?? l(context, 'medi_cat_diabetes')).toString();
      _isCustomCat = false;
      _customCatCtrl.clear();
    } else {
      _selFreq ??= l(context, 'medi_freq_once');
      _selCat ??= l(context, 'medi_cat_diabetes');
      _isCustomCat = false;
      _customCatCtrl.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final l = AppLocalizations.t;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: phoneShell,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border(top: BorderSide(color: cardBorder, width: 1)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: panel2,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l(context, 'medi_add_title'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: ListView(
                        children: [
                          _buildInputLabel(l(context, 'medi_label_name')),
                          _buildTextField(
                            _nameCtrl,
                            l(context, 'medi_hint_name'),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInputLabel(
                                      l(context, 'medi_label_dose'),
                                    ),
                                    _buildTextField(
                                      _doseCtrl,
                                      l(context, 'medi_hint_dose'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInputLabel(
                                      l(context, 'medi_label_time'),
                                    ),
                                    _buildTextField(
                                      _timeCtrl,
                                      l(context, 'medi_hint_time'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildInputLabel(l(context, 'medi_label_frequency')),
                          _buildDropdown(
                            _selFreq ?? l(context, 'medi_freq_once'),
                            [
                              l(context, 'medi_freq_once'),
                              l(context, 'medi_freq_twice'),
                              l(context, 'medi_freq_as_needed'),
                            ],
                            (v) => setSheetState(() => _selFreq = v!),
                          ),
                          const SizedBox(height: 16),
                          _buildInputLabel(l(context, 'medi_label_category')),
                          _buildCategorySelector(
                            setSheetState,
                            AppLocalizations.t,
                          ),
                          const SizedBox(height: 16),
                          _buildInputLabel(l(context, 'medi_label_supply')),
                          _buildTextField(
                            _supplyCtrl,
                            l(context, 'medi_hint_supply'),
                            isNumber: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PressScaleButton(
                      onTap: () async {
                        final name = _nameCtrl.text.trim();
                        final dose = _doseCtrl.text.trim();
                        final supply =
                            int.tryParse(_supplyCtrl.text.trim()) ?? 0;
                        final customText = _customCatCtrl.text.trim();
                        final effectiveCat = _isCustomCat
                            ? customText
                            : (_selCat ?? l(this.context, 'medi_cat_diabetes'));
                        if (name.isEmpty || dose.isEmpty || supply <= 0) {
                          _showToast(
                            AppLocalizations.t(
                              this.context,
                              'medi_please_fill',
                            ),
                            '⚠️',
                          );
                          return;
                        }
                        if (_isCustomCat && customText.isEmpty) {
                          _showToast(
                            'Please enter a custom category name',
                            '⚠️',
                          );
                          return;
                        }

                        try {
                          final appwrite = Provider.of<AppwriteService>(
                            this.context,
                            listen: false,
                          );
                          final resolvedTime = _timeCtrl.text.trim().isEmpty
                              ? '12:00 PM'
                              : _timeCtrl.text.trim();
                          final resolvedFreq =
                              _selFreq ?? l(this.context, 'medi_freq_once');
                          if (isEditing) {
                            // Update existing medicine. Leave `left` and
                            // `lastTaken` alone so today's taken-state and
                            // remaining count are not reset by an edit.
                            await appwrite.updateMed(editMed['id'] as String, {
                              'name': name,
                              'dose': dose,
                              'freq': resolvedFreq,
                              'time': resolvedTime,
                              'cat': effectiveCat,
                              'total': supply,
                            });
                            _showToast('Medicine updated', '✅');
                          } else {
                            await appwrite.createMed({
                              'name': name,
                              'dose': dose,
                              'freq': resolvedFreq,
                              'time': resolvedTime,
                              'cat': effectiveCat,
                              'left': supply,
                              'total': supply,
                              'reminder': true,
                              'lastTaken': '',
                            });
                            _showToast(
                              AppLocalizations.t(
                                this.context,
                                'medi_medicine_added',
                              ),
                              '💊',
                            );
                          }
                          Navigator.pop(context);

                          _nameCtrl.clear();
                          _doseCtrl.clear();
                          _timeCtrl.clear();
                          _supplyCtrl.clear();
                          _customCatCtrl.clear();
                          _selFreq = null;
                          _selCat = null;
                          _isCustomCat = false;

                          _fetchData();
                        } catch (e) {
                          _showToast('Save failed: $e', '❌');
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            l(context, 'medi_save'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    bool isNumber = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: textColor, fontSize: 14),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          hintText: hint,
          hintStyle: TextStyle(color: muted.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _buildCategorySelector(
    StateSetter setSheetState,
    String Function(BuildContext, String) l,
  ) {
    final categories = [
      l(context, 'medi_cat_diabetes'),
      l(context, 'medi_cat_bp'),
      l(context, 'medi_cat_heart'),
      l(context, 'medi_cat_vitamin'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...categories.map((cat) {
              final isSelected = !_isCustomCat && _selCat == cat;
              return GestureDetector(
                onTap: () => setSheetState(() {
                  _selCat = cat;
                  _isCustomCat = false;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? accent.withValues(alpha: 0.15) : panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? accent : cardBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected ? accent : textColor,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
            // Custom button
            GestureDetector(
              onTap: () => setSheetState(() {
                _isCustomCat = true;
                _selCat = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _isCustomCat ? accent2.withValues(alpha: 0.15) : panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isCustomCat ? accent2 : cardBorder,
                    width: _isCustomCat ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: _isCustomCat ? accent2 : muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Custom',
                      style: TextStyle(
                        color: _isCustomCat ? accent2 : muted,
                        fontWeight: _isCustomCat
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isCustomCat) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder),
            ),
            child: TextField(
              controller: _customCatCtrl,
              autofocus: true,
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                hintText: 'Enter category name (e.g. Thyroid)',
                hintStyle: TextStyle(color: muted.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    final menuBg = _t.backgroundSecondary;
    final selectedBg = _t.panel;

    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 52),
      constraints: const BoxConstraints(minWidth: 200),
      itemBuilder: (_) => items.map((e) {
        final isSelected = e == value;
        return PopupMenuItem<String>(
          value: e,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              e,
              style: TextStyle(
                color: isSelected ? accent : textColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _t.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: accent, size: 22),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  [PATCH B01] Generic press-scale animation widget
// ════════════════════════════════════════════════════════════
class _PressScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;

  const _PressScaleButton({
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.95,
  });

  @override
  State<_PressScaleButton> createState() => _PressScaleButtonState();
}

class _PressScaleButtonState extends State<_PressScaleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  [PATCH B11] Horizontal slide press for med/adhere items
// ════════════════════════════════════════════════════════════
class _SlideXPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _SlideXPressButton({required this.child, required this.onTap});
  @override
  State<_SlideXPressButton> createState() => _SlideXPressButtonState();
}

class _SlideXPressButtonState extends State<_SlideXPressButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        transform: Matrix4.translationValues(_hovered ? 4.0 : 0.0, 0, 0),
        child: widget.child,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  [PATCH B02] Hero add button with spring rotate + scale
// ════════════════════════════════════════════════════════════
class _HeroAddButton extends StatefulWidget {
  final VoidCallback onTap;
  const _HeroAddButton({required this.onTap});
  @override
  State<_HeroAddButton> createState() => _HeroAddButtonState();
}

class _HeroAddButtonState extends State<_HeroAddButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _rotateAnim = Tween<double>(
      begin: 0.0,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _ctrl.forward().then((_) => _ctrl.reverse());
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: Transform.rotate(
            angle: _rotateAnim.value * 2 * math.pi,
            child: child,
          ),
        ),
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: context.themeTokens.accent.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: context.themeTokens.accent.primary.withValues(
                  alpha: 0.40,
                ),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  [PATCH B25] Nav card with press translateX + scale
// ════════════════════════════════════════════════════════════
class _NavCardAnimated extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _NavCardAnimated({required this.child, required this.onTap});
  @override
  State<_NavCardAnimated> createState() => _NavCardAnimatedState();
}

class _NavCardAnimatedState extends State<_NavCardAnimated> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        transform: Matrix4.translationValues(_pressed ? 0 : 3.0, 0, 0)
          ..multiply(
            Matrix4.diagonal3Values(
              _pressed ? 0.97 : 1.01,
              _pressed ? 0.97 : 1.01,
              1.0,
            ),
          ),
        child: widget.child,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  [PATCH B05] Pulsing "Take Medicines" button
// ════════════════════════════════════════════════════════════
class _PulseTakeMedsButton extends StatelessWidget {
  final Animation<double> pulseAnim;
  final VoidCallback onTap;
  final Color accent;
  const _PulseTakeMedsButton({
    required this.pulseAnim,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, child) {
        final spread = pulseAnim.value * 6.0;
        final blurR = 4 + pulseAnim.value * 10;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.4 * (1 - pulseAnim.value)),
                blurRadius: blurR,
                spreadRadius: spread,
              ),
            ],
          ),
          child: child,
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.12), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 13, color: accent),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.t(context, 'medi_take_medicines'),
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  [PATCH B04] Shimmer CustomPainter for progress card
// ════════════════════════════════════════════════════════════
class _ShimmerPainter extends CustomPainter {
  final double progress;
  const _ShimmerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final left = (-0.70 + progress * 2.0) * size.width;
    final shimmerW = size.width * 0.45;
    double opacity = 0.0;
    if (progress < 0.2) {
      opacity = progress / 0.2;
    } else if (progress < 0.8) {
      opacity = 1.0;
    } else {
      opacity = 1.0 - (progress - 0.8) / 0.2;
    }
    opacity = (opacity * 0.22).clamp(0.0, 0.22);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: opacity),
        Colors.transparent,
      ],
    );
    final rect = Rect.fromLTWH(left, 0, shimmerW, size.height);
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}

// ════════════════════════════════════════════════════════════
//  Ring Painter
// ════════════════════════════════════════════════════════════
class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = (size.width - strokeWidth) / 2;
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}

// ─── ASK AHVI FAB (matches Skincare style exactly) ───────────────────────────
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
    final accent = context.themeTokens.accent.primary;
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
              Positioned.fill(
                child: Opacity(
                  opacity: _pulseOpacity.value,
                  child: Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
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
              color: accent,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.40),
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
                  child: const Text(
                    '',
                    style: TextStyle(fontSize: 11, color: Colors.white),
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

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // [ADDED B08] for CupertinoPicker
import 'package:flutter/services.dart'; // [ADDED B12] for input formatters
import 'package:provider/provider.dart';
import 'package:myapp/app_routes.dart';
import 'package:myapp/profile.dart';
import 'package:myapp/services/appwrite_service.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Screen1(),
  ));
}

// ── Body shape image constants ──────────────────────────────────────────────
const Map<String, List<Map<String, String>>> kBodyShapes = {
  'women': [
    {'name': 'Hourglass',  'img': 'assets/body_shapes/women_hourglass.jpeg'},
    {'name': 'Pear',       'img': 'assets/body_shapes/women_pear.jpeg'},
    {'name': 'Apple',      'img': 'assets/body_shapes/women_apple.jpeg'},
    {'name': 'Rectangle',  'img': 'assets/body_shapes/women_rectangle.jpeg'},
    {'name': 'Inverted',   'img': 'assets/body_shapes/women_inverted.jpeg'},
  ],
  'men': [
    {'name': 'Rectangle',  'img': 'assets/body_shapes/men_rectangle.jpeg'},
    {'name': 'Triangle',   'img': 'assets/body_shapes/men_traingle.jpeg'},
    {'name': 'Trapezoid',  'img': 'assets/body_shapes/men_trapezoid.jpeg'},
    {'name': 'Oval',       'img': 'assets/body_shapes/men_oval.jpeg'},
    {'name': 'Inverted',   'img': 'assets/body_shapes/men_inverted.jpeg'},
  ],
};

class Screen1 extends StatefulWidget {
  const Screen1({super.key});

  @override
  State<Screen1> createState() => _Screen1State();
}

// [ADDED B01, B02, B05] TickerProviderStateMixin supports multiple AnimationControllers
class _Screen1State extends State<Screen1> with TickerProviderStateMixin {
  int _selectedTab = 0;
  int _selectedGender = -1; // no default — user must select

  // ── [ADDED B06] Press states for pills and button ──
  final List<bool> _pillPressed = [false, false, false];
  bool _btnPressed = false;

  // ── [ADDED B04] FocusNodes for inputs ──
  late FocusNode _nameFocus;
  late FocusNode _phoneFocus;
  bool _nameFocused = false;
  bool _phoneFocused = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  // ── Country code selection state ──
  String _selectedCountryCode = '+91';
  String _selectedCountryFlag = '🇮🇳';
  String _selectedCountryName = 'India';
  int _selectedCountryMaxDigits = 10;

  // Full country list: flag, name, dial code, max digits
  static const List<Map<String, dynamic>> _countries = [
    {'flag': '🇮🇳', 'name': 'India', 'code': '+91', 'digits': 10},
    {'flag': '🇺🇸', 'name': 'United States', 'code': '+1', 'digits': 10},
    {'flag': '🇬🇧', 'name': 'United Kingdom', 'code': '+44', 'digits': 10},
    {'flag': '🇦🇺', 'name': 'Australia', 'code': '+61', 'digits': 9},
    {'flag': '🇨🇦', 'name': 'Canada', 'code': '+1', 'digits': 10},
    {'flag': '🇩🇪', 'name': 'Germany', 'code': '+49', 'digits': 11},
    {'flag': '🇫🇷', 'name': 'France', 'code': '+33', 'digits': 9},
    {'flag': '🇯🇵', 'name': 'Japan', 'code': '+81', 'digits': 10},
    {'flag': '🇨🇳', 'name': 'China', 'code': '+86', 'digits': 11},
    {'flag': '🇧🇷', 'name': 'Brazil', 'code': '+55', 'digits': 11},
    {'flag': '🇲🇽', 'name': 'Mexico', 'code': '+52', 'digits': 10},
    {'flag': '🇿🇦', 'name': 'South Africa', 'code': '+27', 'digits': 9},
    {'flag': '🇳🇬', 'name': 'Nigeria', 'code': '+234', 'digits': 10},
    {'flag': '🇰🇪', 'name': 'Kenya', 'code': '+254', 'digits': 9},
    {'flag': '🇸🇬', 'name': 'Singapore', 'code': '+65', 'digits': 8},
    {'flag': '🇦🇪', 'name': 'UAE', 'code': '+971', 'digits': 9},
    {'flag': '🇸🇦', 'name': 'Saudi Arabia', 'code': '+966', 'digits': 9},
    {'flag': '🇵🇰', 'name': 'Pakistan', 'code': '+92', 'digits': 10},
    {'flag': '🇧🇩', 'name': 'Bangladesh', 'code': '+880', 'digits': 10},
    {'flag': '🇱🇰', 'name': 'Sri Lanka', 'code': '+94', 'digits': 9},
    {'flag': '🇳🇵', 'name': 'Nepal', 'code': '+977', 'digits': 10},
    {'flag': '🇮🇩', 'name': 'Indonesia', 'code': '+62', 'digits': 11},
    {'flag': '🇵🇭', 'name': 'Philippines', 'code': '+63', 'digits': 10},
    {'flag': '🇲🇾', 'name': 'Malaysia', 'code': '+60', 'digits': 10},
    {'flag': '🇹🇭', 'name': 'Thailand', 'code': '+66', 'digits': 9},
    {'flag': '🇻🇳', 'name': 'Vietnam', 'code': '+84', 'digits': 10},
    {'flag': '🇰🇷', 'name': 'South Korea', 'code': '+82', 'digits': 10},
    {'flag': '🇮🇹', 'name': 'Italy', 'code': '+39', 'digits': 10},
    {'flag': '🇪🇸', 'name': 'Spain', 'code': '+34', 'digits': 9},
    {'flag': '🇵🇹', 'name': 'Portugal', 'code': '+351', 'digits': 9},
    {'flag': '🇳🇱', 'name': 'Netherlands', 'code': '+31', 'digits': 9},
    {'flag': '🇧🇪', 'name': 'Belgium', 'code': '+32', 'digits': 9},
    {'flag': '🇨🇭', 'name': 'Switzerland', 'code': '+41', 'digits': 9},
    {'flag': '🇸🇪', 'name': 'Sweden', 'code': '+46', 'digits': 9},
    {'flag': '🇳🇴', 'name': 'Norway', 'code': '+47', 'digits': 8},
    {'flag': '🇩🇰', 'name': 'Denmark', 'code': '+45', 'digits': 8},
    {'flag': '🇫🇮', 'name': 'Finland', 'code': '+358', 'digits': 9},
    {'flag': '🇷🇺', 'name': 'Russia', 'code': '+7', 'digits': 10},
    {'flag': '🇺🇦', 'name': 'Ukraine', 'code': '+380', 'digits': 9},
    {'flag': '🇵🇱', 'name': 'Poland', 'code': '+48', 'digits': 9},
    {'flag': '🇦🇷', 'name': 'Argentina', 'code': '+54', 'digits': 10},
    {'flag': '🇨🇱', 'name': 'Chile', 'code': '+56', 'digits': 9},
    {'flag': '🇨🇴', 'name': 'Colombia', 'code': '+57', 'digits': 10},
    {'flag': '🇵🇪', 'name': 'Peru', 'code': '+51', 'digits': 9},
    {'flag': '🇹🇷', 'name': 'Turkey', 'code': '+90', 'digits': 10},
    {'flag': '🇮🇱', 'name': 'Israel', 'code': '+972', 'digits': 9},
    {'flag': '🇪🇬', 'name': 'Egypt', 'code': '+20', 'digits': 10},
    {'flag': '🇲🇦', 'name': 'Morocco', 'code': '+212', 'digits': 9},
    {'flag': '🇬🇭', 'name': 'Ghana', 'code': '+233', 'digits': 9},
    {'flag': '🇳🇿', 'name': 'New Zealand', 'code': '+64', 'digits': 9},
  ];

  OverlayEntry? _countryDropdownOverlay;
  final LayerLink _countryLayerLink = LayerLink();

  void _showCountryPicker() {
    if (_countryDropdownOverlay != null) {
      _removeCountryDropdown();
      return;
    }
    final overlay = Overlay.of(context);
    _countryDropdownOverlay = OverlayEntry(
      builder: (_) => _CountryDropdownOverlay(
        link: _countryLayerLink,
        countries: _countries,
        selectedCode: _selectedCountryCode,
        selectedFlag: _selectedCountryFlag,
        onSelected: (country) {
          setState(() {
            _selectedCountryCode = country['code'] as String;
            _selectedCountryFlag = country['flag'] as String;
            _selectedCountryName = country['name'] as String;
            _selectedCountryMaxDigits = country['digits'] as int;
            _phoneCtrl.clear();
          });
          _removeCountryDropdown();
        },
        onDismiss: _removeCountryDropdown,
      ),
    );
    overlay.insert(_countryDropdownOverlay!);
  }

  void _removeCountryDropdown() {
    _countryDropdownOverlay?.remove();
    _countryDropdownOverlay = null;
  }

  // ── [ADDED B08] DOB selection state ──
  String? _selectedDay;
  String? _selectedMonth;
  String? _selectedYear;

  // ── Shop Preferences, Skin Tone & Body Shape state ──
  final Set<String> _shopPrefs = {};
  int _selectedSkinTone = 3;
  String _bodyGender = 'women';
  String _selectedBodyShape = 'Hourglass';

  // ── [ADDED B01] Staggered entrance AnimationController ──
  late AnimationController _entranceController;
  // 7 staggered animations: brandTag / title / subtitle / tabBar /
  // sectionLabel / glassCard / ctaSection
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;

  // ── [ADDED B02] Brand dot pulse AnimationController ──
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  // ── [ADDED B05] Gender pill spring bounce AnimationController ──
  late AnimationController _pillBounceController;
  late Animation<double> _pillBounceScale;
  int _lastTappedGender = -1;

  static const Color bg = Color(0xFFEEF3FF);

  static const Color panel = Color(0xA8FFFFFF);
  static const Color panel2 = Color(0xE0FFFFFF);
  static const Color card = Color(0xE0FFFFFF);
  static const Color cardBorder = Color(0xFFE5E9F7);
  static const Color textColor = Color(0xFF1A1D26);
  static const Color muted = Color(0xFF66708A);
  static const Color accent = Color(0xFF6B91FF);
  static const Color accent2 = Color(0xFF8D7DFF);
  static const Color accent5 = Color(0xFFFFD86E);

  @override
  void initState() {
    super.initState();

    // ── [ADDED B04] FocusNode listeners ──
    _nameFocus = FocusNode()
      ..addListener(() => setState(() => _nameFocused = _nameFocus.hasFocus));
    _phoneFocus = FocusNode()
      ..addListener(() => setState(() => _phoneFocused = _phoneFocus.hasFocus));
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();

    // ── [ADDED B01] Entrance controller (900ms covers all stagger offsets) ──
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // HTML delays: 0 / 80 / 130 / 180 / 220 / 270 / 350ms in a 900ms window
    // Converted to 0.0–1.0 intervals: delay/900 .. (delay+550)/900
    final staggerOffsets = [0, 80, 130, 180, 220, 270, 350];
    const animDuration = 550;
    const totalDuration = 900;

    _fadeAnims = staggerOffsets.map((delay) {
      final begin = delay / totalDuration;
      final end = (delay + animDuration) / totalDuration;
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(begin, end.clamp(0.0, 1.0),
              curve: Curves.easeOutCubic),
        ),
      );
    }).toList();

    _slideAnims = staggerOffsets.map((delay) {
      final begin = delay / totalDuration;
      final end = (delay + animDuration) / totalDuration;
      return Tween<Offset>(
        begin: const Offset(0, 0.4), // ~10px translated down at typical scale
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(begin, end.clamp(0.0, 1.0),
              curve: Curves.easeOutCubic),
        ),
      );
    }).toList();

    _entranceController.forward(); // [ADDED B01] kick off cascade on mount

    // ── [ADDED B02] Pulse controller (2800ms infinite loop) ──
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // ── [ADDED B05] Pill bounce controller (240ms spring) ──
    _pillBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    // TweenSequence: 0→0.93 (20%) → 1.04 (40%) → 1.0 (40%)
    _pillBounceScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.93)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.93, end: 1.04)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.04, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
    ]).animate(_pillBounceController);
  }

  @override
  void dispose() {
    // [ADDED] Dispose all controllers and FocusNodes
    _entranceController.dispose();
    _pulseController.dispose();
    _pillBounceController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _removeCountryDropdown();
    super.dispose();
  }

  // ── [ADDED B01] Helper: wraps a widget with staggered fade + slide ──
  Widget _staggered(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeAnims[index],
      child: SlideTransition(
        position: _slideAnims[index],
        child: child,
      ),
    );
  }

  bool get _isValid {
    return _nameCtrl.text.trim().isNotEmpty &&
        _selectedDay != null &&
        _selectedMonth != null &&
        _selectedYear != null;
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onContinue() async {
    if (!_isValid) {
      _showValidationError('Please complete your name and date of birth.');
      return;
    }
    final genders = ['Male', 'Female', 'Others'];
    final gender = _selectedGender >= 0 ? genders[_selectedGender.clamp(0, genders.length - 1)] : '';
    final dob = '${_selectedDay!} ${_selectedMonth!} ${_selectedYear!}';
    final monthIndex = const [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'
    ].indexOf(_selectedMonth!) + 1;
    final dobIso = DateTime(
      int.parse(_selectedYear!),
      monthIndex,
      int.parse(_selectedDay!),
    ).toUtc().toIso8601String();
    context.read<ProfileController>().updateBasics(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isNotEmpty
          ? '$_selectedCountryCode ${_phoneCtrl.text.trim()}'
          : '',
      gender: gender,
      dob: dob,
      skinTone: _selectedSkinTone,
      bodyShape: _selectedBodyShape,
      shopPrefs: _shopPrefs,
    );
    try {
      await context.read<AppwriteService>().updateCurrentUserProfileFields({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isNotEmpty
            ? '$_selectedCountryCode ${_phoneCtrl.text.trim()}'
            : '',
        'dob': dobIso,
        'gender': gender,
        'skinTone': _selectedSkinTone,
        'bodyShape': _selectedBodyShape,
        'onboarding1': true,
      });
    } catch (e) {
      if (!mounted) return;
      _showValidationError('Could not save profile details. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushNamed(AppRoutes.onboarding2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                color: bg,
                gradient: RadialGradient(
                  center: Alignment(-1.0, -1.0),
                  radius: 1.2,
                  colors: [Color(0x1814CACD), Color(0x0014CACD)],
                  stops: [0.0, 0.65],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.0, 1.0),
                  radius: 1.2,
                  colors: [Color(0x1814CACD), Color(0x0014CACD)],
                  stops: [0.0, 0.65],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        _buildTabBar(),
                        _buildSectionLabel('About You'),
                        _buildGlassCard(),
                        _buildCTASection(),
                      ],
                    ),
                  ),
                ),
                _buildHomeIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── [ADDED B01] stagger index 0 — brand tag ──
          _staggered(
            0,
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.fromLTRB(9, 5, 13, 5),
              decoration: BoxDecoration(
                color: const Color(0x1F8D7DFF),
                border:
                Border.all(color: const Color(0x388D7DFF), width: 1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── [ADDED B02] animated pulsing dot ──
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) => Transform.scale(
                      scale: _pulseScale.value,
                      child: Opacity(
                        opacity: _pulseOpacity.value,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: accent2,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'AHVI',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                      letterSpacing: 0.1 * 11,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── [ADDED B01] stagger index 1 — page title ──
          _staggered(
            1,
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  height: 1.06,
                  letterSpacing: -0.03 * 40,
                  fontFamily: 'SF Pro Display',
                ),
                children: [
                  TextSpan(text: 'Your '),
                  TextSpan(
                    text: 'Profile',
                    style: TextStyle(
                      color: accent2,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -0.02 * 40,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          // ── [ADDED B01] stagger index 2 — subtitle ──
          _staggered(
            2,
            const Text(
              'Tell us about you so AHVI can personalise your styling experience.',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
                color: muted,
                height: 1.55,
                fontFamily: 'DM Sans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['Basics', 'Style', 'Try-On'];
    // ── [ADDED B01] stagger index 3 — tab bar ──
    // Only the current screen's tab (index 0 = Basics) is active and tappable.
    // Subsequent tabs are locked — they become accessible as the user progresses.
    return _staggered(
      3,
      Container(
        margin: const EdgeInsets.only(bottom: 32),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: cardBorder, width: 1),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final isActive = i == _selectedTab;
            // Tabs beyond the current one are locked — not tappable
            final isLocked = i > _selectedTab;
            return Expanded(
              child: GestureDetector(
                // Only allow tapping the current (active) tab; locked tabs do nothing
                onTap: isLocked ? null : () => setState(() => _selectedTab = i),
                child: Opacity(
                  // Locked tabs are visually dimmed to signal they're unavailable
                  opacity: isLocked ? 0.45 : 1.0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOut,
                    padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent, accent2],
                      )
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isActive
                          ? const [
                        BoxShadow(
                            color: Color(0x4D6B91FF),
                            blurRadius: 10,
                            offset: Offset(0, 2)),
                        BoxShadow(
                            color: Color(0x2E6B91FF),
                            blurRadius: 3,
                            offset: Offset(0, 1)),
                      ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tabs[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w500,
                            color: isActive ? textColor : muted,
                            letterSpacing: 0.005 * 13,
                            fontFamily: 'DM Sans',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    // ── [ADDED B01] stagger index 4 — section label ──
    return _staggered(
      4,
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted,
                letterSpacing: 0.10 * 11,
                fontFamily: 'DM Sans',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: cardBorder)),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard() {
    // ── [ADDED B01] stagger index 5 — glass card ──
    return _staggered(
      5,
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 22),
        decoration: BoxDecoration(
          color: card,
          border: Border.all(color: cardBorder, width: 1),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x18000000),
                blurRadius: 40,
                offset: Offset(0, 12)),
            BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 10,
                offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNameField(),
            _buildDivider(),
            _buildPhoneField(),
            _buildDivider(),
            _buildDOBField(),
            _buildDivider(),
            _buildSkinToneField(),
            _buildDivider(),
            _buildShopPrefsField(),
            // Body shape section — slides in when Women or Men is selected
            _BodyShapeReveal(
              visible: _shopPrefs.contains('Women') || _shopPrefs.contains('Men'),
              divider: _buildDivider(),
              child: _buildBodyShapeField(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'FULL NAME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: muted,
                  letterSpacing: 0.07 * 11,
                  fontFamily: 'DM Sans',
                ),
              ),
              SizedBox(width: 6),
              Text('✦',
                  style: TextStyle(fontSize: 10, color: accent5)),
            ],
          ),
          const SizedBox(height: 9),
          Stack(
            alignment: Alignment.centerRight,
            children: [
              // ── [ADDED B04] AnimatedContainer drives fill + glow on focus ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  // Glow ring on focus
                  boxShadow: _nameFocused
                      ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 3,
                    ),
                  ]
                      : [],
                ),
                child: TextField(
                  focusNode: _nameFocus, // [ADDED B04]
                  controller: _nameCtrl,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                    fontFamily: 'DM Sans',
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Sofia Laurent',
                    hintStyle: TextStyle(
                      color: muted.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w400,
                      fontSize: 15,
                      fontFamily: 'DM Sans',
                    ),
                    filled: true,
                    // [ADDED B04] fillColor animates with focus state
                    fillColor: _nameFocused ? panel2 : panel,
                    contentPadding:
                    const EdgeInsets.fromLTRB(15, 13, 40, 13),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                      const BorderSide(color: cardBorder, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                      const BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 14,
                child: Text('✦',
                    style: TextStyle(fontSize: 12, color: accent2)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'PHONE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: muted,
                  letterSpacing: 0.07 * 11,
                  fontFamily: 'DM Sans',
                ),
              ),
              SizedBox(width: 6),
              Text(
                '— optional',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: muted,
                  letterSpacing: 0.01 * 10,
                  fontFamily: 'DM Sans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: _phoneFocused
                  ? [BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: 3)]
                  : [],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Country code button with CompositedTransformTarget ──
                CompositedTransformTarget(
                  link: _countryLayerLink,
                  child: GestureDetector(
                    onTap: _showCountryPicker,
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _phoneFocused ? panel2 : panel,
                        border: Border(
                          top: BorderSide(color: _phoneFocused ? accent : cardBorder, width: 1.5),
                          bottom: BorderSide(color: _phoneFocused ? accent : cardBorder, width: 1.5),
                          left: BorderSide(color: _phoneFocused ? accent : cardBorder, width: 1.5),
                          right: BorderSide(color: _phoneFocused ? accent : cardBorder, width: 1.5),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_selectedCountryFlag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 6),
                          Text(
                            _selectedCountryCode,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                              fontFamily: 'DM Sans',
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: muted, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // ── Number input ──
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: TextField(
                      focusNode: _phoneFocus,
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_selectedCountryMaxDigits),
                      ],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: textColor,
                        fontFamily: 'DM Sans',
                      ),
                      decoration: InputDecoration(
                        hintText: '00000 00000',
                        hintStyle: TextStyle(
                          color: muted.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w400,
                          fontSize: 15,
                          fontFamily: 'DM Sans',
                        ),
                        filled: true,
                        fillColor: _phoneFocused ? panel2 : panel,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: cardBorder, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: accent, width: 1.5),
                        ),
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
  }

  Widget _buildGenderField() {
    final genders = ['Male', 'Female', 'Others'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GENDER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: muted,
              letterSpacing: 0.07 * 11,
              fontFamily: 'DM Sans',
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: List.generate(genders.length, (i) {
              final isSelected = i == _selectedGender;
              final isAnimating = i == _lastTappedGender;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: i < genders.length - 1 ? 8 : 0),
                  // ── [ADDED B06] GestureDetector with press-down ──
                  child: GestureDetector(
                    onTapDown: (_) =>
                        setState(() => _pillPressed[i] = true),
                    onTapUp: (_) {
                      setState(() {
                        _pillPressed[i] = false;
                        _selectedGender = i;
                        _lastTappedGender = i;
                      });
                      // [ADDED B05] trigger spring bounce
                      _pillBounceController.forward(from: 0);
                    },
                    onTapCancel: () =>
                        setState(() => _pillPressed[i] = false),
                    child: AnimatedScale(
                      // [ADDED B06] scale 0.97 on press-down
                      scale: _pillPressed[i] ? 0.97 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: AnimatedBuilder(
                        // [ADDED B05] spring bounce on the newly selected pill
                        animation: _pillBounceController,
                        builder: (_, child) {
                          final scale = (isAnimating && isSelected)
                              ? _pillBounceScale.value
                              : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: child,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut, // [ADDED B05] match curve
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [accent, accent2],
                            )
                                : null,
                            color: isSelected ? null : panel,
                            border: Border.all(
                              color:
                              isSelected ? accent : cardBorder,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: isSelected
                                ? const [
                              BoxShadow(
                                  color: Color(0x596B91FF),
                                  blurRadius: 14,
                                  offset: Offset(0, 4)),
                              BoxShadow(
                                  color: Color(0x336B91FF),
                                  blurRadius: 4,
                                  offset: Offset(0, 1)),
                            ]
                                : null,
                          ),
                          child: Text(
                            genders[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color:
                              isSelected ? textColor : muted,
                              fontFamily: 'DM Sans',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDOBField() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DATE OF BIRTH',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: muted,
              letterSpacing: 0.07 * 11,
              fontFamily: 'DM Sans',
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              // ── [ADDED B08] functional DOB dropdowns ──
              Expanded(
                  child: _buildSelectDropdown(
                    'Day',
                    _selectedDay,
                    List.generate(31, (i) => '${i + 1}'),
                        (val) => setState(() => _selectedDay = val),
                  )),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSelectDropdown(
                    'Month',
                    _selectedMonth,
                    const [
                      'January', 'February', 'March', 'April',
                      'May', 'June', 'July', 'August',
                      'September', 'October', 'November', 'December'
                    ],
                        (val) => setState(() => _selectedMonth = val),
                  )),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSelectDropdown(
                    'Year',
                    _selectedYear,
                    List.generate(58, (i) => '${2007 - i}'),
                        (val) => setState(() => _selectedYear = val),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  // ── [ADDED B07, B08] Functional dropdown with focus glow + real values ──
  Widget _buildSelectDropdown(
      String hint,
      String? selectedValue,
      List<String> options,
      ValueChanged<String?> onChanged,
      ) {
    return GestureDetector(
      onTap: () {
        _nameFocus.unfocus();
        _phoneFocus.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
        _showPicker(hint, options, onChanged);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          // [ADDED B07] background switches when a value is selected
          color: selectedValue != null ? panel2 : panel,
          border: Border.all(
            // [ADDED B07] border highlights when value present
            color: selectedValue != null ? accent : cardBorder,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
          // [ADDED B07] glow ring when selected
          boxShadow: selectedValue != null
              ? [
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 12,
              spreadRadius: 3,
            ),
          ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                selectedValue ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  // [ADDED B08] show white text once a value is chosen
                  color: selectedValue != null ? textColor : muted,
                  fontFamily: 'DM Sans',
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  // ── [ADDED B08] Bottom sheet CupertinoPicker to select DOB values ──
  void _showPicker(
      String title,
      List<String> options,
      ValueChanged<String?> onChanged,
      ) {
    // Explicitly unfocus all text fields so keyboard fully dismisses
    _nameFocus.unfocus();
    _phoneFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    // Short delay lets the keyboard fully close before sheet opens,
    // preventing Flutter from re-raising the keyboard for the sheet
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      _doShowPicker(title, options, onChanged);
    });
  }

  void _doShowPicker(
      String title,
      List<String> options,
      ValueChanged<String?> onChanged,
      ) {
    int tempIndex = 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: 280,
        child: Column(
          children: [
            // Sheet handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCDD4E8),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: muted,
                          fontSize: 13,
                          fontFamily: 'DM Sans')),
                  GestureDetector(
                    onTap: () {
                      onChanged(options[tempIndex]);
                      Navigator.pop(context);
                    },
                    child: const Text('Done',
                        style: TextStyle(
                            color: accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'DM Sans')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                backgroundColor: Colors.transparent,
                itemExtent: 36,
                onSelectedItemChanged: (i) => tempIndex = i,
                children: options
                    .map((o) => Center(
                  child: Text(o,
                      style: const TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontFamily: 'DM Sans')),
                ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Skin Tone Field ──
  Widget _buildSkinToneField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SKIN TONE',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: muted, letterSpacing: 0.07 * 11, fontFamily: 'DM Sans',
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(kSkinTones.length, (i) {
                final active = _selectedSkinTone == i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSkinTone = i + 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: kSkinTones[i],
                      shape: BoxShape.circle,
                      border: active
                          ? Border.all(color: accent, width: 3)
                          : Border.all(color: Colors.transparent, width: 3),
                    ),
                    transform: active
                        ? (Matrix4.identity()..scale(1.15))
                        : Matrix4.identity(),
                    transformAlignment: Alignment.center,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shop Preferences Field ──
  // Three mutually exclusive cards: Women / Men / Both
  static const List<Map<String, String>> _shopPrefCards = [
    {'label': 'Women', 'img': 'assets/shop/women.jpg'},
    {'label': 'Men',   'img': 'assets/shop/men.jpg'},
    {'label': 'Both',  'img': 'assets/shop/both.jpeg'},
  ];

  Widget _buildShopPrefsField() {
    // Determine which card is visually active
    final bool womenSelected = _shopPrefs.length == 1 && _shopPrefs.contains('Women');
    final bool menSelected   = _shopPrefs.length == 1 && _shopPrefs.contains('Men');
    final bool bothSelected  = _shopPrefs.contains('Women') && _shopPrefs.contains('Men');

    bool isCardActive(String label) {
      if (label == 'Women') return womenSelected;
      if (label == 'Men')   return menSelected;
      return bothSelected; // Both
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SHOP PREFERENCES',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: muted, letterSpacing: 0.07 * 11, fontFamily: 'DM Sans',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(_shopPrefCards.length, (index) {
              final pref    = _shopPrefCards[index];
              final label   = pref['label']!;
              final isActive = isCardActive(label);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left:  index == 0 ? 0 : 5,
                    right: index == _shopPrefCards.length - 1 ? 0 : 5,
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _shopPrefs.clear();
                      if (label == 'Both') {
                        _shopPrefs.addAll(['Women', 'Men']);
                        _bodyGender = 'both';
                        _selectedBodyShape = kBodyShapes['women']!.first['name']!;
                      } else if (label == 'Women') {
                        _shopPrefs.add('Women');
                        _bodyGender = 'women';
                        _selectedBodyShape = kBodyShapes['women']!.first['name']!;
                      } else {
                        _shopPrefs.add('Men');
                        _bodyGender = 'men';
                        _selectedBodyShape = kBodyShapes['men']!.first['name']!;
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive ? accent : cardBorder,
                          width: isActive ? 1.5 : 1,
                        ),
                        color: isActive ? const Color(0x226B91FF) : panel,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              pref['img']!,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, _, _) => const SizedBox(),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.65),
                                  ],
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    if (isActive)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check_circle,
                                            color: accent, size: 13),
                                      ),
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        color: textColor, fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'DM Sans',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Body Shape Field ──
  Widget _buildBodyShapeField() {
    if (_bodyGender == 'both') {
      // Show women shapes section + men shapes section
      final womenShapes = kBodyShapes['women']!;
      final menShapes = kBodyShapes['men']!;
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BODY SHAPE',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: muted, letterSpacing: 0.07 * 11, fontFamily: 'DM Sans',
              ),
            ),
            const SizedBox(height: 12),
            // Women section label
            const Text(
              'Women',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: accent, letterSpacing: 0.04 * 12, fontFamily: 'DM Sans',
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10, mainAxisSpacing: 10,
              childAspectRatio: 0.65,
              children: womenShapes.map((shape) {
                final isActive = _selectedBodyShape == shape['name'];
                return _buildBodyShapeCard(shape, isActive);
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Men section label
            const Text(
              'Men',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: accent2, letterSpacing: 0.04 * 12, fontFamily: 'DM Sans',
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10, mainAxisSpacing: 10,
              childAspectRatio: 0.65,
              children: menShapes.map((shape) {
                final isActive = _selectedBodyShape == shape['name'];
                return _buildBodyShapeCard(shape, isActive);
              }).toList(),
            ),
          ],
        ),
      );
    }

    final shapes = kBodyShapes[_bodyGender] ?? kBodyShapes['women']!;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BODY SHAPE',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: muted, letterSpacing: 0.07 * 11, fontFamily: 'DM Sans',
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 0.65,
            children: shapes.map((shape) {
              final isActive = _selectedBodyShape == shape['name'];
              return _buildBodyShapeCard(shape, isActive);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyShapeCard(Map<String, String> shape, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _selectedBodyShape = shape['name']!),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? accent : cardBorder,
            width: isActive ? 2 : 1,
          ),
          color: isActive ? const Color(0x226B91FF) : panel,
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13)),
                child: Image.asset(
                  shape['img']!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.person, color: muted, size: 36),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                shape['name']!,
                style: TextStyle(
                  color: isActive ? accent : muted,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontFamily: 'DM Sans',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Transform.translate(
      offset: const Offset(-2, 0),
      child: Container(width: double.infinity, height: 1, color: cardBorder),
    );
  }

  Widget _buildCTASection() {
    // ── [ADDED B01] stagger index 6 — CTA section ──
    return _staggered(
      6,
      Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          children: [
            // ── [ADDED B09, B10] Continue button with navigation + press-down ──
            GestureDetector(
              onTapDown: (_) => setState(() => _btnPressed = true),
              onTapUp: (_) {
                setState(() => _btnPressed = false);
                _onContinue();
              },
              onTapCancel: () => setState(() => _btnPressed = false),
              child: AnimatedScale(
                // [ADDED B10] scale 0.98 on press, matching HTML :active
                scale: _btnPressed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, accent2],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    // [ADDED B10] shadow shrinks on press
                    boxShadow: _btnPressed
                        ? const [
                      BoxShadow(
                          color: Color(0x336B91FF),
                          blurRadius: 20,
                          offset: Offset(0, 6)),
                      BoxShadow(
                          color: Color(0x1A6B91FF),
                          blurRadius: 6,
                          offset: Offset(0, 2)),
                    ]
                        : const [
                      BoxShadow(
                          color: Color(0x596B91FF),
                          blurRadius: 32,
                          offset: Offset(0, 10)),
                      BoxShadow(
                          color: Color(0x336B91FF),
                          blurRadius: 8,
                          offset: Offset(0, 3)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0x17FFFFFF),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.55],
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              letterSpacing: 0.01 * 15.5,
                              fontFamily: 'DM Sans',
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '→',
                            style: TextStyle(
                                fontSize: 15,
                                color: Color(0xA6F5F7FF)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Progress dots — already IMPLEMENTED (B11), no change needed
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final isActive = i == 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3.5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      width: isActive ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? accent2 : const Color(0xFFCDD4E8),
                        borderRadius:
                        BorderRadius.circular(isActive ? 3 : 50),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeIndicator() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
      alignment: Alignment.center,
      child: Container(
        width: 130,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFCDD4E8),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }
}

// ── Animated reveal widget for Body Shape section ──
class _BodyShapeReveal extends StatefulWidget {
  final bool visible;
  final Widget divider;
  final Widget child;

  const _BodyShapeReveal({
    required this.visible,
    required this.divider,
    required this.child,
  });

  @override
  State<_BodyShapeReveal> createState() => _BodyShapeRevealState();
}

class _BodyShapeRevealState extends State<_BodyShapeReveal>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
    ));

    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.visible) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_BodyShapeReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _ctrl.forward(from: 0.0);
    } else if (!widget.visible && oldWidget.visible) {
      _ctrl.reverse();
    }
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
      builder: (context, child) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOutCubic,
          child: _ctrl.isDismissed
              ? const SizedBox.shrink()
              : FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: ScaleTransition(
                      scale: _scale,
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          widget.divider,
                          widget.child,
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

// ── Country Dropdown Overlay — appears below the button ──
class _CountryDropdownOverlay extends StatefulWidget {
  final LayerLink link;
  final List<Map<String, dynamic>> countries;
  final String selectedCode;
  final String selectedFlag;
  final void Function(Map<String, dynamic>) onSelected;
  final VoidCallback onDismiss;

  const _CountryDropdownOverlay({
    required this.link,
    required this.countries,
    required this.selectedCode,
    required this.selectedFlag,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  State<_CountryDropdownOverlay> createState() => _CountryDropdownOverlayState();
}

class _CountryDropdownOverlayState extends State<_CountryDropdownOverlay> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const sheetBg  = Color(0xFFFFFFFF);
    const itemBg   = Color(0xFFF0F4FF);
    const borderCol = Color(0xFFE5E9F7);
    const labelCol  = Color(0xFF66708A);
    const textCol   = Color(0xFF1A1D26);
    const accentCol = Color(0xFF6B91FF);

    final filtered = widget.countries.where((c) {
      final name = (c['name'] as String).toLowerCase();
      final code = c['code'] as String;
      final q = _search.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();

    return Stack(
      children: [
        // Dismiss tap area
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        // Dropdown positioned below the button
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          offset: const Offset(0, 54), // below button (height 50 + 4 gap)
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 260,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol, width: 1.2),
                boxShadow: const [
                  BoxShadow(color: Color(0x18000000), blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(fontSize: 13, color: textCol, fontFamily: 'DM Sans'),
                      decoration: InputDecoration(
                        hintText: 'Search…',
                        hintStyle: const TextStyle(color: labelCol, fontSize: 13, fontFamily: 'DM Sans'),
                        prefixIcon: const Icon(Icons.search_rounded, color: labelCol, size: 17),
                        filled: true,
                        fillColor: itemBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: borderCol, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: accentCol, width: 1.2),
                        ),
                      ),
                    ),
                  ),
                  // List
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final isSelected = c['code'] == widget.selectedCode &&
                            c['flag'] == widget.selectedFlag;
                        return GestureDetector(
                          onTap: () => widget.onSelected(c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0x256B91FF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(c['flag'] as String, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    c['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: textCol,
                                      fontFamily: 'DM Sans',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  c['code'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: labelCol,
                                    fontFamily: 'DM Sans',
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_rounded, color: accentCol, size: 15),
                                ],
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
          ),
        ),
      ],
    );
  }
}

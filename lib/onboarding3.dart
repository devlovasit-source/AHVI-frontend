import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myapp/app_routes.dart';
import 'package:myapp/profile.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Screen3(),
  ));
}


// ── Color constants (Light Mode) ───────────────────────────────────────────────
const Color _bg  = Color(0xFFEEF3FF);
const Color _bg2 = Color(0xFFFFFFFF);
const Color _panel  = Color(0xA8FFFFFF); // rgba(255,255,255,.66)
const Color _panel2 = Color(0x33C5CDED); // soft blue-grey tint
const Color _card       = Color(0xE0FFFFFF); // rgba(255,255,255,.88)
const Color _cardBorder = Color(0xFFE5E9F7);
const Color _text  = Color(0xFF1A1D26);
const Color _muted = Color(0xFF66708A);

const Color _accent1 = Color(0xFF6B91FF); // blue
const Color _accent2 = Color(0xFF8D7DFF); // purple
const Color _accent3 = Color(0xFF04D7C8); // teal
const Color _accent4 = Color(0xFF14CACD); // teal-alt

class Screen3 extends StatefulWidget {
  const Screen3({super.key});

  @override
  State<Screen3> createState() => _Screen3State();
}

class _Screen3State extends State<Screen3> {
  bool _personalizationEnabled = false;
  bool _faceUploaded = false;
  bool _bodyUploaded = false;
  int _activeTab = 3;

  bool get _isValid {
    if (!_personalizationEnabled) return true;
    return _faceUploaded && _bodyUploaded;
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onSkip() async {
    context.read<ProfileController>().updatePersonalization(
      enabled: false,
      faceUploaded: false,
      bodyUploaded: false,
    );
    try {
      await context.read<AppwriteService>().updateCurrentUserProfileFields({
        'onboarding3': true,
      });
    } catch (e) {
      if (!mounted) return;
      _showValidationError('Could not finish onboarding. Please try again.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.main,
      (route) => false,
    );
  }

  Future<void> _onSaveContinue() async {
    if (!_isValid) {
      _showValidationError('Please upload both face and body photos.');
      return;
    }
    context.read<ProfileController>().updatePersonalization(
      enabled: _personalizationEnabled,
      faceUploaded: _faceUploaded,
      bodyUploaded: _bodyUploaded,
    );
    // Mark onboarding as fully complete — ONLY here, after all 3 screens done
    try {
      await context.read<AppwriteService>().updateCurrentUserProfileFields({
        'onboarding3': true,
      });
    } catch (e) {
      if (!mounted) return;
      _showValidationError('Could not finish onboarding. Please try again.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.main,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg2,
      body: Stack(
        children: [
          // ── Atmospheric background ──────────────────────────
          const _AtmosphericBackground(),

          // ── Main content ────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        _Header(),

                        // Tab Bar
                        _TabBar(activeTab: _activeTab, onTabSelected: (i) => setState(() => _activeTab = i)),
                        const SizedBox(height: 32),

                        // Section Divider
                        _SectionDivider(),
                        const SizedBox(height: 16),

                        // Intro Card
                        _IntroCard(),
                        const SizedBox(height: 16),

                        // Toggle Card
                        _ToggleCard(
                          enabled: _personalizationEnabled,
                          onChanged: (v) => setState(() => _personalizationEnabled = v),
                        ),
                        const SizedBox(height: 16),

                        // Optional Badge
                        _OptionalBadge(),
                        const SizedBox(height: 14),

                        // Upload Section
                        _UploadSection(
                          enabled: _personalizationEnabled,
                          faceUploaded: _faceUploaded,
                          bodyUploaded: _bodyUploaded,
                          onFaceTap: () => setState(() => _faceUploaded = !_faceUploaded),
                          onBodyTap: () => setState(() => _bodyUploaded = !_bodyUploaded),
                        ),
                        const SizedBox(height: 24),

                        // Privacy Block
                        _PrivacyBlock(),
                        const SizedBox(height: 32),

                        // CTA Section
                        _CtaSection(
                          onBack: () => Navigator.of(context).pop(),
                          onSaveContinue: _onSaveContinue,
                        ),

                        // Skip row
                        _SkipRow(onSkip: _onSkip),

                        // Progress dots
                        _ProgressDots(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),

                // Home indicator
                _HomeIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Atmospheric Background ─────────────────────────────────────
class _AtmosphericBackground extends StatelessWidget {
  const _AtmosphericBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          gradient: RadialGradient(
            center: Alignment(-1.1, -1.0),
            radius: 1.4,
            colors: [Color(0x256B91FF), Color(0x006B91FF)],
          ),
        ),
        child: Stack(
          children: [
            // Top-right purple
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(1.16, -1.0),
                    radius: 1.3,
                    colors: [Color(0x228D7DFF), Color(0x008D7DFF)],
                  ),
                ),
              ),
            ),
            // Bottom-left teal
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-1.08, 1.1),
                    radius: 1.4,
                    colors: [Color(0x1814CACD), Color(0x0014CACD)],
                  ),
                ),
              ),
            ),
            // Bottom-right blue
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(1.16, 1.1),
                    radius: 1.3,
                    colors: [Color(0x1A6B91FF), Color(0x006B91FF)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand tag
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.fromLTRB(9, 5, 14, 5),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: _cardBorder, width: 1),
              boxShadow: const [
                BoxShadow(color: Color(0x126B91FF), blurRadius: 24, offset: Offset(0, 6)),
                BoxShadow(color: Color(0x22FFFFFF), blurRadius: 0, spreadRadius: 0, offset: Offset(0, 1)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _accent4,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'AHVI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _accent4,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          // Page title
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 34,
                fontWeight: FontWeight.w400,
                color: _text,
                height: 1.08,
              ),
              children: [
                TextSpan(text: 'Virtual '),
                TextSpan(
                  text: 'Try-On',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: _accent2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Personalize your fit experience with a few photos.',
            style: TextStyle(
              fontSize: 15,
              color: _muted,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Bar ─────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabSelected;
  const _TabBar({required this.activeTab, required this.onTabSelected});

  @override
  Widget build(BuildContext context) {
    const tabs = ['Basics', 'Style', 'Try-On'];
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x126B91FF), blurRadius: 24, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == activeTab;
          final isTryOn = i == 2;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabSelected(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: (isActive || isTryOn)
                    ? BoxDecoration(
                  gradient: isTryOn
                      ? const LinearGradient(
                    colors: [Color(0xFF6B91FF), Color(0xFF8D7DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                      : null,
                  color: isTryOn ? null : const Color(0xFFEDF0FF),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                        color: isTryOn
                            ? const Color(0x336B91FF)
                            : const Color(0x1A6B91FF),
                        blurRadius: isTryOn ? 14 : 8,
                        offset: Offset(0, isTryOn ? 4 : 2)),
                    if (!isTryOn)
                      const BoxShadow(color: Color(0x22FFFFFF), blurRadius: 0, offset: Offset(0, 1)),
                  ],
                )
                    : null,
                child: Text(
                  tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: (isActive || isTryOn) ? FontWeight.w600 : FontWeight.w500,
                    color: isTryOn ? Colors.white : (isActive ? _accent1 : _muted),
                    letterSpacing: 0.065,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Section Divider ─────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'VIRTUAL TRY-ON',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _muted,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: _cardBorder)),
      ],
    );
  }
}

// ── Intro Card ──────────────────────────────────────────────────
class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x148D7DFF), blurRadius: 24, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shimmer top strip
            Container(
              height: 1.5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x608D7DFF),
                    Color(0x3814CACD),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.35, 0.65, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                children: [
                  // Intro header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Try-on icon
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment(-0.6, -0.8),
                            end: Alignment(0.6, 0.8),
                            colors: [Color(0x188D7DFF), Color(0x146B91FF)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x2A8D7DFF), width: 1),
                          boxShadow: const [
                            BoxShadow(color: Color(0x148D7DFF), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.person_outline, color: _accent2, size: 24),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Text block
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Personalized Fit Preview',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _text,
                                  letterSpacing: -0.16,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Upload photos to improve fit accuracy and how outfits look on your body type.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: _muted,
                                  fontWeight: FontWeight.w300,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Trust strip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0x0A04D7C8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x2204D7C8), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, color: _accent3, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(fontSize: 12, color: _accent3, letterSpacing: 0.12),
                              children: [
                                TextSpan(text: 'Photos are '),
                                TextSpan(
                                  text: 'end-to-end encrypted',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(text: ' and never shared.'),
                              ],
                            ),
                          ),
                        ),
                      ],
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
}

// ── Toggle Card ─────────────────────────────────────────────────
class _ToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _ToggleCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _cardBorder, width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x148D7DFF), blurRadius: 24, offset: Offset(0, 6)),
            BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Enable try-on personalization',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _text,
                      letterSpacing: -0.15,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'You can use AHVI without this.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w300,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // iOS-style toggle
            GestureDetector(
              onTap: () => onChanged(!enabled),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 51,
                height: 31,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  color: enabled ? _accent2 : const Color(0xFFDDE2F0),
                  boxShadow: enabled
                      ? const [BoxShadow(color: Color(0x288D7DFF), blurRadius: 0, spreadRadius: 3)]
                      : null,
                  border: enabled ? null : Border.all(color: _cardBorder),
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      top: 3,
                      left: enabled ? 23 : 3,
                      child: Container(
                        width: 25,
                        height: 25,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
                            BoxShadow(color: Color(0x22000000), blurRadius: 2, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Optional Badge ──────────────────────────────────────────────
class _OptionalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: _cardBorder, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: _muted.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Both uploads are optional',
            style: TextStyle(
              fontSize: 11,
              color: _muted,
              letterSpacing: 0.385,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: _muted.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upload Section ──────────────────────────────────────────────
class _UploadSection extends StatelessWidget {
  final bool enabled;
  final bool faceUploaded;
  final bool bodyUploaded;
  final VoidCallback onFaceTap;
  final VoidCallback onBodyTap;

  const _UploadSection({
    required this.enabled,
    required this.faceUploaded,
    required this.bodyUploaded,
    required this.onFaceTap,
    required this.onBodyTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 320),
      opacity: enabled ? 1.0 : 0.32,
      child: Column(
        children: [
          _UploadRow(
            title: 'Add a face photo',
            subtitle: 'Used only to enhance facial fit and styling.',
            uploaded: faceUploaded,
            isFace: true,
            onTap: enabled ? onFaceTap : null,
          ),
          const SizedBox(height: 12),
          _UploadRow(
            title: 'Add a full body photo',
            subtitle: 'Improves outfit proportion accuracy.',
            uploaded: bodyUploaded,
            isFace: false,
            onTap: enabled ? onBodyTap : null,
          ),
        ],
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool uploaded;
  final bool isFace;
  final VoidCallback? onTap;

  const _UploadRow({
    required this.title,
    required this.subtitle,
    required this.uploaded,
    required this.isFace,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = uploaded ? const Color(0x448D7DFF) : _cardBorder;
    final bgColor = uploaded ? const Color(0xFFF4F2FF) : _card;
    final iconBgColor = uploaded ? const Color(0x128D7DFF) : _panel;
    final iconBorderColor = uploaded ? const Color(0x338D7DFF) : _cardBorder;

    // Thumb gradient
    final thumbGradient = isFace
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x208D7DFF), Color(0x146B91FF)],
    )
        : const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x1A04D7C8), Color(0x146B91FF)],
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: uploaded
              ? const [
            BoxShadow(color: Color(0x188D7DFF), blurRadius: 20, offset: Offset(0, 5)),
            BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
          ]
              : const [
            BoxShadow(color: Color(0x0E8D7DFF), blurRadius: 10, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Icon wrap
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: iconBorderColor, width: 1),
                gradient: uploaded ? thumbGradient : null,
              ),
              child: Center(
                child: Icon(
                  isFace ? Icons.person_outline : Icons.accessibility_new_outlined,
                  color: uploaded ? _accent2 : _muted,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _text,
                      letterSpacing: -0.14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (!uploaded)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _muted,
                        fontWeight: FontWeight.w300,
                        height: 1.4,
                      ),
                    ),
                  if (uploaded)
                    Row(
                      children: const [
                        Icon(Icons.check, color: _accent3, size: 12),
                        SizedBox(width: 5),
                        Text(
                          'Photo added · encrypted',
                          style: TextStyle(
                            fontSize: 11,
                            color: _accent3,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.22,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Row action
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: uploaded ? const Color(0x188D7DFF) : _panel,
                shape: BoxShape.circle,
                border: Border.all(
                  color: uploaded ? const Color(0x338D7DFF) : _cardBorder,
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(
                  uploaded ? Icons.check : Icons.chevron_right,
                  color: uploaded ? _accent2 : _muted,
                  size: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Privacy Block ───────────────────────────────────────────────
class _PrivacyBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0x0A04D7C8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x2204D7C8), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0x1204D7C8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(Icons.shield_outlined, color: _accent3, size: 17),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Privacy is Protected',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _accent3,
                    letterSpacing: 0.25,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w300,
                      height: 1.55,
                    ),
                    children: [
                      TextSpan(text: 'Photos are used solely for fit modeling and are '),
                      TextSpan(
                        text: 'deleted on request',
                        style: TextStyle(color: _text, fontWeight: FontWeight.w500),
                      ),
                      TextSpan(text: '. AHVI does not sell or share personal data.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── CTA Section ─────────────────────────────────────────────────
class _CtaSection extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSaveContinue;

  const _CtaSection({
    required this.onBack,
    required this.onSaveContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Back button
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder, width: 1),
              boxShadow: const [
                BoxShadow(color: Color(0x126B91FF), blurRadius: 24, offset: Offset(0, 6)),
              ],
            ),
            child: const Center(
              child: Icon(Icons.chevron_left, color: _muted, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Save button
        Expanded(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF14CACD), Color(0xFF8D7DFF)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x3314CACD), blurRadius: 24, offset: Offset(0, 8)),
                BoxShadow(color: Color(0x288D7DFF), blurRadius: 10, offset: Offset(0, 3)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onSaveContinue,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Save & Continue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.15,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Skip Row ────────────────────────────────────────────────────
class _SkipRow extends StatelessWidget {
  final VoidCallback onSkip;

  const _SkipRow({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: GestureDetector(
          onTap: onSkip,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _cardBorder, width: 1),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 1),
            child: const Text(
              'Skip for now — set up later in Settings',
              style: TextStyle(
                fontSize: 12.5,
                color: _muted,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Progress Dots ───────────────────────────────────────────────
class _ProgressDots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // done dot
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0x608D7DFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          // done dot
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0x608D7DFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          // active dot (pill)
          Container(
            width: 22,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [_accent2, _accent4],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x408D7DFF), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home Indicator ──────────────────────────────────────────────
class _HomeIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Center(
        child: Container(
          width: 134,
          height: 5,
          decoration: BoxDecoration(
            color: _cardBorder,
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }
}

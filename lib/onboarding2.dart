import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:myapp/app_routes.dart';
import 'package:myapp/profile.dart';
import 'package:myapp/services/appwrite_service.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Screen2(),
  ));
}

class Screen2 extends StatefulWidget {
  const Screen2({super.key});
  @override
  State<Screen2> createState() => _Screen2State();
}

class _Screen2State extends State<Screen2> with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;

  final Set<String> selected = {'Casual', 'Minimalist'};

  final List<Map<String, String>> styles = [
    {'label': 'Clean Minimal', 'img': 'assets/styles/clean_minimal.png'},
    {'label': 'Soft Elegant',  'img': 'assets/styles/soft_elegant.png'},
    {'label': 'Street Cool',   'img': 'assets/styles/street_cool.png'},
    {'label': 'Boho Artisanal','img': 'assets/styles/boho_artisinal.png'},
    {'label': 'Party Glam',    'img': 'assets/styles/party_galm.png'},
    {'label': 'Formal Chic',   'img': 'assets/styles/formal_chic.png'},
  ];

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void toggleCard(String key) {
    setState(() {
      if (selected.contains(key)) {
        selected.remove(key);
      } else {
        selected.add(key);
      }
    });
  }

  bool get _isValidSelection =>
      selected.isNotEmpty;

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _staggered(Widget child,
      {required double start, required double end}) {
    final anim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(start, end, curve: const Cubic(0.22, 1.0, 0.36, 1.0)),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position:
        Tween<Offset>(begin: const Offset(0, 0.055), end: Offset.zero)
            .animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF3FF),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _BgPainter())),
          Positioned.fill(
            child:
            IgnorePointer(child: CustomPaint(painter: _GrainPainter())),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _staggered(_Header(pulseCtrl: _pulseCtrl),
                            start: 0.00, end: 0.58),
                        _staggered(_TabBarWidget(),
                            start: 0.08, end: 0.66),
                        const SizedBox(height: 20),
                        _staggered(
                          const Text(
                            'Choose styles that match your vibe ✨',
                            style: TextStyle(
                              color: Color(0xFF66708A),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          start: 0.14, end: 0.72,
                        ),
                        const SizedBox(height: 4),
                        _staggered(
                          const Text(
                            'Tap to select multiple',
                            style: TextStyle(
                              color: Color(0x99667080),
                              fontSize: 10.5,
                            ),
                          ),
                          start: 0.18, end: 0.76,
                        ),
                        const SizedBox(height: 20),
                        _staggered(
                          _StyleGrid(
                            styles: styles,
                            selected: selected,
                            hasSelection: selected.isNotEmpty,
                            onToggle: toggleCard,
                          ),
                          start: 0.23,
                          end: 0.81,
                        ),
                        const SizedBox(height: 28),
                        _staggered(_CtaSection(selected: selected),
                            start: 0.37, end: 0.95),
                        const SizedBox(height: 22),
                        _staggered(const _ProgressRow(),
                            start: 0.44, end: 1.00),
                      ],
                    ),
                  ),
                ),
                const _HomeIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint();
    for (int i = 0; i < 6000; i++) {
      paint.color = rng.nextBool()
          ? const Color(0x06FFFFFF)
          : const Color(0x07000000);
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width,
            rng.nextDouble() * size.height),
        0.55,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    void r(Offset c, double rx, double ry, Color color) {
      final rect =
      Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    r(Offset(w * .5, h * .32), w * .46, h * .30, const Color(0x0A1A1D26));
    r(Offset(w * -.14, h * -.08), w * .90, h * .68,
        const Color(0x206B91FF));
    r(Offset(w * 1.14, h * .32), w * .62, h * .52,
        const Color(0x188D7DFF));
    r(Offset(w * 1.18, h * 1.12), w * .82, h * .68,
        const Color(0x1204D7C8));
    r(Offset(w * .5, h * .92), w * .72, h * .52, const Color(0x10FF8EC7));
    r(Offset(w * -.16, h * .72), w * .64, h * .74,
        const Color(0x40EEF3FF));
    r(Offset(w * .04, h * 1.0), w * .52, h * .46, const Color(0x0F6B91FF));
    r(Offset(w * 1.02, h * .02), w * .44, h * .36,
        const Color(0x0A04D7C8));
    r(Offset(w * .90, h * .58), w * .40, h * .34, const Color(0x08FFD86E));
    r(Offset(w * .5, h * 0), w * .50, h * .30, const Color(0x148D7DFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _Header({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.fromLTRB(9, 5, 13, 5),
            decoration: BoxDecoration(
              color: const Color(0x1F8D7DFF),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color(0x388D7DFF)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1F6B91FF),
                    blurRadius: 32,
                    offset: Offset(0, 8)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (context, child) {
                  final t = pulseCtrl.value;
                  return Opacity(
                    opacity: 1.0 - t * 0.5,
                    child: Transform.scale(
                      scale: 1.0 - t * 0.25,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B91FF),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(
                                  107, 145, 255, 0.55 - t * 0.40),
                              blurRadius: 8.0 - t * 5.0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 7),
              const Text('AHVI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B91FF),
                    letterSpacing: 1.32,
                  )),
            ]),
          ),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w400,
                color: Color(0xFF1A1D26),
                letterSpacing: -0.936,
                height: 1.06,
              ),
              children: [
                TextSpan(text: 'Your '),
                TextSpan(
                  text: 'Style',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFF6B91FF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tell us about your style preferences.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w300,
              color: Color(0xFF66708A),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab Bar (decorative)
// ─────────────────────────────────────────────────────────────

class _TabBarWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xA8FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E9F7)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A6B91FF),
              blurRadius: 32,
              offset: Offset(0, 8)),
        ],
      ),
      child: Stack(children: [
        Positioned(
          top: 0,
          left: (MediaQuery.of(context).size.width - 48 - 8) / 3 + 4,
          child: Container(
            width: (MediaQuery.of(context).size.width - 48 - 8) / 3,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6B91FF), Color(0xFF8D7DFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x4D6B91FF),
                    blurRadius: 18,
                    offset: Offset(0, 4)),
                BoxShadow(
                    color: Color(0x2E6B91FF),
                    blurRadius: 6,
                    offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
        Row(children: [
          _Tab(label: 'Basics', isActive: false),
          _Tab(label: 'Style', isActive: true),
          _Tab(label: 'Try-On', isActive: false),
        ]),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isActive;
  const _Tab({required this.label, required this.isActive});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
              isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive
                  ? const Color(0xFFF5F7FF)
                  : const Color(0xFF66708A),
            )),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// Style Grid
// ─────────────────────────────────────────────────────────────

class _StyleGrid extends StatelessWidget {
  final List<Map<String, String>> styles;
  final Set<String> selected;
  final bool hasSelection;
  final void Function(String) onToggle;

  const _StyleGrid({
    required this.styles,
    required this.selected,
    required this.hasSelection,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 3 / 4,
      ),
      itemCount: styles.length,
      itemBuilder: (context, i) {
        final s = styles[i];
        final label = s['label']!;
        final isSel = selected.contains(label);
        return _StyleCard(
          name: label,
          sub: '',
          imgUrl: s['img']!,
          isSelected: isSel,
          isDimmed: hasSelection && !isSel,
          onTap: () => onToggle(label),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Style Card
//
// THE FIX — what was wrong in all previous versions:
//
//   _updateScaleAnim() was called on every didUpdateWidget().
//   Each call did:  TweenSequence([...]).animate(CurvedAnimation(parent: _ctrl))
//
//   CurvedAnimation(parent: _ctrl) registers a listener on _ctrl.
//   The OLD CurvedAnimation is never disposed → its listener stays attached.
//   After 2 taps: 2 listeners. After 3: 3. Flutter asserts on the stale
//   listener when the controller tries to notify all of them.
//
// THE CORRECT PATTERN:
//   Use animateTo() directly on the controller with an inline curve argument.
//   animateTo() creates NO persistent CurvedAnimation object — zero leaks.
//   Read controller.value in AnimatedBuilder and map it to scale manually.
// ─────────────────────────────────────────────────────────────

class _StyleCard extends StatelessWidget {
  final String name;
  final String sub;
  final String imgUrl;
  final bool isSelected;
  final bool isDimmed;
  final VoidCallback onTap;

  const _StyleCard({
    required this.name,
    required this.sub,
    required this.imgUrl,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isDimmed ? 0.46 : 1.0,
      duration: const Duration(milliseconds: 220),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xBF6B91FF)
                  : const Color(0xFFE5E9F7),
              width: 2,
            ),
            boxShadow: isSelected
                ? const [
              BoxShadow(
                  color: Color(0x476B91FF),
                  blurRadius: 28,
                  offset: Offset(0, 8)),
            ]
                : [],
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(fit: StackFit.expand, children: [
            // Photo
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(isSelected ? 0.08 : 0.22),
                  BlendMode.darken),
              child: Image.asset(
                imgUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) =>
                    Container(color: const Color(0xFFDFE7FB)),
              ),
            ),
            // Bottom gradient overlay
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.40, 0.65, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color(0x701A1D26),
                      Color(0xD81A1D26),
                    ],
                  ),
                ),
              ),
            ),
            // Gradient checkmark badge (top-right)
            if (isSelected)
              Positioned(
                top: 9, right: 9,
                child: Container(
                  width: 22, height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF6B91FF), Color(0xFF8D7DFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x666B91FF),
                          blurRadius: 10,
                          offset: Offset(0, 3)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text('✓',
                      style: TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            // Bottom label pill
            Positioned(
              bottom: 10, left: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF5F7FF),
                          letterSpacing: 0.1,
                        )),
                    const SizedBox(height: 1),
                    Text(sub,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xB8E6EBFF),
                          fontWeight: FontWeight.w400,
                        )),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────
// CTA Section
//
// THE FIX:
//   Previous versions stored TweenSequence animations as fields and
//   called .animate(CurvedAnimation(parent: ctrl)) multiple times,
//   leaking listeners on every tap.
//
//   Now: controller value is a plain double 0..1.
//   We lerp scale from it directly in AnimatedBuilder.
//   animateTo() with an inline curve creates zero persistent objects.
// ─────────────────────────────────────────────────────────────

class _CtaSection extends StatefulWidget {
  final Set<String> selected;
  const _CtaSection({required this.selected});
  @override
  State<_CtaSection> createState() => _CtaSectionState();
}

class _CtaSectionState extends State<_CtaSection>
    with TickerProviderStateMixin {
  late final AnimationController _backCtrl;
  late final AnimationController _continueCtrl;

  bool _backBusy = false;
  bool _continueBusy = false;

  bool get _isValidSelection =>
      widget.selected.isNotEmpty;

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    // value=0 → rest; value=1 → fully squeezed
    _backCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
        value: 0);
    _continueCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
        value: 0);
  }

  @override
  void dispose() {
    _backCtrl.dispose();
    _continueCtrl.dispose();
    super.dispose();
  }

  Future<void> _squeezeBack() async {
    if (_backBusy) return;
    _backBusy = true;
    // squeeze in
    await _backCtrl.animateTo(1.0,
        duration: const Duration(milliseconds: 100), curve: Curves.easeIn);
    if (!mounted) { _backBusy = false; return; }
    // spring back
    await _backCtrl.animateTo(0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.elasticOut);
    _backBusy = false;
  }

  Future<void> _squeezeContinue() async {
    if (_continueBusy) return;
    _continueBusy = true;
    await _continueCtrl.animateTo(1.0,
        duration: const Duration(milliseconds: 100), curve: Curves.easeIn);
    if (!mounted) { _continueBusy = false; return; }
    await _continueCtrl.animateTo(0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.elasticOut);
    _continueBusy = false;
  }

  void _onBackTap() {
    _squeezeBack();
    Future.delayed(const Duration(milliseconds: 180),
            () { if (mounted) Navigator.of(context).maybePop(); });
  }

  void _onContinueTap() {
    if (!_isValidSelection) {
      _showValidationError('Please select at least one style to continue.');
      return;
    }
    _squeezeContinue();
    Future.delayed(const Duration(milliseconds: 180), () async {
      if (mounted) {
        context.read<ProfileController>().updateStyles(widget.selected);
        try {
          await context.read<AppwriteService>().updateCurrentUserProfileFields({
            'stylePreferences': widget.selected.toList(),
            'onboarding2': true,
          });
        } catch (e) {
          if (!mounted) return;
          _showValidationError('Could not save style preferences. Please try again.');
          return;
        }
        if (!mounted) return;
        Navigator.of(context).pushNamed(AppRoutes.onboarding3);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      // ── Back button ────────────────────────────────────
      GestureDetector(
        onTap: _onBackTap,
        child: AnimatedBuilder(
          animation: _backCtrl,
          builder: (_, child) {
            final v = _backCtrl.value;
            return Transform.translate(
              offset: Offset(-v * 3.0, 0),
              child: Transform.scale(
                scale: 1.0 - v * 0.09, // 1.0 → 0.91
                child: child,
              ),
            );
          },
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xA8FFFFFF),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE5E9F7)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 26,
                    offset: Offset(0, 8)),
                BoxShadow(
                    color: Color(0x40FFFFFF),
                    blurRadius: 0,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Center(
              child: CustomPaint(
                  size: const Size(18, 18), painter: _BackArrowP()),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),

      // ── Continue button ────────────────────────────────
      Expanded(
        child: GestureDetector(
          onTap: _onContinueTap,
          child: AnimatedBuilder(
            animation: _continueCtrl,
            builder: (_, child) {
              return Transform.scale(
                scale: 1.0 - _continueCtrl.value * 0.028, // 1.0 → 0.972
                child: child,
              );
            },
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6B91FF), Color(0xFF8D7DFF)],
                ),
                borderRadius: BorderRadius.circular(17),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x616B91FF),
                      blurRadius: 34,
                      offset: Offset(0, 10)),
                  BoxShadow(
                      color: Color(0x336B91FF),
                      blurRadius: 8,
                      offset: Offset(0, 2)),
                  BoxShadow(
                      color: Color(0x29FFFFFF),
                      blurRadius: 0,
                      offset: Offset(0, 1)),
                ],
              ),
              child: Stack(children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      gradient: const LinearGradient(
                        begin: Alignment(-0.8, -1.0),
                        end: Alignment(0.2, 0.5),
                        colors: [Color(0x1FFFFFFF), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10131B),
                            letterSpacing: 0.3,
                          )),
                      const SizedBox(width: 8),
                      CustomPaint(
                          size: const Size(16, 16), painter: _ArrowP()),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _BackArrowP extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(s.width * .611, s.height * .222)
        ..lineTo(s.width * .333, s.height * .5)
        ..lineTo(s.width * .611, s.height * .778),
      Paint()
        ..color = const Color(0xFF66708A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ArrowP extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = const Color(0xCC10131B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(s.width * .25, s.height * .5),
        Offset(s.width * .75, s.height * .5), p);
    canvas.drawPath(
      Path()
        ..moveTo(s.width * .5625, s.height * .3125)
        ..lineTo(s.width * .75, s.height * .5)
        ..lineTo(s.width * .5625, s.height * .6875),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─────────────────────────────────────────────────────────────
// Progress Row
// ─────────────────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  const _ProgressRow();
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
              color: const Color(0x806B91FF),
              borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Container(
        width: 24,
        height: 6,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF6B91FF), Color(0xFF8D7DFF)]),
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [
            BoxShadow(
                color: Color(0x666B91FF),
                blurRadius: 10,
                offset: Offset(0, 2))
          ],
        ),
      ),
      const SizedBox(width: 8),
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
              color: const Color(0x386B91FF),
              borderRadius: BorderRadius.circular(3))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// Home Indicator
// ─────────────────────────────────────────────────────────────

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 134,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0x2EF5F7FF),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }
}

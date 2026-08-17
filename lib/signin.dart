import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:appwrite/appwrite.dart';
import 'package:myapp/app_routes.dart';
import 'package:provider/provider.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/notification_service.dart';
import 'package:myapp/profile.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:flutter/services.dart';
import 'package:myapp/widgets/country_dropdown.dart';

void main() => runApp(const AhviApp());

class AhviApp extends StatelessWidget {
  const AhviApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SignInScreen(),
    );
  }
}

/// Source-of-truth onboarding gate.
///
/// Routes the user to onboarding1 ONLY if their Appwrite profile is
/// incomplete (missing gender or onboarding1/2/3 flags). Otherwise sends
/// them straight to the main shell. Relying on SharedPreferences alone is
/// wrong because a returning user on a fresh install / new device has no
/// local cache, even though Appwrite already has onboardingComplete=true.
Future<void> _routeAfterSignIn(BuildContext context) async {
  if (!context.mounted) return;
  final appwrite = Provider.of<AppwriteService>(context, listen: false);

  bool onboardingDone = false;
  try {
    onboardingDone = await appwrite.isCurrentUserOnboardingComplete();
  } catch (e) {
    debugPrint('AHVI_SIGNIN_GATE failed to read onboarding state: $e');
    onboardingDone = false;
  }

  debugPrint('AHVI_SIGNIN_GATE onboardingDone=$onboardingDone');

  if (!context.mounted) return;
  if (onboardingDone) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
  } else {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.onboarding1, (route) => false);
  }
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  void _goToMain(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
  }

  void _goToEmailAuth(BuildContext context) {
    Navigator.of(context).pushNamed(AppRoutes.emailAuth);
  }

  // --- NEW: Real Google Login Flow ---
  Future<void> _handleGoogleLogin(BuildContext context) async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);

    // Attempt the login
    final success = await appwrite.loginWithGoogle();

    // If successful, check if first-time user and route accordingly
    if (success && context.mounted) {
      // Load real name & email into ProfileController so profile never shows "New User"
      try {
        final account = await appwrite.account.get();
        if (context.mounted) {
          context.read<ProfileController>().loadFromAccount(
            name: account.name,
            email: account.email,
          );
        }
      } catch (_) {}

      try {
        await AhviNotificationService.instance.registerForCurrentUser(appwrite);
      } catch (_) {}

      if (!context.mounted) return;
      await _routeAfterSignIn(context);
    } else if (context.mounted) {
      // If it fails or the user cancels, show an error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Sign-In failed or was canceled.')),
      );
    }
  }

  // --- Real Apple Login Flow ---
  Future<void> _handleAppleLogin(BuildContext context) async {
    final appwrite = Provider.of<AppwriteService>(context, listen: false);
    final success = await appwrite.loginWithApple();

    if (success && context.mounted) {
      // Load real name & email into ProfileController so profile never shows "New User"
      try {
        final account = await appwrite.account.get();
        if (context.mounted) {
          context.read<ProfileController>().loadFromAccount(
            name: account.name,
            email: account.email,
          );
        }
      } catch (_) {}

      try {
        await AhviNotificationService.instance.registerForCurrentUser(appwrite);
      } catch (_) {}

      if (!context.mounted) return;
      await _routeAfterSignIn(context);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Apple Sign-In failed or was canceled.'),
          backgroundColor: const Color(0xFFBF3B3B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AnimatedAppBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: _SignUpPage(
                  onGoogleTap: () => _handleGoogleLogin(context),
                  onAppleTap: () => _handleAppleLogin(context),
                  onEmailTap: () => _goToEmailAuth(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMAIL OTP LOGIN SCREEN - SIMPLIFIED (OTP ONLY, NO PASSWORD)
// ============================================================================
class EmailOTPLoginScreen extends StatefulWidget {
  const EmailOTPLoginScreen({super.key});

  @override
  State<EmailOTPLoginScreen> createState() => _EmailOTPLoginScreenState();
}

class _EmailOTPLoginScreenState extends State<EmailOTPLoginScreen> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _otpCtrl;
  bool _isLoading = false;
  bool _otpSent = false;
  bool _canResend = false;
  bool _otpExpired = false;
  int _otpExpirationCountdown = 60;
  int _resendCountdown = 60;
  String _currentEmail = '';
  Timer? _otpExpirationTimer;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
    _otpCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _otpExpirationTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return regex.hasMatch(trimmed);
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFBF3B3B)
            : const Color(0xFF2E7D52),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _startOtpExpirationTimer() {
    _otpExpired = false;
    _otpExpirationCountdown = 60;

    _otpExpirationTimer?.cancel();
    _otpExpirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _otpExpirationCountdown--;
          if (_otpExpirationCountdown <= 0) {
            _otpExpired = true;
            timer.cancel();
            _showSnackBar(
              'OTP expired. Please request a new one.',
              isError: true,
            );
          }
        });
      }
    });
  }

  void _startResendTimer() {
    _canResend = false;
    _resendCountdown = 60;

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _resendCountdown--;
          if (_resendCountdown <= 0) {
            _canResend = true;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _onSendOTP() async {
    final email = _emailCtrl.text.trim();

    if (!_isValidEmail(email)) {
      _showSnackBar('Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);

      // Send OTP to email
      await appwrite.sendOTP(email);

      if (!mounted) return;

      _currentEmail = email;
      setState(() {
        _otpSent = true;
        _isLoading = false;
      });
      _showSnackBar(
        'OTP sent to your email. Expires in 60 seconds.',
        isError: false,
      );
      _startOtpExpirationTimer();
      _startResendTimer();
    } on AppwriteException catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to send OTP: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Something went wrong. Please try again.');
      debugPrint('Send OTP error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onVerifyOTP() async {
    final otp = _otpCtrl.text.trim();

    if (_otpExpired) {
      _showSnackBar('OTP has expired. Please request a new one.');
      return;
    }

    if (otp.isEmpty) {
      _showSnackBar('Please enter the OTP.');
      return;
    }
    if (otp.length != 6) {
      _showSnackBar('OTP must be 6 digits.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);

      // Verify OTP
      final success = await appwrite.verifyOTP(_currentEmail, otp);

      if (!mounted) return;

      if (success) {
        _otpExpirationTimer?.cancel();
        _resendTimer?.cancel();

        // Load user account
        try {
          final account = await appwrite.account.get();
          if (mounted) {
            context.read<ProfileController>().loadFromAccount(
              name: account.name,
              email: account.email,
            );
          }
        } catch (_) {}

        try {
          await AhviNotificationService.instance.registerForCurrentUser(
            appwrite,
          );
        } catch (_) {}

        if (!mounted) return;
        _showSnackBar('Verified successfully!', isError: false);

        // Route after sign-in
        await _routeAfterSignIn(context);
      } else {
        _showSnackBar('Invalid OTP. Please try again.');
      }
    } on AppwriteException catch (e) {
      if (!mounted) return;
      _showSnackBar('Verification failed: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Something went wrong. Please try again.');
      debugPrint('OTP verification error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onResendOTP() async {
    if (!_canResend) return;

    setState(() => _isLoading = true);
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      await appwrite.sendOTP(_currentEmail);

      if (!mounted) return;
      _otpCtrl.clear();
      setState(() => _otpExpired = false);
      _showSnackBar('OTP resent to your email.', isError: false);
      _startOtpExpirationTimer();
      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to resend OTP. Please try again.');
      debugPrint('Resend OTP error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetToEmailInput() {
    _otpExpirationTimer?.cancel();
    _resendTimer?.cancel();

    setState(() {
      _otpSent = false;
      _otpExpired = false;
      _emailCtrl.clear();
      _otpCtrl.clear();
      _currentEmail = '';
      _canResend = false;
      _otpExpirationCountdown = 60;
      _resendCountdown = 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AnimatedAppBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: _AuthCard(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Back Button
                      GestureDetector(
                        onTap: () {
                          if (_otpSent) {
                            _resetToEmailInput();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCDD5EF)),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Color(0xFF1A1D26),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // AHVI wordmark
                      const Center(
                        child: AhviHomeText(fontSize: 36, letterSpacing: 1),
                      ),
                      const SizedBox(height: 18),

                      if (!_otpSent) ...[
                        // ===== EMAIL INPUT SCREEN =====
                        const _AuthHeading(
                          title: 'Welcome back.',
                          subtitle: 'Sign in with your email',
                        ),
                        const SizedBox(height: 28),
                        _InputField(
                          controller: _emailCtrl,
                          hint: 'Email address',
                          icon: Icons.alternate_email,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_isLoading,
                        ),
                        const SizedBox(height: 24),
                        _PrimaryButton(
                          label: _isLoading ? 'Sending OTP...' : 'Sign In',
                          onTap: _isLoading ? null : _onSendOTP,
                          isLoading: _isLoading,
                        ),
                      ] else ...[
                        // ===== OTP VERIFICATION SCREEN =====
                        _AuthHeading(
                          title: 'Verify your email',
                          subtitle: 'Enter the code sent to $_currentEmail',
                        ),
                        const SizedBox(height: 24),

                        _InputField(
                          controller: _otpCtrl,
                          hint: 'Enter 6-digit code',
                          icon: Icons.password,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          enabled: !_isLoading && !_otpExpired,
                        ),
                        const SizedBox(height: 24),
                        _PrimaryButton(
                          label: _isLoading ? 'Verifying...' : 'Sign In',
                          onTap: (_isLoading || _otpExpired)
                              ? null
                              : _onVerifyOTP,
                          isLoading: _isLoading,
                        ),
                        const SizedBox(height: 16),

                        // Resend OTP Section
                        Center(
                          child: GestureDetector(
                            onTap: (_canResend && !_isLoading)
                                ? _onResendOTP
                                : null,
                            child: Text(
                              _otpExpired
                                  ? 'Request new OTP'
                                  : _canResend
                                  ? 'Didn\'t receive code? Resend'
                                  : 'Resend code in $_resendCountdown seconds',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _canResend
                                    ? const Color(0xFF4B6FE0)
                                    : const Color(0xFF66708A),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _AuthCard({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(28, 44, 28, 36),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F6FC)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE6EAF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AuthHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _AuthHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1D26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF66708A),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// ORIGINAL SIGN UP PAGE (UPDATED - ONLY EMAIL OTP)
// ============================================================================
class _SignUpPage extends StatefulWidget {
  final VoidCallback onGoogleTap;
  final VoidCallback onAppleTap;
  final VoidCallback onEmailTap;

  const _SignUpPage({
    required this.onGoogleTap,
    required this.onAppleTap,
    required this.onEmailTap,
  });

  @override
  State<_SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<_SignUpPage> {
  final TextEditingController _phoneController = TextEditingController();
  String _selectedCountryCode = '+91';
  String _selectedCountryFlag = '🇮🇳';
  String _selectedCountryName = 'India';
  int _selectedCountryMaxDigits = 10;
  bool _isPhoneOtpSending = false;

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
      builder: (_) => CountryDropdownOverlay(
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
            _phoneController.clear();
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

  @override
  void dispose() {
    _removeCountryDropdown();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handlePhoneSignIn() async {
    if (_isPhoneOtpSending) return;

    final phone = _phoneController.text.trim();

    if (phone.length != _selectedCountryMaxDigits) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number.')),
      );
      return;
    }

    setState(() => _isPhoneOtpSending = true);

    try {
      final appwriteService = Provider.of<AppwriteService>(
        context,
        listen: false,
      );

      await appwriteService.sendPhoneOTP('$_selectedCountryCode$phone');

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              _PhoneOtpPage(phoneNumber: '$_selectedCountryCode$phone'),
        ),
      );

      debugPrint('✅ Phone OTP request completed');
    } catch (e) {
      debugPrint('❌ Phone sign in error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to send OTP. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPhoneOtpSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AhviHomeText(fontSize: 36, letterSpacing: 1),
          const SizedBox(height: 22),
          const _SectionTitle(
            line1: 'Your Personal Assistant',
            line2: 'Awaits.',
            italic: true,
          ),
          const SizedBox(height: 12),
          const _SectionSub(text: 'Sign in or create your account'),
          const SizedBox(height: 32),

          CompositedTransformTarget(
            link: _countryLayerLink,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD9DDEA), width: 1.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 18),

                  GestureDetector(
                    onTap: _showCountryPicker,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Text(
                          _selectedCountryFlag,
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFFB8BDCD),
                          size: 20,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    _selectedCountryCode,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1D26),
                    ),
                  ),

                  const SizedBox(width: 16),

                  Container(
                    width: 1,
                    height: 32,
                    color: const Color(0xFFD9DDEA),
                  ),

                  const SizedBox(width: 16),

                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          _selectedCountryMaxDigits,
                        ),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Phone number',
                        counterText: '',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF9BA3B7),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9B5DE5), Color(0xFF5B6FE8)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7B61D9).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _isPhoneOtpSending ? null : _handlePhoneSignIn,
                child: Center(
                  child: Text(
                    _isPhoneOtpSending ? 'Sending OTP...' : 'Sign in',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: Container(height: 1, color: const Color(0xFFD9DDEA)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or continue with',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF66708A),
                  ),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: const Color(0xFFD9DDEA)),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _SocialButton(
            icon: _GoogleIcon(),
            label: 'Continue with Google',
            onTap: widget.onGoogleTap,
          ),
          const SizedBox(height: 12),
          _SocialButton(label: 'Continue with Apple', onTap: widget.onAppleTap),
          const _Divider(),
          GestureDetector(
            onTap: widget.onEmailTap,
            behavior: HitTestBehavior.opaque,
            child: const _LinkText(prefix: 'Sign up with ', highlight: 'Email'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// REUSABLE COMPONENTS
// ============================================================================

class _InputField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final int? maxLength;
  final bool enabled;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.enabled = true,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _focused ? const Color(0xFF6C72E0) : const Color(0xFFDFE3F2),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(widget.icon, size: 18, color: const Color(0xFF9AA5C2)),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.controller,
                keyboardType: widget.keyboardType,
                maxLength: widget.maxLength,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFB0BCD4),
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
                style: const TextStyle(fontSize: 15, color: Color(0xFF1A1D26)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _PrimaryButton({
    required this.label,
    this.onTap,
    this.isLoading = false,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null && !widget.isLoading;

    return GestureDetector(
      onTap: isEnabled ? widget.onTap : null,
      onTapDown: isEnabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: isEnabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: isEnabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 54,
        transform: _pressed
            ? (Matrix4.identity()..scale(0.98))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          gradient: isEnabled
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF9B6BE0), Color(0xFF6C72E0)],
                )
              : null,
          color: isEnabled ? null : const Color(0xFFCDD5EF),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isEnabled
              ? [
                  const BoxShadow(
                    color: Color(0x4D6C72E0),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: widget.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5F7FF)),
                  strokeWidth: 2,
                ),
              )
            : Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF),
                  letterSpacing: -0.01 * 16,
                ),
              ),
      ),
    );
  }
}

class _SocialButton extends StatefulWidget {
  final Widget? icon;
  final String label;
  final VoidCallback onTap;
  const _SocialButton({this.icon, required this.label, required this.onTap});
  @override
  State<_SocialButton> createState() => _SocialButtonState();
}

class _SocialButtonState extends State<_SocialButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final transform = _pressed
        ? (Matrix4.identity()..scale(0.98))
        : _hovered
        ? (Matrix4.identity()..translate(0.0, -1.0))
        : Matrix4.identity();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: transform,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFE8EDFC) : const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCDD5EF)),
            boxShadow: _hovered
                ? [
                    const BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(child: widget.icon!),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1A1D26),
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

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFEA4335),
          Color(0xFFFBBC05),
          Color(0xFF34A853),
          Color(0xFF4285F4),
        ],
      ).createShader(bounds),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x40A0AABF),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF66708A),
                letterSpacing: 0.04 * 12,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x40A0AABF),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  final String prefix;
  final String highlight;
  const _LinkText({required this.prefix, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF66708A),
        ),
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: highlight,
            style: const TextStyle(
              color: Color(0xFF4B6FE0),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String line1;
  final String? line2;
  final bool italic;
  const _SectionTitle({required this.line1, this.line2, this.italic = false});

  @override
  Widget build(BuildContext context) {
    final titleStyle = italic
        ? GoogleFonts.cormorantGaramond(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
            color: const Color(0xFF1A1D26),
            letterSpacing: -0.02 * 30,
            height: 1.25,
          )
        : const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 30,
            fontWeight: FontWeight.w400,
            color: Color(0xFF1A1D26),
            letterSpacing: -0.02 * 30,
            height: 1.25,
          );

    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: titleStyle,
          children: [
            TextSpan(text: line1),
            if (line2 != null && line2!.isNotEmpty)
              TextSpan(
                text: '\n$line2',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionSub extends StatelessWidget {
  final String text;
  const _SectionSub({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFF66708A),
      ),
    );
  }
}

class _AnimatedAppBackground extends StatelessWidget {
  const _AnimatedAppBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFBFF),
      // Add your animated background here
    );
  }
}

class _PhoneOtpPage extends StatefulWidget {
  final String phoneNumber;

  const _PhoneOtpPage({required this.phoneNumber});

  @override
  State<_PhoneOtpPage> createState() => _PhoneOtpPageState();
}

class _PhoneOtpPageState extends State<_PhoneOtpPage> {
  final TextEditingController _otpController = TextEditingController();

  bool _isLoading = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendCountdown = 60;

    _resendTimer?.cancel();

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _resendCountdown--;

        if (_resendCountdown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _onResendOTP() async {
    if (!_canResend || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);

      await appwrite.sendPhoneOTP(widget.phoneNumber);

      if (!mounted) return;

      _otpController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent to your phone.')),
      );

      _startResendTimer();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to resend OTP. Please try again.'),
        ),
      );

      debugPrint('Resend phone OTP error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (_isLoading) return;

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔐 Verifying phone OTP...');

      final appwriteService = Provider.of<AppwriteService>(
        context,
        listen: false,
      );

      final success = await appwriteService.verifyPhoneOTP(
        widget.phoneNumber,
        otp,
      );

      if (!mounted) return;

      if (success) {
        debugPrint('✅ Phone OTP verified successfully');

        final account = await appwriteService.account.get();

        if (mounted) {
          context.read<ProfileController>().loadFromAccount(
            name: account.name,
            email: account.email,
          );
        }

        try {
          await AhviNotificationService.instance.registerForCurrentUser(
            appwriteService,
          );
        } catch (_) {}

        if (!mounted) return;

        await _routeAfterSignIn(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid or expired OTP.')),
        );
      }
    } catch (e) {
      if (!mounted) return;

      debugPrint('Phone OTP verification failed');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to verify OTP. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _AnimatedAppBackground(),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: _AuthCard(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFCDD5EF)),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Color(0xFF1A1D26),
                            size: 20,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Center(
                        child: AhviHomeText(fontSize: 36, letterSpacing: 1),
                      ),

                      const SizedBox(height: 18),

                      _AuthHeading(
                        title: 'Verify your phone',
                        subtitle:
                            'Enter the code sent to ${widget.phoneNumber}',
                      ),

                      const SizedBox(height: 24),

                      _InputField(
                        controller: _otpController,
                        hint: 'Enter 6-digit code',
                        icon: Icons.password,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        enabled: !_isLoading,
                      ),

                      const SizedBox(height: 24),

                      _PrimaryButton(
                        label: _isLoading ? 'Verifying...' : 'Sign In',
                        onTap: _isLoading ? null : _verifyOtp,
                        isLoading: _isLoading,
                      ),

                      const SizedBox(height: 16),

                      Center(
                        child: GestureDetector(
                          onTap: (_canResend && !_isLoading)
                              ? _onResendOTP
                              : null,
                          child: Text(
                            _canResend
                                ? 'Didn\'t receive code? Resend'
                                : 'Resend code in $_resendCountdown seconds',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _canResend
                                  ? const Color(0xFF4B6FE0)
                                  : const Color(0xFF66708A),
                            ),
                          ),
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
  }
}

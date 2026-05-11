import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:appwrite/appwrite.dart';
import 'package:myapp/app_routes.dart';
import 'package:provider/provider.dart';
import 'package:myapp/services/appwrite_service.dart';
import 'package:myapp/services/notification_service.dart';
import 'package:myapp/profile.dart';

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
      final isFirstTime = !(await appwrite.isCurrentUserOnboardingComplete());

      if (isFirstTime) {
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.onboarding1, (route) => false);
        }
      } else {
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
        }
      }
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
      final isFirstTime = !(await appwrite.isCurrentUserOnboardingComplete());

      if (isFirstTime) {
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.onboarding1, (route) => false);
        }
      } else {
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
        }
      }
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

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
    _passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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

  Future<void> _onSignIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (!_isValidEmail(email)) {
      _showSnackBar('Please enter a valid email address.');
      return;
    }
    if (password.trim().isEmpty) {
      _showSnackBar('Please enter your password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      final session = await appwrite.loginEmailPassword(email, password);
      if (!mounted) return;
      if (session != null) {
        // Load real name & email into ProfileController so profile never shows "New User"
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
        // Check if first-time user → show onboarding, else go to main
        final isFirstTime = !(await appwrite.isCurrentUserOnboardingComplete());
        if (!mounted) return;
        if (isFirstTime) {
          if (!mounted) return;
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.onboarding1, (route) => false);
        } else {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
        }
      }
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        _showSnackBar('Invalid email or password. Please try again.');
      } else {
        _showSnackBar('Something went wrong. Please try again.');
      }
    } catch (_) {
      _showSnackBar('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      _showSnackBar(
        'Enter your email address above first, then tap Forgot password.',
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final appwrite = Provider.of<AppwriteService>(context, listen: false);
      await appwrite.sendPasswordReset(email);
      if (!mounted) return;
      _showSnackBar('Password reset link sent to $email', isError: false);
    } catch (_) {
      _showSnackBar('Failed to send reset email. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onCreateAccount() {
    Navigator.of(context).pushNamed(AppRoutes.onboarding1);
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
                child: _SignInPage(
                  emailController: _emailCtrl,
                  passwordController: _passwordCtrl,
                  onCreateAccount: _onCreateAccount,
                  onSignIn: _onSignIn,
                  onForgotPassword: _onForgotPassword,
                  isLoading: _isLoading,
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.55),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF8D7DFF),
                  strokeWidth: 2.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedAppBackground extends StatelessWidget {
  const _AnimatedAppBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFEEF3FF)],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.0, -1.0),
              radius: 0.9,
              colors: [
                const Color(0xFF6B91FF).withOpacity(0.18),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xF5FFFFFF),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE5E9F7), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 48,
              offset: Offset(0, 16),
            ),
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment(-0.6, -1),
                    end: Alignment(0.6, 0.5),
                    colors: [Color(0x18A0B0FF), Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 40, 32, 36),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  final VoidCallback onCta;
  const _IntroPage({required this.onCta});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'AHVI',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1D26),
              letterSpacing: -0.03 * 52,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI PERSONAL STYLIST',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF66708A),
              letterSpacing: 0.08 * 13,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Plan outfits. Organise your wardrobe.\nTry looks virtually.\nPersonalised — just for you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: Color(0xFF66708A),
              height: 1.75,
            ),
          ),
          const SizedBox(height: 32),
          _PrimaryButton(label: 'Get styled →', onTap: onCta),
        ],
      ),
    );
  }
}

class _SignUpPage extends StatelessWidget {
  final VoidCallback onEmailTap;
  final VoidCallback onGoogleTap;
  final VoidCallback onAppleTap;
  const _SignUpPage({
    required this.onEmailTap,
    required this.onGoogleTap,
    required this.onAppleTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: Text(
              'AHVI',
              style: GoogleFonts.anton(
                fontSize: 36,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF1A1D26),
                letterSpacing: 3.2,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _SectionTitle(
            line1: 'Your Personal Assistant Awaits.',
            italic: true,
          ),
          const SizedBox(height: 6),
          const _SectionSub(text: 'Sign in or create your account'),
          const SizedBox(height: 28),
          _SocialButton(
            icon: _GoogleIcon(),
            label: 'Continue with Google',
            onTap: onGoogleTap,
          ),
          const SizedBox(height: 10),
          _SocialButton(
            icon: const Text(
              '',
              style: TextStyle(fontSize: 17, color: Color(0xFF1A1D26)),
            ),
            label: 'Continue with Apple',
            onTap: onAppleTap,
          ),
          const _Divider(),
          GestureDetector(
            onTap: onEmailTap,
            child: const _HoverOpacity(
              child: _LinkText(prefix: 'Sign up with ', highlight: 'Email'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInPage extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;
  final VoidCallback onForgotPassword;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  const _SignInPage({
    required this.onCreateAccount,
    required this.onSignIn,
    required this.onForgotPassword,
    required this.emailController,
    required this.passwordController,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'AHVI',
              style: GoogleFonts.anton(
                fontSize: 36,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF1A1D26),
                letterSpacing: 3.2,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Welcome back.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF66708A),
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(child: _SectionSub(text: 'Sign in with your email')),
          const SizedBox(height: 28),
          _AnimatedInputField(
            icon: '@',
            placeholder: 'Email address',
            obscure: false,
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _AnimatedInputField(
            icon: '*',
            placeholder: 'Password',
            obscure: true,
            controller: passwordController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSignIn(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 20),
              child: _AnimatedForgotPassword(onTap: onForgotPassword),
            ),
          ),
          _PrimaryButton(
            label: isLoading ? 'Signing in…' : 'Sign In',
            onTap: isLoading ? () {} : onSignIn,
          ),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              onTap: onCreateAccount,
              child: const _HoverOpacity(
                child: _LinkText(
                  prefix: 'New here? ',
                  highlight: 'Create New Account',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedForgotPassword extends StatefulWidget {
  final VoidCallback onTap;
  const _AnimatedForgotPassword({required this.onTap});
  @override
  State<_AnimatedForgotPassword> createState() =>
      _AnimatedForgotPasswordState();
}

class _AnimatedForgotPasswordState extends State<_AnimatedForgotPassword> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: _hovered ? const Color(0xFF4B6FE0) : const Color(0xFF66708A),
          ),
          child: const Text('Forgot password?'),
        ),
      ),
    );
  }
}

class _HoverOpacity extends StatefulWidget {
  final Widget child;
  const _HoverOpacity({required this.child});
  @override
  State<_HoverOpacity> createState() => _HoverOpacityState();
}

class _HoverOpacityState extends State<_HoverOpacity> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: _hovered ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: widget.child,
      ),
    );
  }
}

class _AnimatedInputField extends StatefulWidget {
  final String icon;
  final String placeholder;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  const _AnimatedInputField({
    required this.icon,
    required this.placeholder,
    required this.obscure,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });
  @override
  State<_AnimatedInputField> createState() => _AnimatedInputFieldState();
}

class _AnimatedInputFieldState extends State<_AnimatedInputField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: _focused ? const Color(0xFFFFFFFF) : const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? const Color(0xFF6B91FF) : const Color(0xFFD0D8F0),
        ),
        boxShadow: _focused
            ? [
                const BoxShadow(
                  color: Color(0x206B91FF),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
                const BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: widget.obscure,
        onSubmitted: widget.onSubmitted,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF1A1D26),
        ),
        decoration: InputDecoration(
          hintText: widget.placeholder,
          hintStyle: const TextStyle(color: Color(0xFF66708A)),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Text(widget.icon, style: const TextStyle(fontSize: 16)),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});
  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final transform = _pressed
        ? (Matrix4.identity()..scale(0.98))
        : _hovered
        ? (Matrix4.identity()..translate(0.0, -2.0))
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
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFA259FF), Color(0xFF8D7DFF)],
            ),
            boxShadow: _hovered && !_pressed
                ? [
                    const BoxShadow(
                      color: Color(0x6B8D7DFF),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                    const BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : _pressed
                ? [
                    const BoxShadow(
                      color: Color(0x408D7DFF),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x528D7DFF),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF5F7FF),
              letterSpacing: -0.01 * 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatefulWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
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
              SizedBox(
                width: 20,
                height: 20,
                child: Center(child: widget.icon),
              ),
              const SizedBox(width: 10),
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

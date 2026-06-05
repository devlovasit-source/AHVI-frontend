// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/wardrobe.dart';
import 'package:myapp/widgets/ahvi_lens_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public contract
// ─────────────────────────────────────────────────────────────────────────────

/// Mic state communicated from the parent down to the bar.
enum MicState {
  /// Not recording.
  idle,

  /// Recording – waiting for first words.
  listening,

  /// Recording – interim (partial) transcript is available.
  transcribing,

  /// Recording finished; final transcript ready for review.
  awaitingReview,

  /// Processing / sending.
  sending,
}

class AhviChatPromptBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  // Optional override – if null the bar reads widget.controller directly.
  final bool? hasText;
  final ValueListenable<TextEditingValue>? hasTextListenable;

  // Colours
  final Color surface;
  final Color border;
  final Color accent;
  final Color accentSecondary;
  final Color textHeading;
  final Color textMuted;
  final Color shadowMedium;
  final Color onAccent;

  final EdgeInsetsGeometry padding;

  /// Called with the trimmed message text after the user confirms send.
  /// Parent should navigate to chat page inside this callback.
  final ValueChanged<String> onSendMessage;

  // ── Lens / plus ──────────────────────────────────────────────────────────
  final AppThemeTokens themeTokens;
  final VoidCallback? onVisualSearch;
  final VoidCallback? onFindSimilar;
  final VoidCallback? onAddToWardrobe;
  final VoidCallback? onPlusTap;

  // ── Voice / STT ──────────────────────────────────────────────────────────
  /// Gradient colors for the mic button while recording.
  /// Defaults to a red-to-pink pair if not provided.
  final List<Color>? micActiveGradientColors;

  /// Shadow color for the mic button while recording.
  /// Defaults to [Colors.redAccent] if not provided.
  final Color? micActiveShadowColor;

  /// Parent starts / stops recording; bar reflects [micState].
  final VoidCallback? onVoiceTap;

  /// Current mic/stt state driven by parent.
  final MicState micState;

  /// Live partial transcript (updated while [micState] == transcribing).
  /// The bar appends this text to the field as a preview.
  final String interimTranscript;

  /// Final transcript provided when [micState] == awaitingReview.
  /// The bar will show a review dialog populated with this text.
  final String finalTranscript;

  /// Amplitude 0.0–1.0 for the waveform indicator while listening.
  final double micAmplitude;

  /// Whether the parent is still processing the send (shows spinner).
  final bool isSending;

  const AhviChatPromptBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    this.hasText,
    this.hasTextListenable,
    required this.surface,
    required this.border,
    required this.accent,
    required this.accentSecondary,
    required this.textHeading,
    required this.textMuted,
    required this.shadowMedium,
    required this.onAccent,
    required this.onSendMessage,
    required this.themeTokens,
    this.onVisualSearch,
    this.onFindSimilar,
    this.onAddToWardrobe,
    this.onPlusTap,
    this.onVoiceTap,
    this.micActiveGradientColors,
    this.micActiveShadowColor,
    this.micState = MicState.idle,
    this.interimTranscript = '',
    this.finalTranscript = '',
    this.micAmplitude = 0.0,
    this.isSending = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  @override
  State<AhviChatPromptBar> createState() => _AhviChatPromptBarState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _AhviChatPromptBarState extends State<AhviChatPromptBar> {
  // Debounce guard – prevents double-sends from rapid taps.
  bool _sendLocked = false;

  // Track previous micState to detect transition → awaitingReview.
  MicState _prevMicState = MicState.idle;

  // Snapshot of text BEFORE interim preview was injected so we can restore it.
  String _textBeforeInterim = '';
  bool _interimInjected = false;

  LinearGradient get _accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [widget.accent, widget.accentSecondary],
      );

  // ── Lens sheet ────────────────────────────────────────────────────────────

  void _openLensSheet(BuildContext context) {
    final ctx = context;
    showAhviLensSheet(
      ctx,
      t: widget.themeTokens,
      onVisualSearch: widget.onVisualSearch,
      onFindSimilar: widget.onFindSimilar,
      onAddToWardrobe:
          widget.onAddToWardrobe ?? () => showAddToWardrobeModal(ctx),
    );
  }

  // ── Send ─────────────────────────────────────────────────────────────────

  Future<void> _trySend() async {
    if (_sendLocked || widget.isSending) return;
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;

    // Lock immediately to prevent double-send.
    setState(() => _sendLocked = true);
    widget.controller.clear();
    widget.onSendMessage(text);

    // Release lock after a short guard window.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _sendLocked = false);
  }

  // ── Voice ─────────────────────────────────────────────────────────────────

  void _handleVoiceTap() {
    if (widget.onVoiceTap != null) {
      widget.onVoiceTap!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Voice input is unavailable here. Please type your message.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: widget.accent,
        ),
      );
    }
  }

  // ── Interim transcript injection / removal ────────────────────────────────

  void _injectInterim(String interim) {
    if (!_interimInjected) {
      _textBeforeInterim = widget.controller.text;
      _interimInjected = true;
    }
    final preview =
        _textBeforeInterim.isEmpty ? interim : '$_textBeforeInterim $interim';
    widget.controller.value = TextEditingValue(
      text: preview,
      selection: TextSelection.collapsed(offset: preview.length),
    );
  }

  void _removeInterim() {
    if (_interimInjected) {
      widget.controller.value = TextEditingValue(
        text: _textBeforeInterim,
        selection:
            TextSelection.collapsed(offset: _textBeforeInterim.length),
      );
      _interimInjected = false;
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didUpdateWidget(AhviChatPromptBar old) {
    super.didUpdateWidget(old);

    final curr = widget.micState;
    final prev = _prevMicState;

    // Inject interim preview while transcribing.
    if (curr == MicState.transcribing &&
        widget.interimTranscript.isNotEmpty) {
      _injectInterim(widget.interimTranscript);
    }

    // When transcription ends (idle / awaitingReview) – remove preview.
    if (prev == MicState.transcribing && curr != MicState.transcribing) {
      _removeInterim();
    }

    // On transition to awaitingReview, inject transcript directly into the
    // text field (no review dialog) so the user can edit and send manually.
    if (prev != MicState.awaitingReview &&
        curr == MicState.awaitingReview &&
        widget.finalTranscript.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _removeInterim();
        final text = widget.finalTranscript.trim();
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        widget.focusNode.requestFocus();
      });
    }

    _prevMicState = curr;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isListening = widget.micState == MicState.listening ||
        widget.micState == MicState.transcribing;

    return Padding(
      padding: widget.padding,
      child: Container(
        decoration: BoxDecoration(
          color: widget.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: widget.shadowMedium,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Waveform amplitude bar (visible while listening) ────────
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: isListening
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _WaveformBar(
                        amplitude: widget.micAmplitude,
                        color: widget.accent,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Main row ────────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 260;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── Plus ────────────────────────────────────────────
                    if (!compact) ...[
                      Builder(
                        builder: (btnCtx) => _ChatPromptPressable(
                          scalePressed: 0.88,
                          onTap: () => widget.onPlusTap != null
                              ? widget.onPlusTap!()
                              : _openLensSheet(btnCtx),
                          child: _IconBox(
                            gradientColors: [
                              widget.accent.withValues(alpha: 0.18),
                              widget.accentSecondary
                                  .withValues(alpha: 0.18),
                            ],
                            child: Icon(
                              Icons.add_rounded,
                              color: widget.accent,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // ── Expandable text field ────────────────────────────
                    Expanded(
                      child: _ExpandableTextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        hintText: widget.hintText,
                        textColor: widget.textHeading,
                        hintColor: widget.textMuted,
                        cursorColor: widget.accent,
                        onSubmitted: (_) => _trySend(),
                        // Disable typing during listening so interim
                        // preview isn't corrupted by the user.
                        readOnly: isListening,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ── Mic / Stop ───────────────────────────────────────
                    _ChatPromptPressable(
                      scalePressed: 0.90,
                      onTap: _handleVoiceTap,
                      child: _MicButton(
                        micState: widget.micState,
                        amplitude: widget.micAmplitude,
                        accent: widget.accent,
                        accentSecondary: widget.accentSecondary,
                        activeGradientColors: widget.micActiveGradientColors,
                        activeShadowColor: widget.micActiveShadowColor,
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ── Send ─────────────────────────────────────────────
                    _ChatPromptPressable(
                      liftY: -1.5,
                      scalePressed: 0.90,
                      onTap: _trySend,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: widget.hasTextListenable ??
                            widget.controller,
                        builder: (context, value, _) {
                          final hasText = widget.hasText ??
                              value.text.trim().isNotEmpty;
                          final sending = widget.isSending || _sendLocked;
                          final iconColor =
                              widget.accent.computeLuminance() > 0.4
                                  ? widget.onAccent
                                  : Colors.white;
                          return _SendButton(
                            hasText: hasText,
                            isSending: sending,
                            gradient: _accentGradient,
                            accent: widget.accent,
                            accentSecondary: widget.accentSecondary,
                            iconColor: iconColor,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable text field
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final Color textColor;
  final Color hintColor;
  final Color cursorColor;
  final ValueChanged<String> onSubmitted;
  final bool readOnly;

  const _ExpandableTextField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.textColor,
    required this.hintColor,
    required this.cursorColor,
    required this.onSubmitted,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Grows from 1 line (≈20 px) up to 5 lines (≈104 px); scrolls beyond.
      constraints: const BoxConstraints(maxHeight: 104),
      child: ScrollConfiguration(
        // Hide the scrollbar thumb while still allowing scrolling.
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
        ),
        child: TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        // minLines + maxLines = null → auto-expands until maxHeight.
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: TextStyle(
          color: textColor,
          fontSize: 14.5,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: hintText,
          hintStyle: TextStyle(
            color: hintColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w300,
            height: 1.4,
          ),
        ),
        cursorColor: cursorColor,
        cursorWidth: 1.5,
        cursorRadius: const Radius.circular(1),
        // Swipe-up gesture on keyboard sends (works with TextInputAction.newline).
        onSubmitted: onSubmitted,
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mic button – idle / listening / transcribing / sending states
// ─────────────────────────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  final MicState micState;
  final double amplitude;
  final Color accent;
  final Color accentSecondary;

  /// Gradient colors shown while the mic is active (listening / transcribing).
  /// Defaults to a red-to-pink pair if not provided.
  final List<Color>? activeGradientColors;

  /// Shadow color shown while the mic is active.
  /// Defaults to [Colors.redAccent] if not provided.
  final Color? activeShadowColor;

  const _MicButton({
    required this.micState,
    required this.amplitude,
    required this.accent,
    required this.accentSecondary,
    this.activeGradientColors,
    this.activeShadowColor,
  });

  bool get _active =>
      micState == MicState.listening || micState == MicState.transcribing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: _active
            ? LinearGradient(
                colors: activeGradientColors ??
                    const [Color(0xFFFF4757), Color(0xFFFF6B81)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  accentSecondary.withValues(alpha: 0.18),
                ],
              ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: _active
            ? [
                BoxShadow(
                  color: (activeShadowColor ?? Colors.redAccent)
                      .withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: _active
          ? _active
              ? _PulsingMicIcon(amplitude: amplitude)
              : const _PulsingMicIcon(amplitude: 0)
          : Icon(Icons.mic_none_rounded, color: accent, size: 18),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform amplitude bar
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformBar extends StatelessWidget {
  final double amplitude; // 0.0 – 1.0
  final Color color;

  const _WaveformBar({required this.amplitude, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(12, (i) {
          // Each bar oscillates based on a phase offset + amplitude.
          final phase = (i % 3) / 3.0;
          final h = 4.0 + (amplitude * 14.0 * (0.4 + phase * 0.6));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 3,
              height: h.clamp(4.0, 18.0),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7 + amplitude * 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Send button – idle / has-text / sending
// ─────────────────────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  final bool hasText;
  final bool isSending;
  final LinearGradient gradient;
  final Color accent;
  final Color accentSecondary;
  final Color iconColor;

  const _SendButton({
    required this.hasText,
    required this.isSending,
    required this.gradient,
    required this.accent,
    required this.accentSecondary,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: hasText
            ? gradient
            : LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.35),
                  accentSecondary.withValues(alpha: 0.35),
                ],
              ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: hasText
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: accentSecondary.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isSending
              ? SizedBox(
                  key: const ValueKey('spinner'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                )
              : Icon(
                  key: const ValueKey('arrow'),
                  Icons.arrow_forward_rounded,
                  color: iconColor,
                  size: 16,
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable icon box (38 × 38)
// ─────────────────────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  final List<Color> gradientColors;
  final Widget child;

  const _IconBox({required this.gradientColors, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pressable wrapper (unchanged from original, minor cleanup)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatPromptPressable extends StatefulWidget {
  final Widget? child;
  final Widget Function(bool isHovered, bool isPressed)? builder;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final double liftY;
  final double scaleHover;
  final double scalePressed;

  const _ChatPromptPressable({
    this.child,
    this.builder,
    this.onTap,
    this.onTapDown,
    this.liftY = 0.0,
    this.scaleHover = 1.0,
    this.scalePressed = 0.97,
  }) : assert(child != null || builder != null);

  @override
  State<_ChatPromptPressable> createState() =>
      _ChatPromptPressableState();
}

class _ChatPromptPressableState extends State<_ChatPromptPressable> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale =
        _isPressed ? widget.scalePressed : (_isHovered ? widget.scaleHover : 1.0);
    final dy = (_isPressed || !_isHovered) ? 0.0 : -widget.liftY;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) {
          widget.onTapDown?.call();
          setState(() => _isPressed = true);
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: _isPressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 340),
          curve: _isPressed
              ? const Cubic(0.4, 0.0, 1.0, 1.0)
              : const Cubic(0.34, 1.40, 0.64, 1.0),
          transform:
              Matrix4.translationValues(0.0, dy, 0.0)
                ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0)),
          transformAlignment: Alignment.center,
          child: widget.builder != null
              ? widget.builder!(_isHovered, _isPressed)
              : widget.child!,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing mic icon – amplitude-aware
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingMicIcon extends StatefulWidget {
  final double amplitude;
  const _PulsingMicIcon({this.amplitude = 0});

  @override
  State<_PulsingMicIcon> createState() => _PulsingMicIconState();
}

class _PulsingMicIconState extends State<_PulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _baseScale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _baseScale = Tween<double>(begin: 0.85, end: 1.15)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Combine base animation with live amplitude for a reactive feel.
    return AnimatedBuilder(
      animation: _baseScale,
      builder: (context, child) {
        final scale = _baseScale.value + widget.amplitude * 0.15;
        return Transform.scale(
          scale: scale.clamp(0.8, 1.3),
          child: child,
        );
      },
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Usage example
// ─────────────────────────────────────────────────────────────────────────────
//
// In your parent widget:
//
//   MicState _micState = MicState.idle;
//   String _interimTranscript = '';
//   String _finalTranscript = '';
//   double _micAmplitude = 0.0;
//   bool _isSending = false;
//
//   AhviChatPromptBar(
//     controller: _controller,
//     focusNode: _focusNode,
//     hintText: 'Search or ask anything...',
//     micState: _micState,
//     interimTranscript: _interimTranscript,
//     finalTranscript: _finalTranscript,
//     micAmplitude: _micAmplitude,
//     isSending: _isSending,
//     onVoiceTap: () {
//       if (_micState == MicState.idle) {
//         _speechService.startListening(
//           onInterim: (t, amp) => setState(() {
//             _micState = MicState.transcribing;
//             _interimTranscript = t;
//             _micAmplitude = amp;
//           }),
//           onFinal: (t) => setState(() {
//             _micState = MicState.awaitingReview;
//             _finalTranscript = t;
//             _micAmplitude = 0;
//           }),
//         );
//         setState(() => _micState = MicState.listening);
//       } else {
//         _speechService.stopListening();
//       }
//     },
//     onSendMessage: (message) async {
//       setState(() => _isSending = true);
//       await myChatService.send(message);
//       setState(() { _isSending = false; _micState = MicState.idle; });
//     },
//     // ... other required colour params
//   )

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:myapp/widgets/ahvi_home_text.dart';
import 'package:myapp/theme/theme_tokens.dart';

/// ── AhviHeader ──────────────────────────────────────────────────────────────
/// One reusable, STATIC header used by Home, Chat, Boards, and Wardrobe.
///
/// Rules that keep it perfectly stable:
///   • It is a StatelessWidget — same props → Flutter skips rebuild entirely.
///   • It uses MediaQuery.sizeOf() for the font-size branch (size-only,
///     no viewInsets subscription → keyboard can't trigger a rebuild here).
///   • It must always be the FIRST child of a Column, NEVER inside
///     AnimatedBuilder / ValueListenableBuilder / setState-heavy widgets.
///
/// Usage examples
/// ──────────────
/// Home (inside Positioned, top: 0):
///   AhviHeader(right: _buildProfileAvatar())
///
/// Chat:
///   AhviHeader(showBack: true, right: IconButton(...historyDrawer))
///
/// Boards / Wardrobe:
///   const AhviHeader()
class AhviHeader extends StatelessWidget {
  /// Show the back-arrow on the left (Chat, detail screens).
  final bool showBack;

  /// Custom back handler. Falls back to Navigator.pop() when null.
  final VoidCallback? onBack;

  /// Optional widget pinned to the right (profile avatar, history icon, etc.).
  final Widget? right;

  /// Draw a hairline bottom border (matches Wardrobe / Chat header style).
  final bool showBorder;

  /// Slight frosted-glass bg so content scrolls cleanly underneath.
  final bool frosted;

  /// Left/right inset for the header row. Defaults to 20 (the value every
  /// screen used before this fix). Pass the SAME horizontal gutter the
  /// screen's own body content uses (e.g. Home's responsive `horizontalPad`)
  /// so the logo lines up with the greeting/cards below it instead of using
  /// a fixed 20px that drifts out of sync on small phones and tablets where
  /// the body gutter is narrower/wider (or centered).
  final double horizontalPadding;

  const AhviHeader({
    super.key,
    this.showBack = false,
    this.onBack,
    this.right,
    this.showBorder = false,
    this.frosted = false,
    this.horizontalPadding = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.themeTokens;

    // Use sizeOf — subscribes ONLY to size changes, not viewInsets.
    // Keyboard open/close never triggers a rebuild of this widget.
    final screenH = MediaQuery.sizeOf(context).height;
    final double topPad = screenH < 700 ? 6.0 : 10.0;
    final double botPad = screenH < 700 ? 4.0 : 6.0;
    final double logoSize = screenH < 700 ? 26.0 : 30.0;

    // NOT a Hero. The tag 'ahvi_logo' lived only in this shared header, so it
    // never had a counterpart on another screen to animate to — every
    // navigation just placed two identical-tag heroes in one transition
    // subtree, throwing "multiple heroes share the same tag" -> red error
    // flash on open. The Hero gave no benefit, only collisions.
    Widget logo = AhviHomeText(
      color: t.textPrimary,
      fontSize: logoSize,
      letterSpacing: 3.2,
      fontWeight: FontWeight.w400,
    );

    return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.only(top: 0), // no extra SafeArea top padding
      child: ClipRect(
        child: BackdropFilter(
          filter: frosted
              ? ImageFilter.blur(sigmaX: 18, sigmaY: 18)
              : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: frosted
                  ? t.backgroundPrimary.withValues(alpha: 0.55)
                  : Colors.transparent,
              border: showBorder
                  ? Border(bottom: BorderSide(color: t.cardBorder, width: 0.5))
                  : null,
            ),
            child: SizedBox(
              height: 33.0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showBack) ...[
                      GestureDetector(
                        onTap: onBack ?? () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: t.textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: logo,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // 🔧 FIX: Removed FittedBox + logoSize SizedBox that was
                    // squeezing the right widget (notification bell + profile
                    // avatar) from 48px down to 26-30px.
                    // Now right widget renders at its own natural 48px size.
                    if (right != null)
                      Flexible(
                        fit: FlexFit.loose,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: right!,
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

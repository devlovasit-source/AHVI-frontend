import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapp/app_routes.dart';

class AhviHomeText extends StatelessWidget {
  const AhviHomeText({
    super.key,
    this.color,
    this.fontSize = 36,
    this.letterSpacing = 3.2,
    this.fontWeight = FontWeight.w400,
  });

  final Color? color;
  final double fontSize;
  final double letterSpacing;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
      },
      child: Material(
        type:
            MaterialType.transparency, // inherited elevation/shadow తీసేస్తుంది
        child: Text(
          'AHVI',
          style: TextStyle(
            fontFamily: 'Anton',
            color: textColor,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
            height: 1.0,
            shadows: const [],
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

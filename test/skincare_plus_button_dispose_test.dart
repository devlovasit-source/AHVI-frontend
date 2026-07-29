import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/skincare.dart';

void main() {
  testWidgets(
    'SkincarePlusButton disposes without a setState/lifecycle assertion',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: debugSkincarePlusButton())),
        ),
      );
      await tester.pump();

      // Unmount the subtree -> _SkincarePlusButtonState.dispose().
      // Before the fix, dispose() called _closeMenu(), which calls setState()
      // (mounted still reads true during dispose) and reverses the animation
      // controller -> defunct _ElementLifecycle / setState-after-dispose
      // assertion. The fixed dispose() tears down the overlay + controller
      // directly with no rebuild.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}

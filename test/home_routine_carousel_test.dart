// Widget tests for the Home five-card daily-summary carousel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/widgets/home_routine_carousel.dart';

const _palette = HomeRoutinePalette(
  accent: Color(0xFF7B6EF6),
  border: Color(0xFFCCCCCC),
  cardColor: Color(0xFFF5F5F7),
  textHeading: Color(0xFF111111),
  textMuted: Color(0xFF777777),
  onAccent: Color(0xFFFFFFFF),
);

List<HomeRoutineCardData> _cards({
  bool medicineOverdue = false,
  Map<int, VoidCallback>? taps,
}) {
  final specs = [
    ('Wear', Icons.dry_cleaning_outlined, 'Comfortable layers today', 'Mild 24C'),
    ('Move', Icons.directions_run_rounded, 'Men - 10 Min Core', 'Keep your streak'),
    ('Eat', Icons.restaurant_outlined, 'Dinner Meal', "Today's dinner plan"),
    ('Care', Icons.spa_outlined, 'Morning routine ready', 'Glow steps'),
    ('Medicine', Icons.medication_outlined, "Review today's reminders",
        medicineOverdue ? '3 overdue' : 'All done'),
  ];
  return [
    for (int i = 0; i < specs.length; i++)
      HomeRoutineCardData(
        icon: specs[i].$2,
        color: const Color(0xFF6B8FD4),
        label: specs[i].$1,
        primary: specs[i].$3,
        context: specs[i].$4,
        stateLabel: '',
        cta: specs[i].$1,
        done: false,
        overdue: i == 4 && medicineOverdue,
        onOpen: taps?[i] ?? () {},
      ),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  Widget carousel, {
  double width = 390,
  double height = 160,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: carousel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows one readable card and a preview of the next', (t) async {
    await _pump(t, HomeRoutineCarousel(cards: _cards(), palette: _palette));
    // First card fully present.
    expect(find.text('Comfortable layers today'), findsOneWidget);
    // Next card peeks in — its label is built and laid out (title + CTA).
    expect(find.text('Move'), findsWidgets);
    // Far card not yet in view.
    expect(find.text("Review today's reminders"), findsNothing);
  });

  testWidgets('swipes through all five cards', (t) async {
    await _pump(t, HomeRoutineCarousel(cards: _cards(), palette: _palette));
    for (var i = 0; i < 4; i++) {
      await t.drag(find.byType(PageView), const Offset(-400, 0));
      await t.pumpAndSettle();
    }
    expect(find.text("Review today's reminders"), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('title and CTA present at 360px width', (t) async {
    await _pump(t, HomeRoutineCarousel(cards: _cards(), palette: _palette),
        width: 360);
    expect(find.text('Wear'), findsWidgets); // module title (also CTA)
    // CTA arrow always visible on the active card.
    expect(find.byIcon(Icons.arrow_forward_rounded), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('no overflow at 360 logical pixels', (t) async {
    await _pump(t, HomeRoutineCarousel(cards: _cards(), palette: _palette),
        width: 360, height: 150);
    expect(t.takeException(), isNull);
  });

  testWidgets('medicine overdue shows warning styling', (t) async {
    await _pump(
        t, HomeRoutineCarousel(cards: _cards(medicineOverdue: true), palette: _palette));
    // Swipe to the medicine card.
    for (var i = 0; i < 4; i++) {
      await t.drag(find.byType(PageView), const Offset(-400, 0));
      await t.pumpAndSettle();
    }
    expect(find.text('3 overdue'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsWidgets);
  });

  testWidgets('tapping a card triggers its navigation callback', (t) async {
    var opened = -1;
    await _pump(
      t,
      HomeRoutineCarousel(
        cards: _cards(taps: {0: () => opened = 0}),
        palette: _palette,
      ),
    );
    await t.tap(find.text('Comfortable layers today'));
    expect(opened, 0);
  });

  testWidgets('renders a segmented indicator with one segment per card',
      (t) async {
    await _pump(t, HomeRoutineCarousel(cards: _cards(), palette: _palette));
    // Indicator segments are AnimatedContainers; 5 cards -> 5 segments.
    final segments = find.byType(AnimatedContainer);
    expect(segments, findsNWidgets(5));
  });

  testWidgets('module title is never ellipsized', (t) async {
    await _pump(t, HomeRoutineCarousel(cards: _cards(), palette: _palette),
        width: 360);
    final title = t.widget<Text>(find.text('Wear').first);
    expect(title.overflow, TextOverflow.visible);
  });

  // ── Regression: Move supporting-copy truncation/collapse ────────────────

  HomeRoutineCardData singleCard({required String context, String primary = 'Move headline'}) =>
      HomeRoutineCardData(
        icon: Icons.directions_run_rounded,
        color: const Color(0xFF6B8FD4),
        label: 'Move',
        primary: primary,
        context: context,
        stateLabel: '',
        cta: 'Move',
        done: false,
        overdue: false,
        onOpen: () {},
      );

  testWidgets(
      'MOVE_COPY_COMPLETE: reasonable-length context renders in full at normal card height, not a manual substring cut',
      (t) async {
    const longButReasonable = 'Best window is now, keep your streak going';
    await _pump(
      t,
      HomeRoutineCarousel(cards: [singleCard(context: longButReasonable)], palette: _palette),
      height: 170,
    );
    // The Text widget still holds the complete provider string — Flutter's
    // own (width-aware) ellipsis handles overflow, not a blind char-count
    // substring producing a mid-word fragment like "workout recom...".
    expect(find.text(longButReasonable), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'MOVE_COPY_COMPLETE: context up to 2 lines is allowed instead of forcing a single truncated line',
      (t) async {
    const longButReasonable = 'Best window is now, keep your streak going';
    await _pump(
      t,
      HomeRoutineCarousel(cards: [singleCard(context: longButReasonable)], palette: _palette),
      height: 170,
    );
    final text = t.widget<Text>(find.text(longButReasonable));
    expect(text.maxLines, greaterThan(1));
  });

  testWidgets(
      'context never renders as a clipped partial-line fragment — hides cleanly on a squeezed card instead',
      (t) async {
    // Height too small for even one context line: previously the bare
    // Flexible(child: Text(maxLines: 1)) would be squeezed into a
    // sub-line-height box and paint a clipped sliver of glyphs. Now it must
    // hide entirely rather than render a broken fragment.
    await _pump(
      t,
      HomeRoutineCarousel(cards: [singleCard(context: 'Keep your streak going')], palette: _palette),
      height: 118,
    );
    expect(find.text('Keep your streak going'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('an exceptionally long context still degrades gracefully via native ellipsis, no overflow',
      (t) async {
    const exceptional =
        'This is an unusually long supporting sentence that goes on and on well past what any Home card should ever realistically need to show to a user';
    await _pump(
      t,
      HomeRoutineCarousel(cards: [singleCard(context: exceptional)], palette: _palette),
      height: 170,
    );
    expect(t.takeException(), isNull);
  });
}

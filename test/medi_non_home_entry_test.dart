import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/boards.dart';
import 'package:myapp/home_and_utilities.dart';
import 'package:myapp/medi_tracker.dart';
import 'package:myapp/theme/accent_palette.dart';
import 'package:myapp/theme/theme_tokens.dart';

const _accent = AccentPalette(
  primary: Color(0xFFFF8EC7),
  secondary: Color(0xFF8D7DFF),
  tertiary: Color(0xFF04D7C8),
);

void main() {
  testWidgets(
    'Boards Home Utilities route paints non-Home Medi safely before fetch',
    (tester) async {
      final pendingFetch = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppThemeTokens.light(_accent)]),
          localizationsDelegates: const [_MalformedMediDelegate()],
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  buildBoardsPushRoute(
                    HomeUtilitiesScreen(
                      mediChild: MediTrackScreen(
                        beforeInitialFetch: () => pendingFetch.future,
                      ),
                      billsChild: const SizedBox.shrink(),
                      contactsChild: const SizedBox.shrink(),
                    ),
                  ),
                ),
                child: const Text('Open Home Utilities'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open Home Utilities'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('\uFFFD'),
        ),
        findsWidgets,
      );
      expect(find.text('Medi \uFFFD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _MalformedMediDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _MalformedMediDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      _MalformedMediLocalizations(locale);

  @override
  bool shouldReload(_MalformedMediDelegate old) => false;
}

class _MalformedMediLocalizations extends AppLocalizations {
  _MalformedMediLocalizations(super.locale);

  @override
  String translate(String key) => switch (key) {
    'home_title_bold' => 'Home \uD800',
    'home_title_light' => '& Utilities \uDC00',
    'home_tab_medi' => 'Medi \uD800',
    'home_tab_bills' => 'Bills',
    'home_tab_contacts' => 'Contacts',
    _ => key,
  };
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final backendSource = File(
    'lib/services/backend_service.dart',
  ).readAsStringSync();
  final chatSource = File(
    'lib/widgets/ahvi_stylist_chat.dart',
  ).readAsStringSync();

  test('reachable Style calls do not use the three missing backend routes', () {
    expect(backendSource, isNot(contains('/api/stylist/daily-board')));
    expect(backendSource, isNot(contains('/api/style/log-wear')));
    expect(
      backendSource,
      isNot(contains("Uri.parse('\$baseUrl/api/style-boards/")),
    );
    expect(backendSource, contains('/api/stylist/pipeline'));
    expect(backendSource, contains('/api/style/wear-today'));
    expect(backendSource, contains('UNSUPPORTED_BETA_MUTATION'));
  });

  test('compact Style state is sent and retained per chat session', () {
    expect(backendSource, contains("'style_state': styleState"));
    expect(chatSource, contains('styleState: _latestStyleState.isEmpty'));
    expect(chatSource, contains("_latestStyleState = {};"));
    expect(chatSource, contains("'styleState': styleState"));
    expect(chatSource, contains("response['style_state']"));
  });

  test('optional beta cards preserve legacy rendering', () {
    // Beta diagnostics (AHVI UNDERSTOOD / CONSTRAINT CHECK) are gated behind
    // the explicit developer flag so they never show in the beta APK.
    expect(chatSource, contains('if (msg.betaInsights != null && Env.showStyleDebug)'));
    expect(chatSource, contains('AHVI UNDERSTOOD'));
    expect(chatSource, contains('CONSTRAINT CHECK'));
    expect(chatSource, contains('AHVI VISUAL READ'));
    expect(chatSource, contains('.take(3)'));
    expect(chatSource, contains("validationStatus == 'partial'"));
    expect(chatSource, contains("validationStatus == 'failed'"));
  });

  test('frontend never sends visual image bytes and only trusts backend status', () {
    expect(chatSource, isNot(contains("'image_base64':")));
    expect(chatSource, isNot(contains("'board_base64':")));
    expect(chatSource, isNot(contains('preserved item')));
    expect(chatSource, contains("status['passed_constraints']"));
  });

  test('style state restores only with its matching chat session', () {
    expect(chatSource, contains('styleStateOwnerId: _styleStateOwnerId'));
    expect(chatSource, contains('session.styleStateOwnerId == _styleStateOwnerId'));
    expect(chatSource, contains('await _ensureStyleStateOwner();'));
    expect(chatSource, contains('_latestStyleState = {};'));
    expect(chatSource, contains('_lastStyleContext = null;'));
  });
}

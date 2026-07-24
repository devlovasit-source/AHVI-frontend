import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/config/env.dart';

void main() {
  test('showStyleDebug defaults to false (debug cards hidden unless explicitly enabled)', () {
    // dotenv is not initialized here, so the guarded getter must fall back to
    // false rather than throw — the beta APK must never surface the diagnostics.
    expect(Env.showStyleDebug, isFalse);
  });
}

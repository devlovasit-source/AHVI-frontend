import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/config/env.dart';

void main() {
  test('runtime provenance does not use the stale placeholder version', () {
    expect(Env.build, isNot('1.0.0+1'));
    expect(Env.canonicalRendererVersion, 'editorial_board_canonical_v1');
  });

  test('runtime provenance exposes supplied compile-time values', () {
    const expectedSha = String.fromEnvironment(
      'AHVI_EXPECTED_FRONTEND_SHA',
      defaultValue: '',
    );
    const expectedBuild = String.fromEnvironment(
      'AHVI_EXPECTED_BUILD',
      defaultValue: '',
    );

    if (expectedSha.isEmpty && expectedBuild.isEmpty) {
      expect(Env.frontendSha, 'unknown');
      expect(Env.build, 'dev_0');
      return;
    }

    expect(expectedSha, isNotEmpty);
    expect(expectedBuild, isNotEmpty);
    expect(Env.frontendSha, expectedSha);
    expect(Env.build, expectedBuild);
    expect(Env.runtimeProvenanceLog, 'frontend_sha=$expectedSha build=$expectedBuild');
  });

  test('runtime provenance contains only non-sensitive identity fields', () {
    expect(Env.runtimeProvenance, {
      'frontend_sha': Env.frontendSha,
      'build': Env.build,
    });
    expect(Env.runtimeProvenance.keys, isNot(contains('API_KEY')));
    expect(Env.runtimeProvenance.keys, isNot(contains('SECRET')));
  });
}

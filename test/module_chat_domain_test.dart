import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/services/backend_service.dart';

void main() {
  test('Prep uses the plan backend domain', () {
    expect(canonicalModuleChatDomain(' prepare '), 'plan');
  });

  test('packing requests use the planner backend domain', () {
    expect(
      canonicalModuleChatDomain('prepare', plannerRequest: true),
      'planner',
    );
    expect(
      canonicalModuleChatDomain('medi', plannerRequest: true),
      'planner',
    );
  });

  test('other module domains remain unchanged', () {
    expect(canonicalModuleChatDomain(' Fitness '), 'fitness');
    expect(canonicalModuleChatDomain('style'), 'style');
  });
}

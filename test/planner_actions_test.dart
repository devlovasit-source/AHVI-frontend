import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/models/planner_actions.dart';

void main() {
  test('carry-on Planner chip enters planner with a real packing request', () {
    final route = plannerRouteFor('prepare_carry_on');

    expect(route.module, 'prepare');
    expect(route.prompt, 'Pack for a carry-on trip');
  });

  test('camping Planner chip includes pack and trip trigger words', () {
    final route = plannerRouteFor('prepare_camping');

    expect(route.module, 'prepare');
    expect(route.prompt.toLowerCase(), contains('pack'));
    expect(route.prompt.toLowerCase(), contains('trip'));
  });

  test('unknown Planner action still submits a non-empty planner request', () {
    final route = plannerRouteFor('prepare_custom');

    expect(route.module, 'prepare');
    expect(route.prompt, 'prepare_custom');
  });
}

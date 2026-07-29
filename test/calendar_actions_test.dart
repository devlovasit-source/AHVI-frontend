import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/app_routes.dart';
import 'package:myapp/models/calendar_actions.dart';
import 'package:myapp/models/calendar_event_record.dart';

void main() {
  test('View events navigates without requesting module chat', () async {
    final coordinator = CalendarActionCoordinator();
    var navigationCount = 0;
    var requestCount = 0;

    await coordinator.dispatch(
      CalendarQuickAction.viewEvents,
      navigate: (route) async {
        expect(route, AppRoutes.calendar);
        navigationCount++;
      },
      requestPlan: (_) async {
        requestCount++;
      },
    );

    expect(navigationCount, 1);
    expect(requestCount, 0);
  });

  test('rapid View events actions trigger one navigation', () async {
    final coordinator = CalendarActionCoordinator();
    final routeOpen = Completer<void>();
    var navigationCount = 0;

    Future<void> navigate(String route) {
      navigationCount++;
      return routeOpen.future;
    }

    final first = coordinator.dispatch(
      CalendarQuickAction.viewEvents,
      navigate: navigate,
      requestPlan: (_) async {},
    );
    final second = coordinator.dispatch(
      CalendarQuickAction.viewEvents,
      navigate: navigate,
      requestPlan: (_) async {},
    );

    expect(navigationCount, 1);
    routeOpen.complete();
    await Future.wait([first, second]);
  });

  test('Calendar route variants normalize to the supported route', () {
    expect(normalizeCalendarRoute('calendar'), AppRoutes.calendar);
    expect(normalizeCalendarRoute('/organize/calendar'), AppRoutes.calendar);
  });

  test('Prep for tomorrow sends its canonical structured action', () {
    final action = calendarQuickActionFor(
      value: 'Prep for tomorrow',
      label: 'Prep for tomorrow',
    );
    final request = calendarActionRequest(action!, occasion: 'Gym');

    expect(action, CalendarQuickAction.prepTomorrow);
    expect(request.context['calendar_action'], 'calendar_prep_tomorrow');
    expect(request.context['requested_plan_type'], 'tomorrow_prep');
  });

  test('occasion context does not prefix or override the prep request', () {
    final request = calendarActionRequest(
      CalendarQuickAction.prepTomorrow,
      occasion: 'Gym',
    );

    expect(request.message, isNot(contains('Occasion:')));
    expect(request.message.toLowerCase(), contains('tomorrow'));
    expect(request.context['occasion'], 'Gym');
    expect(request.context['calendar_action'], 'calendar_prep_tomorrow');
  });

  test('Plan my day and Prep for tomorrow retain distinct identities', () {
    final day = calendarQuickActionFor(
      value: 'plan_pack',
      label: 'Plan my day',
    );
    final prep = calendarQuickActionFor(
      value: 'plan_pack',
      label: 'Prep for tomorrow',
    );

    expect(day, CalendarQuickAction.planDay);
    expect(prep, CalendarQuickAction.prepTomorrow);
    expect(day!.id, isNot(prep!.id));
  });

  test('plan_pack renders with the requested Tomorrow Prep Plan identity', () {
    final plan = CalendarPlanPack.tryParse({
      'intent': 'plan_pack',
      'data': {
        'prep': {
          'sections': [
            {
              'title': 'Tonight',
              'items': ['Pack gym clothes'],
            },
          ],
        },
      },
    }, requestedAction: CalendarQuickAction.prepTomorrow);

    expect(plan, isNotNull);
    expect(plan!.title, 'Tomorrow Prep Plan');
    expect(plan.planType, 'tomorrow_prep');
    expect(plan.sections.single.items.single, 'Pack gym clothes');
  });

  test('plan_pack accepts backend visual checklist sections', () {
    final plan = CalendarPlanPack.tryParse({
      'intent': 'plan_pack',
      'visual_sections': [
        {
          'title': 'Morning',
          'items': [
            {'display_label': 'Check the weather'},
          ],
        },
      ],
    }, requestedAction: CalendarQuickAction.planDay);

    expect(plan!.title, 'Day Plan');
    expect(plan.sections.single.items.single, 'Check the weather');
  });

  test('CTA and open_module route values are parsed safely', () {
    expect(
      calendarOpenModuleRoute({'open_module': '/organize/calendar'}),
      '/organize/calendar',
    );
    expect(
      calendarOpenModuleRoute({
        'cta': {'route': 'calendar'},
      }),
      'calendar',
    );
    expect(
      calendarOpenModuleRoute({
        'card': {
          'cta': {'target': '/organize/calendar'},
        },
      }),
      '/organize/calendar',
    );
    expect(normalizeCalendarRoute('/organize/unknown'), isNull);
  });

  test('Calendar list diagnostics identify surface and parse counts', () {
    final batch = CalendarEventBatch.parse([
      {
        'id': 'event-1',
        'title': 'Hidden from diagnostics',
        'start_time': '2026-07-28T07:00:00+05:30',
      },
      {'id': 'bad-event', 'start_time': 'not-a-date'},
    ]);

    final homeStart = calendarListStartDiagnostic(
      surface: CalendarListSurface.homeToday,
      from: DateTime.utc(2026, 7, 28),
      to: DateTime.utc(2026, 7, 29),
    );
    final calendarStart = calendarListStartDiagnostic(
      surface: CalendarListSurface.calendar,
    );
    final ok = calendarListOkDiagnostic(
      surface: CalendarListSurface.homeToday,
      batch: batch,
    );

    expect(homeStart, contains('surface=home_today'));
    expect(calendarStart, contains('surface=calendar from=none to=none'));
    expect(ok, contains('raw_count=2 parsed_count=1 skipped_count=1'));
    expect(ok, isNot(contains('Hidden from diagnostics')));
  });
}

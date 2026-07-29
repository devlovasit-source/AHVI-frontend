import 'package:flutter/material.dart';
import 'package:myapp/app_localizations.dart';
import 'package:myapp/models/calendar_actions.dart';
import 'package:myapp/models/calendar_event_record.dart';
import 'package:myapp/services/ahvi_response_parser.dart';
import 'package:myapp/services/ahvi_speech_service.dart';
import 'package:myapp/services/backend_service.dart';
import 'package:myapp/theme/theme_tokens.dart';
import 'package:myapp/models/ahvi_visual_board_model.dart';
import 'package:myapp/widgets/ahvi_visual_board.dart';
import 'package:myapp/widgets/ahvi_module_card.dart';

void main() {
  runApp(const ScheduleApp());
}

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppLocalizations.t(context, 'boards_schedule_calendar'),
      debugShowCheckedModeBanner: false,
      home: const CalendarShell(),
    );
  }
}

// ==========================================
// MODELS
// ==========================================
class PlanItem {
  final String? id;
  final String occasion;
  final IconData icon;
  final String colorTheme;
  final String time;
  final String outfit;
  final DateTime? startTime;
  bool hasReminder;

  PlanItem({
    this.id,
    required this.occasion,
    required this.icon,
    this.colorTheme = 'orange',
    this.time = '',
    this.outfit = '',
    this.startTime,
    this.hasReminder = true,
  });

  PlanItem copyWith({
    String? id,
    String? occasion,
    IconData? icon,
    String? colorTheme,
    String? time,
    String? outfit,
    DateTime? startTime,
    bool? hasReminder,
  }) {
    return PlanItem(
      id: id ?? this.id,
      occasion: occasion ?? this.occasion,
      icon: icon ?? this.icon,
      colorTheme: colorTheme ?? this.colorTheme,
      time: time ?? this.time,
      outfit: outfit ?? this.outfit,
      startTime: startTime ?? this.startTime,
      hasReminder: hasReminder ?? this.hasReminder,
    );
  }
}

class OutfitIdea {
  final String vibe;
  final String desc;
  final String tip;
  final String summary;

  OutfitIdea({
    required this.vibe,
    required this.desc,
    required this.tip,
    required this.summary,
  });
}

// ==========================================
// MAIN SHELL
// ==========================================
class CalendarShell extends StatefulWidget {
  const CalendarShell({super.key});

  @override
  State<CalendarShell> createState() => _CalendarShellState();
}

class _CalendarShellState extends State<CalendarShell> {
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  final BackendService _backend = BackendService();
  final Map<String, List<PlanItem>> _plansData = {};

  bool _isLoadingPlans = false;
  bool _isChatOpen = false;
  String _activeOccasion = 'Gym';
  IconData _activeIcon = Icons.fitness_center;

  String _dateKey(DateTime date) => "${date.year}-${date.month}-${date.day}";

  // Helper formats
  String get _selectedDateKey => _dateKey(_selectedDate);
  String get _todayKey => _dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadCalendarEvents();
  }

  IconData _iconForOccasion(String value) {
    final q = value.toLowerCase();
    if (q.contains('gym') || q.contains('workout') || q.contains('fitness')) {
      return Icons.fitness_center;
    }
    if (q.contains('office') || q.contains('work') || q.contains('meeting')) {
      return Icons.work_outline;
    }
    if (q.contains('party') || q.contains('event')) {
      return Icons.celebration;
    }
    if (q.contains('travel') || q.contains('trip')) {
      return Icons.flight_takeoff;
    }
    if (q.contains('shopping')) {
      return Icons.shopping_bag_outlined;
    }
    if (q.contains('study') || q.contains('class')) {
      return Icons.menu_book;
    }
    if (q.contains('date')) {
      return Icons.favorite_border;
    }
    return Icons.event;
  }

  String _themeForOccasion(String value) {
    final q = value.toLowerCase();
    if (q.contains('office') || q.contains('work') || q.contains('meeting')) {
      return 'blue';
    }
    if (q.contains('party') || q.contains('date')) {
      return 'pink';
    }
    return 'orange';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $suffix';
  }

  DateTime _startDateTimeForPlan(PlanItem plan) {
    if (plan.startTime != null) return plan.startTime!;

    final text = plan.time.trim().toLowerCase();
    var hour = 12;
    var minute = 0;

    final match = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(text);
    if (match != null) {
      hour = int.tryParse(match.group(1) ?? '') ?? 12;
      minute = int.tryParse(match.group(2) ?? '0') ?? 0;
      final suffix = match.group(3);
      if (suffix == 'pm' && hour < 12) hour += 12;
      if (suffix == 'am' && hour == 12) hour = 0;
    }

    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour,
      minute,
    );
  }

  PlanItem _planFromBackendEvent(CalendarEventRecord event) {
    final occasion = (event.metadata['occasion'] ??
            (event.type.isNotEmpty ? event.type : event.title))
        .toString();
    final outfit = (event.metadata['outfit'] ?? event.description)
        .toString();

    return PlanItem(
      id: event.id,
      occasion: occasion.isEmpty ? event.title : occasion,
      icon: _iconForOccasion(occasion),
      colorTheme: _themeForOccasion(occasion),
      time: _formatTime(event.startTime),
      outfit: outfit,
      startTime: event.startTime,
      hasReminder: event.reminderMinutes > 0,
    );
  }

  Future<void> _loadCalendarEvents() async {
    if (_isLoadingPlans) return;
    setState(() => _isLoadingPlans = true);

    final events = await _backend.getCalendarEvents(
      limit: 300,
      surface: CalendarListSurface.calendar,
    );
    final next = <String, List<PlanItem>>{};

    for (final event in events) {
      final record = CalendarEventRecord.tryParse(
        event,
        onSkipped: (eventId, field) => debugPrint(
          'AHVI_CALENDAR_PARSE_SKIPPED event_id=$eventId field=$field',
        ),
      );
      if (record == null) continue;
      final plan = _planFromBackendEvent(record);
      final key = _dateKey(record.startTime);
      next.putIfAbsent(key, () => <PlanItem>[]).add(plan);
    }

    if (!mounted) return;
    setState(() {
      _plansData
        ..clear()
        ..addAll(next);
      _isLoadingPlans = false;
    });
  }

  void _changeMonth(int increment) {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + increment,
        1,
      );
    });
  }

  Future<void> _addPlan(PlanItem plan) async {
    final key = _selectedDateKey;
    setState(() {
      _plansData.putIfAbsent(key, () => <PlanItem>[]);
      _plansData[key]!.add(plan);
    });

    final start = _startDateTimeForPlan(plan);
    final created = await _backend.createCalendarEvent(
      title: plan.occasion,
      description: plan.outfit,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      type: plan.occasion,
      source: 'ahvi_calendar',
      reminderMinutes: plan.hasReminder ? 30 : 0,
      metadata: {
        'occasion': plan.occasion,
        'outfit': plan.outfit,
        'colorTheme': plan.colorTheme,
      },
    );

    if (!mounted) return;
    if (created == null) {
      setState(() => _plansData[key]?.remove(plan));
      return;
    }

    CalendarRefreshSignal.notify();
    await _loadCalendarEvents();
  }

  Future<void> _handleCalendarMutation(Map<String, dynamic> response) async {
    final mutation = CalendarMutationResult.tryParse(response);
    if (mutation == null) return;
    debugPrint('AHVI_CALENDAR_CREATE_START');
    if (mutation.reused) {
      debugPrint('AHVI_CALENDAR_CREATE_REUSED event_id=${mutation.eventId}');
    } else {
      debugPrint('AHVI_CALENDAR_CREATE_OK event_id=${mutation.eventId}');
    }
    if (mutation.reminderConfirmed) {
      final reminderId = mutation.reminderId.isNotEmpty
          ? mutation.reminderId
          : 'scheduled';
      debugPrint('AHVI_CALENDAR_REMINDER_OK reminder_id=$reminderId');
    }
    CalendarRefreshSignal.notify();
    await _loadCalendarEvents();
  }

  Future<void> _removePlan(int index) async {
    final key = _selectedDateKey;
    final plan = (_plansData[key] != null && index < _plansData[key]!.length)
        ? _plansData[key]![index]
        : null;

    setState(() {
      _plansData[key]?.removeAt(index);
    });

    final id = plan?.id;
    if (id != null && id.trim().isNotEmpty) {
      await _backend.deleteCalendarEvent(id);
    }
  }

  Future<void> _toggleReminder(int index) async {
    final key = _selectedDateKey;
    if (_plansData[key] == null || index >= _plansData[key]!.length) return;

    final plan = _plansData[key]![index];
    final nextValue = !plan.hasReminder;

    setState(() {
      _plansData[key]![index].hasReminder = nextValue;
    });

    final id = plan.id;
    if (id != null && id.trim().isNotEmpty) {
      await _backend.updateCalendarEvent(id, {
        'reminder_minutes': nextValue ? 30 : 0,
      });
    }
  }

  void _openChat(String occasion, IconData icon) {
    setState(() {
      _activeOccasion = occasion;
      _activeIcon = icon;
      _isChatOpen = true;
    });
  }

  void _closeChat() {
    setState(() {
      _isChatOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeTokens;
    return Scaffold(
      backgroundColor: theme.backgroundSecondary,
      body: Stack(
        children: [
          const BackgroundScene(),
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _isChatOpen
                      ? StyleChatScreen(
                          key: const ValueKey('chat'),
                          occasion: _activeOccasion,
                          icon: _activeIcon,
                          onBack: _closeChat,
                          onOpenRoute: (route) async => _closeChat(),
                          onCalendarMutation: (response) async {
                            await _handleCalendarMutation(response);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.t(
                                    context,
                                    'calendar_plan_saved',
                                  ),
                                  style: TextStyle(
                                    color: context.themeTokens.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                backgroundColor:
                                    context.themeTokens.backgroundSecondary,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        )
                      : MainCalendarView(
                          key: const ValueKey('calendar'),
                          currentMonth: _currentMonth,
                          selectedDate: _selectedDate,
                          todayKey: _todayKey,
                          selectedDateKey: _selectedDateKey,
                          plans: _plansData[_selectedDateKey] ?? [],
                          allPlansData: _plansData,
                          onMonthChanged: _changeMonth,
                          onDaySelected: (date) {
                            setState(() {
                              _selectedDate = date;
                            });
                          },
                          onAddPlanPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => AddPlanModal(
                                onPlanSaved: _addPlan,
                                onChatOpened: (occ, emo) {
                                  Navigator.pop(ctx);
                                  _openChat(occ, emo);
                                },
                              ),
                            );
                          },
                          onRemovePlan: _removePlan,
                          onToggleReminder: _toggleReminder,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// BACKGROUND EFFECTS
// ==========================================
class BackgroundScene extends StatefulWidget {
  const BackgroundScene({super.key});

  @override
  State<BackgroundScene> createState() => _BackgroundSceneState();
}

class _BackgroundSceneState extends State<BackgroundScene>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeTokens;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          children: [
            // Container matching the fallback background
            Container(color: theme.backgroundSecondary),
            /* 
             * Uncomment the below code to add the animated orbs back.
             * The reference CSS had them hidden so they are omitted for a cleaner look.
             */
            /*
            Positioned(
              top: -100 + (_ctrl.value * 40),
              left: -140 + (_ctrl.value * 60),
              child: _buildOrb(480, theme.accent.primary.withValues(alpha: 0.15)),
            ),
            Positioned(
              top: 260 + (_ctrl.value * -30),
              right: -100 + (_ctrl.value * 40),
              child: _buildOrb(360, theme.accent.secondary.withValues(alpha: 0.15)),
            ),
            Positioned(
              bottom: 60 + (_ctrl.value * 50),
              left: 10 + (_ctrl.value * -30),
              child: _buildOrb(300, theme.accent.tertiary.withValues(alpha: 0.15)),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Container(color: Colors.transparent),
              ),
            ),
            */
          ],
        );
      },
    );
  }
}

// ==========================================
// MAIN CALENDAR VIEW
// ==========================================
class MainCalendarView extends StatelessWidget {
  final DateTime currentMonth;
  final DateTime selectedDate;
  final String todayKey;
  final String selectedDateKey;
  final List<PlanItem> plans;
  final Map<String, List<PlanItem>> allPlansData;
  final Function(int) onMonthChanged;
  final Function(DateTime) onDaySelected;
  final VoidCallback onAddPlanPressed;
  final Function(int) onRemovePlan;
  final Function(int) onToggleReminder;

  MainCalendarView({
    super.key,
    required this.currentMonth,
    required this.selectedDate,
    required this.todayKey,
    required this.selectedDateKey,
    required this.plans,
    required this.allPlansData,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.onAddPlanPressed,
    required this.onRemovePlan,
    required this.onToggleReminder,
  });

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final List<String> _weekdays = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.themeTokens;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      children: [
        // Top Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.maybePop(context);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.card,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.accent.primary.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6.0),
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 18,
                    color: theme.textPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.t(context, 'boards_schedule_calendar'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.accent.tertiary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.accent.tertiary.withValues(
                                alpha: 0.75,
                              ),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${getAllPlansCount()} ${AppLocalizations.t(context, 'calendar_outfit_plans')}',
                        style: TextStyle(fontSize: 12, color: theme.mutedText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Calendar Box
        Container(
          decoration: BoxDecoration(
            color: theme.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.textPrimary.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Month Nav
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _navBtn(
                      Icons.chevron_left_rounded,
                      () => onMonthChanged(-1),
                      theme,
                    ),
                    Text(
                      '${_months[currentMonth.month - 1]} ${currentMonth.year}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.textPrimary,
                      ),
                    ),
                    _navBtn(
                      Icons.chevron_right_rounded,
                      () => onMonthChanged(1),
                      theme,
                    ),
                  ],
                ),
              ),

              // Days Strip
              Builder(
                builder: (ctx) {
                  final now = DateTime.now();
                  final isCurrentMonth =
                      currentMonth.year == now.year &&
                      currentMonth.month == now.month;
                  final totalDays = _daysInMonth(currentMonth);
                  // Auto-scroll to today when viewing current month
                  final scrollCtrl = ScrollController(
                    initialScrollOffset: isCurrentMonth
                        ? ((now.day - 1) * 58.0).clamp(0.0, double.infinity)
                        : 0.0,
                  );
                  return SizedBox(
                    height: 90,
                    child: ListView.builder(
                      controller: scrollCtrl,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: totalDays,
                      itemBuilder: (ctx, index) {
                        final now = DateTime.now();
                        final day = index + 1;
                        final date = DateTime(
                          currentMonth.year,
                          currentMonth.month,
                          day,
                        );
                        final key = "${date.year}-${date.month}-${date.day}";
                        final isSelected = key == selectedDateKey;
                        final isToday = key == todayKey;
                        final hasEvent =
                            (allPlansData[key]?.isNotEmpty ?? false);
                        final isPast = date.isBefore(
                          DateTime(now.year, now.month, now.day),
                        );

                        return GestureDetector(
                          onTap: () => onDaySelected(date),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 4,
                            ),
                            width: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: isPast && !isSelected
                                  ? theme.card.withValues(alpha: 0.55)
                                  : theme.card,
                              border: Border.all(
                                color: isSelected
                                    ? theme.accent.primary
                                    : Colors.transparent,
                                width: isSelected ? 1.5 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: theme.accent.primary.withValues(
                                          alpha: 0.6,
                                        ),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (isToday)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: theme.accent.tertiary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                if (hasEvent)
                                  Positioned(
                                    bottom: 6,
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: theme.accent.secondary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _weekdays[date.weekday % 7],
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? theme.accent.primary
                                            : (isPast
                                                  ? theme.mutedText.withValues(
                                                      alpha: 0.5,
                                                    )
                                                  : theme.mutedText),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$day',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: isPast && !isSelected
                                            ? theme.textPrimary.withValues(
                                                alpha: 0.35,
                                              )
                                            : theme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),

              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: theme.textPrimary.withValues(alpha: 0.06),
              ),

              // Plans Section
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      selectedDateKey == todayKey
                          ? AppLocalizations.t(context, 'calendar_todays_plans')
                          : "${_months[selectedDate.month - 1]} ${selectedDate.day} ${AppLocalizations.t(context, 'calendar_plans')}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.mutedText,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (plans.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          AppLocalizations.t(context, 'calendar_no_plans'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.mutedText,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      )
                    else
                      ...List.generate(plans.length, (idx) {
                        final plan = plans[idx];
                        Color sideColor = theme.accent.primary;
                        List<Color> bgGrad = [
                          theme.accent.primary.withValues(alpha: 0.13),
                          theme.accent.primary.withValues(alpha: 0.07),
                        ];

                        if (plan.colorTheme == 'blue') {
                          sideColor = theme.accent.secondary;
                          bgGrad = [
                            theme.accent.secondary.withValues(alpha: 0.12),
                            theme.accent.secondary.withValues(alpha: 0.06),
                          ];
                        } else if (plan.colorTheme == 'pink') {
                          sideColor = theme.accent.tertiary;
                          bgGrad = [
                            theme.accent.tertiary.withValues(alpha: 0.12),
                            theme.accent.tertiary.withValues(alpha: 0.06),
                          ];
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: bgGrad,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border(
                              left: BorderSide(color: sideColor, width: 4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: sideColor.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  13,
                                  9,
                                  40,
                                  9,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      plan.icon,
                                      size: 16,
                                      color: theme.textPrimary,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      plan.occasion,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: theme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      plan.time.isEmpty
                                          ? AppLocalizations.t(
                                              context,
                                              'calendar_planned',
                                            )
                                          : plan.time,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: theme.mutedText,
                                      ),
                                    ),
                                    if (plan.outfit.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        plan.outfit,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: theme.textPrimary.withValues(
                                            alpha: 0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: theme.mutedText,
                                  ),
                                  onPressed: () => onRemovePlan(idx),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: IconButton(
                                  icon: Icon(
                                    plan.hasReminder
                                        ? Icons.notifications_active
                                        : Icons.notifications_off,
                                    size: 14,
                                    color: plan.hasReminder
                                        ? theme.accent.primary
                                        : theme.mutedText,
                                  ),
                                  onPressed: () => onToggleReminder(idx),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onAddPlanPressed,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.accent.primary,
                              theme.accent.secondary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: theme.accent.primary.withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_circle_outline,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.t(context, 'calendar_add_plan'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80), // Padding
      ],
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap, dynamic theme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: theme.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: theme.textPrimary),
      ),
    );
  }

  int _daysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  int getAllPlansCount() {
    int total = 0;
    for (var l in allPlansData.values) {
      total += l.length;
    }
    return total;
  }
}

// ==========================================
// ADD PLAN MODAL
// ==========================================
class AddPlanModal extends StatefulWidget {
  final Function(PlanItem) onPlanSaved;
  final Function(String, IconData) onChatOpened;

  const AddPlanModal({
    super.key,
    required this.onPlanSaved,
    required this.onChatOpened,
  });

  @override
  State<AddPlanModal> createState() => _AddPlanModalState();
}

class _AddPlanModalState extends State<AddPlanModal> {
  final List<Map<String, dynamic>> _buttons = [
    {
      'name': 'Gym',
      'icon': Icons.fitness_center,
      'key': 'calendar_occasion_gym',
    },
    {
      'name': 'Office',
      'icon': Icons.work_outline,
      'key': 'calendar_occasion_office',
    },
    {
      'name': 'Party',
      'icon': Icons.celebration,
      'key': 'calendar_occasion_party',
    },
    {
      'name': 'Shopping',
      'icon': Icons.shopping_bag_outlined,
      'key': 'calendar_occasion_shopping',
    },
    {
      'name': 'Study',
      'icon': Icons.menu_book,
      'key': 'calendar_occasion_study',
    },
    {
      'name': 'Travel',
      'icon': Icons.flight_takeoff,
      'key': 'calendar_occasion_travel',
    },
    {'name': 'Event', 'icon': Icons.event, 'key': 'calendar_occasion_event'},
    {
      'name': 'Date Night',
      'icon': Icons.favorite_border,
      'key': 'calendar_occasion_date_night',
    },
  ];

  final String _selectedOccasion = 'Gym';

  @override
  Widget build(BuildContext context) {
    final theme = context.themeTokens;
    return Container(
      decoration: BoxDecoration(
        color: theme.backgroundSecondary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.textPrimary.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.t(context, 'calendar_new_plan'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 14, color: theme.mutedText),
                      SizedBox(width: 4),
                      Text(
                        AppLocalizations.t(context, 'calendar_close'),
                        style: TextStyle(
                          color: theme.mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Occasions grid
          Text(
            AppLocalizations.t(context, 'calendar_choose_occasion'),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: theme.mutedText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buttons.map((b) {
              bool isSel = _selectedOccasion == b['name'];
              return GestureDetector(
                onTap: () {
                  widget.onChatOpened(
                    b['name'] as String,
                    b['icon'] as IconData,
                  );
                },
                child: Container(
                  width: (MediaQuery.of(context).size.width - 40 - 24) / 4,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel
                        ? theme.accent.primary.withValues(alpha: 0.2)
                        : theme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSel ? theme.accent.primary : theme.cardBorder,
                    ),
                    boxShadow: isSel
                        ? [
                            BoxShadow(
                              color: theme.accent.primary.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 12,
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        b['icon'] as IconData,
                        size: 24,
                        color: theme.textPrimary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.t(context, b['key'] as String),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSel ? theme.accent.primary : theme.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ==========================================
// CHAT SCREEN
// ==========================================
class ChatMessage {
  final String text;
  final bool isUser;
  final String time;
  final List<AhviChip> chips;
  final AhviVisualBoard? visualBoard;
  final AhviModuleCard? moduleCard;
  final CalendarPlanPack? planPack;
  ChatMessage(
    this.text, {
    required this.isUser,
    required this.time,
    this.chips = const [],
    this.visualBoard,
    this.moduleCard,
    this.planPack,
  });
}

class StyleChatScreen extends StatefulWidget {
  final String occasion;
  final IconData icon;
  final VoidCallback onBack;
  final Future<void> Function(String route) onOpenRoute;
  final Future<void> Function(Map<String, dynamic>) onCalendarMutation;
  final BackendService? backend;

  const StyleChatScreen({
    super.key,
    required this.occasion,
    required this.icon,
    required this.onBack,
    required this.onOpenRoute,
    required this.onCalendarMutation,
    this.backend,
  });

  @override
  State<StyleChatScreen> createState() => _StyleChatScreenState();
}

class _StyleChatScreenState extends State<StyleChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final List<ChatMessage> _msgs = [];
  final CalendarActionCoordinator _actionCoordinator =
      CalendarActionCoordinator();
  bool _isListening = false;
  String? _lastDraftPlan;
  String? _lastDraftTime;

  bool _greetingAdded = false;
  BackendService get _backend => widget.backend ?? BackendService();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_greetingAdded) {
      _greetingAdded = true;
      _msgs.add(
        ChatMessage(
          AppLocalizations.t(
            context,
            'calendar_chat_greeting',
          ).replaceAll('{occasion}', widget.occasion),
          isUser: false,
          time: AppLocalizations.t(context, 'calendar_chat_time_now'),
        ),
      );
    }
  }

  // Helper to extract time
  String _extractTime(String text) {
    final match = RegExp(
      r"\b(\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.|o'clock)?)\b",
      caseSensitive: false,
    ).firstMatch(text);
    return match != null ? match.group(1) ?? "" : "";
  }

  String _responseText(Map<String, dynamic> response) {
    final rawMessage = response['message'];
    return (response['message_text'] ??
            (rawMessage is Map ? rawMessage['content'] : rawMessage) ??
            '')
        .toString()
        .trim();
  }

  String _summaryFromAhvi(AhviResponse parsed) {
    final sections = parsed.prepSections.isNotEmpty
        ? parsed.prepSections
        : parsed.planSections;
    final lines = <String>[];
    for (final section in sections.take(3)) {
      if (section.title.trim().isNotEmpty) lines.add(section.title.trim());
      lines.addAll(section.items.take(3));
    }
    if (lines.isNotEmpty) return lines.join(' • ');
    if (parsed.checklistItems.isNotEmpty) {
      return parsed.checklistItems.take(5).join(' • ');
    }
    return parsed.messageText;
  }

  List<AhviChip> _calendarChipsFor(AhviResponse parsed) {
    final chips = parsed.chips.map((chip) {
      final action = calendarQuickActionFor(
        value: chip.value,
        label: chip.label,
      );
      return action == null
          ? chip
          : AhviChip(label: action.label, value: action.id);
    }).toList();
    final hasStructuredPlan =
        parsed.isPlan ||
        parsed.isPrep ||
        parsed.planSections.isNotEmpty ||
        parsed.prepSections.isNotEmpty ||
        parsed.checklistItems.isNotEmpty;
    if (hasStructuredPlan) {
      chips.addAll(const [
        AhviChip(label: 'Save to calendar', value: 'calendar_save_draft'),
        AhviChip(label: 'Add prep', value: 'calendar_add_prep'),
        AhviChip(label: 'Build outfit', value: 'calendar_build_outfit'),
      ]);
    }
    final seen = <String>{};
    return chips.where((chip) => seen.add(chip.label)).take(3).toList();
  }

  Future<void> _handleChip(AhviChip chip) async {
    final action = calendarQuickActionFor(
      value: chip.value,
      label: chip.label,
    );
    if (action != null) {
      await _actionCoordinator.dispatch(
        action,
        navigate: (route) async {
          await widget.onOpenRoute(route);
          debugPrint(
            'AHVI_CALENDAR_ACTION action=view_events '
            'outcome=navigated route=$route',
          );
        },
        requestPlan: (requestedAction) async {
          debugPrint(
            'AHVI_CALENDAR_ACTION '
            'action=${requestedAction == CalendarQuickAction.prepTomorrow ? 'prep_tomorrow' : 'plan_day'} '
            'outcome=requested',
          );
          await _sendMsg(action: requestedAction);
        },
      );
      return;
    }
    if (chip.value == 'calendar_save_draft') {
      final plan = _lastDraftPlan;
      if (plan == null || plan.trim().isEmpty) return;
      _textCtrl.text = 'Save to calendar at ${_lastDraftTime ?? '9:00 AM'}: $plan';
      await _sendMsg();
      return;
    }
    _textCtrl.text = chip.value;
    await _sendMsg();
  }

  Future<void> _sendMsg({CalendarQuickAction? action}) async {
    if (action == null && _textCtrl.text.trim().isEmpty) return;

    final userText = action?.label ?? _textCtrl.text;
    final lower = userText.toLowerCase();
    final attemptedSave = lower.contains('yes') ||
        lower.contains('save') ||
        lower.contains('add');
    var calendarMutationApplied = false;
    setState(() {
      _msgs.add(
        ChatMessage(
          userText,
          isUser: true,
          time: AppLocalizations.t(context, 'calendar_chat_time_now'),
        ),
      );
      _textCtrl.clear();
    });

    String reply = '';
    List<AhviChip> responseChips = const [];
    try {
      final actionRequest = action == null
          ? null
          : calendarActionRequest(action, occasion: widget.occasion);
      final response = await _backend.sendModuleChat(
        domain: 'calendar',
        message:
            actionRequest?.message ?? 'Occasion: ${widget.occasion}\n\n$userText',
        context: actionRequest?.context,
        chatHistory: _msgs
            .map(
              (m) => <String, String>{
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              },
            )
            .toList(),
      );
      final mutation = CalendarMutationResult.tryParse(response);
      if (mutation != null) {
        await widget.onCalendarMutation(response);
        calendarMutationApplied = true;
      }

      final openRoute = calendarOpenModuleRoute(response);
      if (openRoute != null) {
        final normalizedRoute = normalizeCalendarRoute(openRoute);
        if (normalizedRoute == null) {
          debugPrint(
            'AHVI_CALENDAR_ACTION action=open_module '
            'outcome=ignored route=$openRoute',
          );
        } else {
          await _actionCoordinator.dispatch(
            CalendarQuickAction.viewEvents,
            navigate: (route) async {
              await widget.onOpenRoute(route);
              debugPrint(
                'AHVI_CALENDAR_ACTION action=view_events '
                'outcome=navigated route=$route',
              );
            },
            requestPlan: (_) async {},
          );
          if (!mounted) return;
        }
      }

      final planPack = CalendarPlanPack.tryParse(
        response,
        requestedAction: action,
      );
      if (planPack != null) {
        if (action == CalendarQuickAction.planDay) {
          // The backend currently exposes one plan_pack capability. Keep the
          // requested day-plan identity and title distinct in the frontend.
          debugPrint(
            'AHVI_CALENDAR_PLAN_CAPABILITY requested=day_plan '
            'backend_intent=plan_pack',
          );
        }
        debugPrint('AHVI_CALENDAR_PLAN_OK plan_type=${planPack.planType}');
        if (!mounted) return;
        setState(() {
          _msgs.add(
            ChatMessage(
              _responseText(response).isNotEmpty
                  ? _responseText(response)
                  : planPack.title,
              isUser: false,
              time: AppLocalizations.t(context, 'calendar_chat_time_now'),
              planPack: planPack,
            ),
          );
        });
        return;
      }

      // Module summary card response (medicines / bills / events / etc).
      if (AhviModuleCard.isModuleCard(response)) {
        final card = AhviModuleCard.fromResponse(response);
        if (card != null) {
          if (!mounted) return;
          setState(() {
            _msgs.add(
              ChatMessage(
                card.summary.isEmpty ? card.title : card.summary,
                isUser: false,
                time: AppLocalizations.t(context, 'calendar_chat_time_now'),
                moduleCard: card,
              ),
            );
          });
          return;
        }
      }

      // Visual board response — render the structured plan board.
      if (AhviVisualBoard.isVisualBoard(response)) {
        final board = AhviVisualBoard.fromJson(response);
        if (!mounted) return;
        setState(() {
          _msgs.add(
            ChatMessage(
              board.title.isEmpty ? 'Here is your plan.' : board.title,
              isUser: false,
              time: AppLocalizations.t(context, 'calendar_chat_time_now'),
              visualBoard: board,
            ),
          );
        });
        return;
      }

      final parsed = AhviResponse.fromMap(response);
      reply = parsed.messageText.isNotEmpty
          ? parsed.messageText
          : _responseText(response);
      responseChips = _calendarChipsFor(parsed);
      final summary = _summaryFromAhvi(parsed);
      if (summary.trim().isNotEmpty) {
        _lastDraftPlan = summary;
        _lastDraftTime = _extractTime(reply).isNotEmpty
            ? _extractTime(reply)
            : (_extractTime(userText).isNotEmpty
                  ? _extractTime(userText)
                  : _lastDraftTime);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      final extractedTime = _extractTime(userText);
      if (calendarMutationApplied) {
        reply = reply.isNotEmpty ? reply : 'Saved it to your calendar.';
      } else if (attemptedSave) {
        reply = "I couldn't confirm that calendar event. Please try again.";
      } else if (extractedTime.isNotEmpty) {
        reply = reply.isNotEmpty
            ? reply
            : AppLocalizations.t(context, 'calendar_chat_suggest_save');
      } else {
        reply = reply.isNotEmpty
            ? reply
            : AppLocalizations.t(context, 'calendar_chat_suggest_save');
      }
      _msgs.add(
        ChatMessage(
          reply,
          isUser: false,
          time: AppLocalizations.t(context, 'calendar_chat_time_now'),
          chips: responseChips,
        ),
      );
    });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await AhviSpeechService.instance.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (mounted) setState(() => _isListening = true);
    await AhviSpeechService.instance.start(
      onText: (text) {
        if (!mounted) return;
        setState(() {
          _textCtrl.text = text;
          _textCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _textCtrl.text.length),
          );
        });
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted && !AhviSpeechService.instance.isListening) {
      setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    if (_isListening) {
      AhviSpeechService.instance.cancel();
    }
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeTokens;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Container(
        color: theme.backgroundSecondary,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: widget.onBack,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.card,
                        border: Border.all(color: theme.cardBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: Icon(
                          Icons.arrow_back_ios,
                          size: 18,
                          color: theme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.occasion} ${AppLocalizations.t(context, 'calendar_chat')}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 5, bottom: 4),
                          width: 36,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: theme.accent.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: theme.accent.tertiary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.accent.tertiary,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.t(
                                context,
                                'calendar_chat_subtitle',
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Chat list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                itemCount: _msgs.length,
                itemBuilder: (ctx, i) {
                  final m = _msgs[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: m.isUser
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!m.isUser)
                          Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: theme.card,
                              border: Border.all(color: theme.cardBorder),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              widget.icon,
                              size: 14,
                              color: theme.textPrimary,
                            ),
                          ),

                        Flexible(
                          child: Column(
                            crossAxisAlignment: m.isUser
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                            Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.7,
                              ),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.card,
                                border: Border.all(color: theme.cardBorder),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(
                                    m.isUser ? 18 : 5,
                                  ),
                                  bottomRight: Radius.circular(
                                    m.isUser ? 5 : 18,
                                  ),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                m.text,
                                style: TextStyle(
                                  color: theme.textPrimary,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 4,
                                left: 4,
                                right: 4,
                              ),
                              child: Text(
                                m.time,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.mutedText,
                                ),
                              ),
                            ),
                            if (!m.isUser && m.chips.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: m.chips
                                        .map(
                                          (chip) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: _chip(
                                              chip.label,
                                              theme,
                                              onTap: () => _handleChip(chip),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            if (!m.isUser && m.visualBoard != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.82,
                                  ),
                                  child: AhviVisualBoardView(
                                    board: m.visualBoard!,
                                    surfaceColor: theme.card,
                                    textColor: theme.textPrimary,
                                    mutedColor: theme.mutedText,
                                    borderColor: theme.cardBorder,
                                  ),
                                ),
                              ),
                            if (!m.isUser && m.moduleCard != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.82,
                                  ),
                                  child: AhviModuleCardView(
                                    card: m.moduleCard!,
                                    surfaceColor: theme.card,
                                    textColor: theme.textPrimary,
                                    mutedColor: theme.mutedText,
                                    borderColor: theme.cardBorder,
                                  ),
                                ),
                              ),
                            if (!m.isUser && m.planPack != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _planPackView(m.planPack!, theme),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Input bar
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
              child: Column(
                children: [
                  // Suggestion Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(
                          AppLocalizations.t(context, 'calendar_chip_wear'),
                          theme,
                        ),
                        _chip(
                          AppLocalizations.t(context, 'calendar_chip_casual'),
                          theme,
                        ),
                        _chip(
                          AppLocalizations.t(context, 'calendar_chip_work'),
                          theme,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.card,
                      border: Border.all(color: theme.cardBorder),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, color: theme.mutedText, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _textCtrl,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: AppLocalizations.t(
                                context,
                                'calendar_chat_input_hint',
                              ),
                              hintStyle: TextStyle(color: theme.mutedText),
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.textPrimary,
                            ),
                            onSubmitted: (_) => _sendMsg(),
                          ),
                        ),
                        GestureDetector(
                          onTap: _toggleListening,
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: _isListening
                                  ? theme.accent.primary
                                  : theme.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: theme.cardBorder),
                            ),
                            child: Icon(
                              Icons.mic,
                              size: 16,
                              color: _isListening
                                  ? Colors.white
                                  : theme.accent.secondary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _sendMsg,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.accent.secondary,
                                  theme.accent.tertiary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.send,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planPackView(CalendarPlanPack plan, dynamic theme) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.card,
        border: Border.all(color: theme.cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.title,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final section in plan.sections) ...[
            const SizedBox(height: 10),
            Text(
              section.title,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final item in section.items)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '- $item',
                  style: TextStyle(color: theme.mutedText, fontSize: 12.5),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String txt, dynamic theme, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap:
          onTap ??
          () {
            _textCtrl.text = txt;
            _sendMsg();
          },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: theme.card,
          border: Border.all(color: theme.cardBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          txt,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
      ),
    );
  }
}

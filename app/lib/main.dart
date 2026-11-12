import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/domain/models.dart';
import 'src/state/providers.dart';
import 'src/ui/common.dart';
import 'src/ui/detail_sheet.dart';
import 'src/ui/views/genre_agenda_view.dart';
import 'src/ui/views/my_week_view.dart';
import 'src/ui/views/studio_columns_view.dart';

void main() {
  runApp(const ProviderScope(child: NYCStudioCalendarApp()));
}

enum CalendarViewType {
  genreAgenda('Genre Agenda', Icons.view_agenda_outlined),
  studioColumns('Studio Columns', Icons.view_column_outlined),
  myWeek('My Regimen', Icons.bookmark_added_outlined);

  const CalendarViewType(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ActiveViewNotifier extends Notifier<CalendarViewType> {
  @override
  CalendarViewType build() => CalendarViewType.genreAgenda;

  void select(CalendarViewType view) => state = view;
}

final activeViewProvider =
    NotifierProvider<ActiveViewNotifier, CalendarViewType>(ActiveViewNotifier.new);

class NYCStudioCalendarApp extends StatelessWidget {
  const NYCStudioCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NYC Solo Dance Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC62828),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC62828),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const CalendarHomeScreen(),
    );
  }
}

class CalendarHomeScreen extends ConsumerWidget {
  const CalendarHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeView = ref.watch(activeViewProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final today = ref.watch(todayProvider);
    final theme = Theme.of(context);
    final isNextWeek = selectedDate.compareTo(today.startOfWeek.addDays(6)) > 0;
    final isToday = selectedDate == today;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NYC Solo Dance Calendar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Row(
              children: [
                Text(
                  '${formatDate(selectedDate)} (${isEasternDst() ? "EDT" : "EST"})',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isNextWeek
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isNextWeek ? 'Next Week' : 'This Week',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isNextWeek
                          ? theme.colorScheme.onTertiaryContainer
                          : theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (!isToday)
            TextButton(
              onPressed: () =>
                  ref.read(selectedDateProvider.notifier).select(today),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Today', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          IconButton(
            icon: const Icon(Icons.repeat),
            tooltip: 'Beginner Workshop Series',
            onPressed: () => showSeriesList(context),
          ),
          PopupMenuButton<CalendarViewType>(
            icon: const Icon(Icons.view_carousel_outlined),
            tooltip: 'Switch Prototype View',
            initialValue: activeView,
            onSelected: (view) =>
                ref.read(activeViewProvider.notifier).select(view),
            itemBuilder: (context) => [
              for (final view in CalendarViewType.values)
                PopupMenuItem(
                  value: view,
                  child: Row(
                    children: [
                      Icon(view.icon, size: 20),
                      const SizedBox(width: 8),
                      Text(view.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: const [
              WeekStrip(),
              FilterRail(),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (activeView) {
          CalendarViewType.genreAgenda => const GenreAgendaView(
              key: ValueKey('genre_agenda'),
            ),
          CalendarViewType.studioColumns => const StudioColumnsView(
              key: ValueKey('studio_columns'),
            ),
          CalendarViewType.myWeek => const MyWeekView(
              key: ValueKey('my_week'),
            ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeView.index,
        onDestinationSelected: (idx) {
          ref.read(activeViewProvider.notifier).select(
                CalendarViewType.values[idx],
              );
        },
        destinations: [
          for (final view in CalendarViewType.values)
            NavigationDestination(
              icon: Icon(view.icon),
              label: view.label,
            ),
        ],
      ),
    );
  }
}

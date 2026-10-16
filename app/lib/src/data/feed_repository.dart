import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'database/app_database.dart';
import 'mock_feed.dart';

class FeedRepository {
  FeedRepository({this.database});

  final AppDatabase? database;

  Future<MockFeed> loadFeed() async {
    try {
      final assetJsonStr = await rootBundle.loadString('assets/feed/schedule.json');
      String jsonStr = assetJsonStr;

      if (database != null) {
        final cachedJsonStr = await database!.getFeedJson('latest');
        if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
          try {
            final cachedData = json.decode(cachedJsonStr) as Map<String, dynamic>;
            final assetData = json.decode(assetJsonStr) as Map<String, dynamic>;
            final cachedGen = DateTime.tryParse(cachedData['generatedAt'] as String? ?? '');
            final assetGen = DateTime.tryParse(assetData['generatedAt'] as String? ?? '');

            if (cachedGen != null && assetGen != null && cachedGen.isAfter(assetGen)) {
              jsonStr = cachedJsonStr;
            } else {
              // Asset is newer or updated: persist to SQLite cache
              await database!.saveFeedJson('latest', assetJsonStr);
              jsonStr = assetJsonStr;
            }
          } catch (_) {
            jsonStr = assetJsonStr;
          }
        } else {
          await database!.saveFeedJson('latest', assetJsonStr);
        }
      }

      final data = json.decode(jsonStr) as Map<String, dynamic>;

      final today = ServiceDate.fromDateTime(DateTime.now());
      final currentMonday = today.startOfWeek;
      final rawWindowStart = data['windowStart'] as String?;
      final parsedWindowStart = rawWindowStart != null
          ? ServiceDate.parse(rawWindowStart)
          : currentMonday;
      // Anchor windowStart to current week's Monday if feed windowStart was earlier
      final windowStart = parsedWindowStart.compareTo(currentMonday) < 0
          ? currentMonday
          : parsedWindowStart;

      // Parse and register all templates from feed (curated + dynamically classified)
      final rawTemplates = data['templates'] as List<dynamic>? ?? [];
      final parsedTemplates = rawTemplates.map((item) {
        final m = item as Map<String, dynamic>;
        final studioKey = m['studioId'] as String;
        final studioId = StudioId.values.firstWhere(
          (s) => s.name == studioKey,
          orElse: () => StudioId.bdc,
        );

        final tierKey = m['tier'] as String? ?? 'beginner';
        final tier = Tier.values.firstWhere(
          (t) => t.name == tierKey,
          orElse: () => Tier.beginner,
        );

        final genreKey = m['primaryGenre'] as String? ?? 'hipHopStreet';
        final primaryGenre = Genre.values.firstWhere(
          (g) => g.name == genreKey,
          orElse: () => Genre.hipHopStreet,
        );

        final rawSlots = m['slots'] as List<dynamic>? ?? [];
        final slots = rawSlots.map((s) {
          final sm = s as Map<String, dynamic>;
          return TemplateSlot(
            weekday: sm['weekday'] as int? ?? 1,
            startMin: sm['startMin'] as int? ?? 600,
            durationMin: sm['durationMin'] as int? ?? 90,
            regularInstructor: sm['regularInstructor'] as String? ?? 'Staff',
          );
        }).toList();

        return ClassTemplate(
          id: m['id'] as String,
          studioId: studioId,
          title: m['title'] as String,
          rawLevelLabel: m['rawLevelLabel'] as String? ?? 'BEGINNER',
          tier: tier,
          primaryGenre: primaryGenre,
          slots: slots,
          description: m['description'] as String? ?? '',
          prerequisiteNotes: m['prerequisiteNotes'] as String?,
          attireNotes: m['attireNotes'] as String?,
          catalogUrl: m['catalogUrl'] as String? ?? '',
        );
      }).toList();

      registerTemplates(parsedTemplates);

      // Parse sessions
      final rawSessions = data['sessions'] as List<dynamic>? ?? [];
      final sessions = rawSessions.map((item) {
        final m = item as Map<String, dynamic>;
        final studioKey = m['studioId'] as String;
        final studioId = StudioId.values.firstWhere(
          (s) => s.name == studioKey,
          orElse: () => StudioId.bdc,
        );

        final statusStr = m['status'] as String? ?? 'scheduled';
        final status = switch (statusStr) {
          'cancelled' => SessionStatus.cancelled,
          'removed' => SessionStatus.removed,
          _ => SessionStatus.scheduled,
        };

        return ClassSession(
          id: m['id'] as String,
          templateId: m['templateId'] as String,
          studioId: studioId,
          serviceDate: ServiceDate.parse(m['serviceDate'] as String),
          startMin: m['startMin'] as int,
          endMin: m['endMin'] as int,
          tz: m['tz'] as String? ?? 'America/New_York',
          instructor: m['instructor'] as String,
          isSubstitute: m['isSubstitute'] as bool? ?? false,
          status: status,
          bookingUrl: m['bookingUrl'] as String,
        );
      }).toList();

      // Parse series
      final rawSeries = data['series'] as List<dynamic>? ?? [];
      final seriesList = rawSeries.map((item) {
        final m = item as Map<String, dynamic>;
        final studioKey = m['studioId'] as String;
        final studioId = StudioId.values.firstWhere(
          (s) => s.name == studioKey,
          orElse: () => StudioId.peridance,
        );

        return WorkshopSeries(
          id: m['id'] as String,
          templateId: m['templateId'] as String,
          studioId: studioId,
          title: m['title'] as String,
          startDate: ServiceDate.parse(m['startDate'] as String),
          sessionCount: m['sessionCount'] as int,
          weekday: m['weekday'] as int,
          startMin: m['startMin'] as int,
          durationMin: m['durationMin'] as int,
          instructor: m['instructor'] as String,
          enrollmentOpen: m['enrollmentOpen'] as bool? ?? true,
          price: m['price'] as String,
          bookingUrl: m['bookingUrl'] as String,
        );
      }).toList();

      return MockFeed.fromData(
        today: today,
        windowStart: windowStart,
        sessions: sessions,
        series: seriesList,
      );
    } catch (_) {
      return MockFeed.build(ServiceDate.fromDateTime(DateTime.now()));
    }
  }
}

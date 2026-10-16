import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'mock_feed.dart';

class FeedRepository {
  Future<MockFeed> loadFeed() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/feed/schedule.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      final windowStart = ServiceDate.parse(data['windowStart'] as String);
      final today = ServiceDate.fromDateTime(DateTime.now());

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
      // Fallback to programmatic mock feed if bundle load fails
      return MockFeed.build(ServiceDate.fromDateTime(DateTime.now()));
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'database/app_database.dart';
import 'mock_feed.dart';

class FeedRepository {
  FeedRepository({
    this.database,
    http.Client? httpClient,
    this.feedUrl,
  }) : httpClient = httpClient ?? http.Client();

  final AppDatabase? database;
  final http.Client httpClient;

  /// Optional remote URL to fetch schedule.json from.
  /// If null, can be overridden via `FEED_URL` compilation define or set directly.
  final String? feedUrl;

  /// Default GitHub Pages URL or environment variable.
  String get effectiveFeedUrl {
    if (feedUrl != null && feedUrl!.isNotEmpty) return feedUrl!;
    const envUrl = String.fromEnvironment('FEED_URL');
    if (envUrl.isNotEmpty) return envUrl;
    // Default fallback or placeholder pointing to GitHub Pages
    return 'https://raw.githubusercontent.com/unchiko/studio-schedules/gh-pages/schedule.json';
  }

  /// Loads the feed using an offline-first strategy:
  /// 1. Reads SQLite cache if present and valid.
  /// 2. Reads bundled asset as fallback or initial seed.
  /// 3. If [fetchRemote] is true, checks remote HTTP endpoint in the background or during refresh.
  Future<MockFeed> loadFeed({bool fetchRemote = true}) async {
    try {
      final assetJsonStr = await rootBundle.loadString('assets/feed/schedule.json');
      final assetData = json.decode(assetJsonStr) as Map<String, dynamic>;
      Map<String, dynamic> data = assetData;

      if (database != null) {
        final cachedJsonStr = await database!.getFeedJson('latest');
        if (cachedJsonStr != null && cachedJsonStr.isNotEmpty) {
          try {
            if (cachedJsonStr == assetJsonStr) {
              data = assetData;
            } else {
              final cachedData = json.decode(cachedJsonStr) as Map<String, dynamic>;
              final cachedGen = DateTime.tryParse(cachedData['generatedAt'] as String? ?? '');
              final assetGen = DateTime.tryParse(assetData['generatedAt'] as String? ?? '');

              if (cachedGen != null && assetGen != null && cachedGen.isAfter(assetGen)) {
                data = cachedData;
              } else {
                // Asset is newer or updated: persist to SQLite cache
                await database!.saveFeedJson('latest', assetJsonStr);
                data = assetData;
              }
            }
          } catch (_) {
            data = assetData;
          }
        } else {
          await database!.saveFeedJson('latest', assetJsonStr);
        }
      }

      // If remote fetching is enabled, attempt to fetch the latest feed from HTTP
      if (fetchRemote) {
        try {
          final remoteData = await fetchRemoteFeed();
          if (remoteData != null) {
            final remoteGen = DateTime.tryParse(remoteData['generatedAt'] as String? ?? '');
            final currentGen = DateTime.tryParse(data['generatedAt'] as String? ?? '');

            if (remoteGen != null && (currentGen == null || remoteGen.isAfter(currentGen))) {
              data = remoteData;
              if (database != null) {
                await database!.saveFeedJson('latest', json.encode(remoteData));
              }
            }
          }
        } catch (e) {
          debugPrint('FeedRepository: Remote fetch failed or skipped, using cached feed: $e');
        }
      }

      return parseFeedData(data);
    } catch (e, st) {
      debugPrint('FeedRepository error loading feed: $e\n$st');
      return MockFeed.build(getTodayInNewYork());
    }
  }

  /// Fetches schedule.json over HTTP. Returns decoded JSON map or null if request fails.
  Future<Map<String, dynamic>?> fetchRemoteFeed() async {
    final urlStr = effectiveFeedUrl;
    if (urlStr.isEmpty) return null;

    final uri = Uri.tryParse(urlStr);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }

    final resp = await httpClient.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'NYCSoloDanceCalendar/1.0',
      },
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode == 200) {
      final decoded = json.decode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded.containsKey('sessions')) {
        return decoded;
      }
    }
    return null;
  }

  /// Parses the raw JSON map into a [MockFeed] and registers templates.
  MockFeed parseFeedData(Map<String, dynamic> data) {
    final today = getTodayInNewYork();
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

      final genreKey = m['primaryGenre'] as String? ?? 'other';
      final primaryGenre = Genre.values.firstWhere(
        (g) => g.name == genreKey,
        orElse: () => Genre.other,
      );

      final rawTags = m['tags'] as List<dynamic>? ?? [];
      final tags = rawTags
          .map((t) => Genre.values.firstWhere(
                (g) => g.name == t.toString(),
                orElse: () => Genre.other,
              ))
          .toSet();

      final rawSlots = m['slots'] as List<dynamic>? ?? [];
      final slots = rawSlots.map((s) {
        final sm = s as Map<String, dynamic>;
        return TemplateSlot(
          weekday: sm['weekday'] as int? ?? 1,
          startMin: sm['startMin'] as int? ?? 600,
          durationMin: sm['durationMin'] as int? ?? 90,
          regularInstructor: unescapeHtml(sm['regularInstructor'] as String? ?? 'Staff'),
        );
      }).toList();

      return ClassTemplate(
        id: m['id'] as String,
        studioId: studioId,
        title: unescapeHtml(m['title'] as String),
        rawLevelLabel: m['rawLevelLabel'] as String? ?? 'BEGINNER',
        tier: tier,
        primaryGenre: primaryGenre,
        tags: tags,
        slots: slots,
        description: unescapeHtml(m['description'] as String? ?? ''),
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

      final rawDesc = m['description'] as String?;
      return ClassSession(
        id: m['id'] as String,
        templateId: m['templateId'] as String,
        studioId: studioId,
        serviceDate: ServiceDate.parse(m['serviceDate'] as String),
        startMin: m['startMin'] as int,
        endMin: m['endMin'] as int,
        tz: m['tz'] as String? ?? 'America/New_York',
        instructor: unescapeHtml(m['instructor'] as String),
        description: rawDesc != null ? unescapeHtml(rawDesc) : null,
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
        title: unescapeHtml(m['title'] as String),
        startDate: ServiceDate.parse(m['startDate'] as String),
        sessionCount: m['sessionCount'] as int,
        weekday: m['weekday'] as int,
        startMin: m['startMin'] as int,
        durationMin: m['durationMin'] as int,
        instructor: unescapeHtml(m['instructor'] as String),
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
  }

  /// Decodes common HTML entities (e.g. `&quot;`, `&#039;`, `&amp;`) into readable characters.
  static String unescapeHtml(String text) {
    if (!text.contains('&')) return text;
    var result = text
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    if (result.contains('&#')) {
      result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        final code = int.tryParse(match.group(1)!);
        return code != null ? String.fromCharCode(code) : match.group(0)!;
      });
      result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
        final code = int.tryParse(match.group(1)!, radix: 16);
        return code != null ? String.fromCharCode(code) : match.group(0)!;
      });
    }
    return result.replaceAll('&amp;', '&');
  }
}

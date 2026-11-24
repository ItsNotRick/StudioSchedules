import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/data/feed_repository.dart';
import 'package:nyc_dance_calendar/src/domain/teachers.dart';

/// The bundled feed's alias map must agree with its session keys after the
/// client's own parsing (HTML unescaping, normalization).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled feed: alias map resolves every session to its instructorKey', () async {
    final feed = await FeedRepository().loadFeed(fetchRemote: false);
    expect(feed.instructorAliases, isNotEmpty, reason: 'bundled feed should be v1.1+');
    expect(feed.placeholderInstructors, contains('staff'));

    final aliasOnly = TeacherResolver.build(
      aliases: feed.instructorAliases,
      sessions: const [],
      placeholders: feed.placeholderInstructors,
    );
    final mismatches = [
      for (final s in feed.sessions)
        if (s.instructorKey == null || aliasOnly.keyFor(s.instructor) != s.instructorKey)
          '${s.instructor} -> ${aliasOnly.keyFor(s.instructor)} (feed: ${s.instructorKey})',
    ];
    expect(mismatches, isEmpty);

    final full = TeacherResolver.build(aliases: feed.instructorAliases, sessions: feed.sessions);
    for (final s in feed.sessions) {
      expect(full.keyFor(s.instructor), s.matchKey);
    }
  });
}

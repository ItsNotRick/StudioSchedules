import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';

/// normalizeInstructor() must match normalize_instructor() in
/// backend/src/instructor_names.py. Both sides check this shared fixture.
void main() {
  test('normalizeInstructor matches the shared backend fixture', () {
    // `flutter test` runs with app/ as the working directory.
    final file = File('../backend/tests/fixtures/instructor_names.json');
    final cases = (jsonDecode(file.readAsStringSync())['cases'] as List)
        .cast<List<dynamic>>();
    expect(cases, isNotEmpty);
    for (final c in cases) {
      final raw = c[0] as String;
      final expected = c[1] as String;
      expect(normalizeInstructor(raw), expected, reason: 'raw: ${jsonEncode(raw)}');
    }
  });
}

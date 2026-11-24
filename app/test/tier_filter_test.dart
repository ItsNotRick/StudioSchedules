import 'package:flutter_test/flutter_test.dart';
import 'package:nyc_dance_calendar/src/domain/models.dart';
import 'package:nyc_dance_calendar/src/state/providers.dart';

void main() {
  final base = FilterState(studios: StudioId.values.toSet(), genres: const {});

  test('no tier selected accepts every tier', () {
    for (final t in Tier.values) {
      expect(base.acceptsTier(t), isTrue);
    }
  });

  test('selected tiers narrow results; All levels is its own tier', () {
    final f = base.copyWith(tiers: {Tier.beginner});
    expect(f.acceptsTier(Tier.beginner), isTrue);
    expect(f.acceptsTier(Tier.allLevels), isFalse);
    expect(base.copyWith(tiers: {Tier.allLevels}).acceptsTier(Tier.allLevels),
        isTrue);
    expect(f.acceptsTier(Tier.advanced), isFalse);
    expect(f.acceptsTier(Tier.zeroExperience), isFalse);
  });
}

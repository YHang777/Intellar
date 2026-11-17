import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/lighting_preset.dart';

void main() {
  test('four presets cover day to night with sane light values', () {
    expect(LightingPreset.values, hasLength(4));
    for (final p in LightingPreset.values) {
      expect(p.color, hasLength(3));
      for (final c in p.color) {
        expect(c, inInclusiveRange(0, 1));
      }
      expect(p.keyScale, greaterThan(0));
      expect(p.fillScale, greaterThan(0));
      expect(p.direction, hasLength(3));
    }
    expect(LightingPreset.daylight.keyScale,
        greaterThan(LightingPreset.night.keyScale),
        reason: 'night must be dimmer than day');
    expect(LightingPreset.evening.color[0], greaterThan(LightingPreset.evening.color[1]),
        reason: 'evening light is warm (more red than green)');
  });

  test('args map carries what the native side needs', () {
    final args = LightingPreset.warm.toArgs();
    expect(args['color'], [1.0, 0.8, 0.58]);
    expect(args['keyScale'], 0.75);
    expect(args['fillScale'], 0.7);
    expect(args['direction'], [-0.3, -1.4, -0.6]);
  });

  test('fromName falls back to daylight for unknown or null', () {
    expect(LightingPreset.fromName('night'), LightingPreset.night);
    expect(LightingPreset.fromName('nope'), LightingPreset.daylight);
    expect(LightingPreset.fromName(null), LightingPreset.daylight);
    for (final p in LightingPreset.values) {
      expect(LightingPreset.fromName(p.name), p);
    }
  });
}

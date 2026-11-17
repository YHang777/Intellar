import 'package:flutter/material.dart';

// Lighting scenarios for the 3D planner and walkthrough (report FR13): the
// key light's colour and strength plus the ambient fill, as multipliers on
// the studio defaults. [overlay] tints the painter fallback the same way.
enum LightingPreset {
  daylight(
    label: 'Daylight',
    icon: Icons.wb_sunny_outlined,
    color: [1.0, 0.98, 0.95],
    keyScale: 1.15,
    fillScale: 1.1,
    direction: [-0.45, -1.3, -0.95],
    overlay: Color(0x00000000),
  ),
  warm(
    label: 'Warm lamps',
    icon: Icons.light_outlined,
    color: [1.0, 0.8, 0.58],
    keyScale: 0.75,
    fillScale: 0.7,
    direction: [-0.3, -1.4, -0.6],
    overlay: Color(0x22FF9A3C),
  ),
  evening(
    label: 'Evening',
    icon: Icons.wb_twilight_outlined,
    color: [1.0, 0.62, 0.38],
    keyScale: 0.5,
    fillScale: 0.45,
    direction: [-1.2, -0.45, -0.6],
    overlay: Color(0x33FF6A1F),
  ),
  night(
    label: 'Night',
    icon: Icons.nightlight_outlined,
    color: [0.58, 0.68, 1.0],
    keyScale: 0.15,
    fillScale: 0.22,
    direction: [-0.2, -1.5, -0.3],
    overlay: Color(0x66101A3A),
  );

  const LightingPreset({
    required this.label,
    required this.icon,
    required this.color,
    required this.keyScale,
    required this.fillScale,
    required this.direction,
    required this.overlay,
  });

  final String label;
  final IconData icon;
  final List<double> color;
  final double keyScale;
  final double fillScale;
  final List<double> direction;
  final Color overlay;

  Map<String, Object?> toArgs() => {
        'color': color,
        'keyScale': keyScale,
        'fillScale': fillScale,
        'direction': direction,
      };

  static LightingPreset fromName(String? name) => LightingPreset.values
      .firstWhere((p) => p.name == name, orElse: () => LightingPreset.daylight);
}

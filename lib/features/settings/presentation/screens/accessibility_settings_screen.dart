import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/accessibility/accessibility_settings.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/settings_widgets.dart';

class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    final notifier = ref.read(accessibilitySettingsProvider.notifier);
    return SettingsPage(
      title: 'Accessibility',
      subtitle: 'Make the app easier to read',
      children: [
        SettingsCard(
          title: 'Text size',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SegmentedButton<TextSizeOption>(
                key: const Key('text-size-selector'),
                showSelectedIcon: false,
                segments: [
                  for (final o in TextSizeOption.values)
                    ButtonSegment(value: o, label: Text(o.label)),
                ],
                selected: {settings.textSize},
                onSelectionChanged: (s) =>
                    notifier.patch((c) => c.copyWith(textSize: s.first)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Preview: Scandinavian oak sofa, RM 1,299',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        SettingsCard(
          title: 'Display',
          children: [
            SettingsSwitchTile(
              key: const Key('high-contrast-switch'),
              icon: Icons.contrast,
              title: 'High contrast',
              subtitle: 'Darker secondary text and stronger outlines',
              value: settings.highContrast,
              onChanged: (v) =>
                  notifier.patch((c) => c.copyWith(highContrast: v)),
            ),
            SettingsSwitchTile(
              key: const Key('bold-text-switch'),
              icon: Icons.format_bold,
              title: 'Bold text',
              subtitle: 'Heavier letters across the app',
              value: settings.boldText,
              onChanged: (v) => notifier.patch((c) => c.copyWith(boldText: v)),
            ),
          ],
        ),
        Text(
          'These settings apply on this phone and work alongside your '
          'system font size.',
          style: GoogleFonts.poppins(
              fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../data/lighting_preset.dart';

// One lighting choice for the session, shared by the planner's 3D view and
// the walkthrough so switching screens keeps the same scene mood.
final lightingPresetProvider =
    StateProvider<LightingPreset>((ref) => LightingPreset.daylight);

Future<void> showLightingSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final current = ref.watch(lightingPresetProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Preview lighting',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'See how your room looks at different times of day.',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (final p in LightingPreset.values)
                  ListTile(
                    key: Key('lighting-${p.name}'),
                    leading: Icon(p.icon,
                        color: p == current
                            ? AppColors.accent
                            : AppColors.textSecondary),
                    title: Text(p.label,
                        style: GoogleFonts.poppins(
                            fontWeight: p == current
                                ? FontWeight.w600
                                : FontWeight.w400)),
                    trailing: p == current
                        ? const Icon(Icons.check, color: AppColors.accent)
                        : null,
                    onTap: () {
                      ref.read(lightingPresetProvider.notifier).state = p;
                      Navigator.of(ctx).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class LightingButton extends ConsumerWidget {
  const LightingButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(lightingPresetProvider);
    return IconButton(
      key: const Key('lighting-button'),
      tooltip: 'Lighting: ${preset.label}',
      icon: Icon(preset.icon),
      onPressed: () => showLightingSheet(context, ref),
    );
  }
}

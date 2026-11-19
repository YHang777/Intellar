import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../ar/presentation/screens/ar_previews_screen.dart';

// FR19: the dashboard shows saved AR previews alongside designs, purchases
// and budget. Hidden until there is at least one, so a new user's dashboard
// carries no empty section.
class DashboardArPreviews extends ConsumerWidget {
  const DashboardArPreviews({super.key});

  static const _maxShown = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previews = ref.watch(arPreviewsProvider).valueOrNull ?? const [];
    if (previews.isEmpty) return const SizedBox.shrink();
    final shown = previews.take(_maxShown).toList();
    return Padding(
      key: const Key('dashboard-ar-previews'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('AR previews',
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
              TextButton(
                onPressed: () => context.push('/ar-previews'),
                child: Text('See all (${previews.length})',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = shown[i];
                return InkWell(
                  onTap: () => context.push('/ar-previews'),
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 84,
                      child: Image.file(
                        File(p.path),
                        fit: BoxFit.cover,
                        semanticLabel: p.label,
                        errorBuilder: (_, __, ___) => ColoredBox(
                          color: AppColors.surfaceContainer,
                          child: Icon(Icons.image_not_supported_outlined,
                              color: AppColors.textHint),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

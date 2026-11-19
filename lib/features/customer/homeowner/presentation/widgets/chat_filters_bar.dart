import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/chat_product_mapper.dart';
import '../../data/chat_state_context.dart';

// FR16: filter AI recommendations by style, budget, eco-friendliness and
// popularity. The assistant only sees products that match, so it cannot
// recommend outside them.
class ChatFiltersBar extends ConsumerWidget {
  const ChatFiltersBar({super.key});

  static const budgets = [200, 500, 1000, 2000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(chatFiltersProvider);
    final notifier = ref.read(chatFiltersProvider.notifier);
    final label = TextStyle(fontSize: 12, color: AppColors.textPrimary);

    Widget active(String text, VoidCallback onClear) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text(text, style: label),
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.accent),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            deleteIcon: const Icon(Icons.close, size: 14),
            onDeleted: onClear,
          ),
        );

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              key: const Key('chat-filters'),
              avatar: Icon(Icons.tune, size: 16, color: AppColors.accent),
              label: Text(
                f.isEmpty ? 'Filter suggestions' : 'Filters (${f.activeCount})',
                style: label.copyWith(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.surface,
              side: BorderSide(color: AppColors.border),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => const _ChatFiltersSheet(),
              ),
            ),
          ),
          if (f.style != null)
            active(f.style!, () => notifier.state = f.copyWith(clearStyle: true)),
          if (f.maxPrice != null)
            active('Up to ${Formatters.myr(f.maxPrice!)}',
                () => notifier.state = f.copyWith(clearMaxPrice: true)),
          if (f.ecoOnly)
            active('Eco-friendly', () => notifier.state = f.copyWith(ecoOnly: false)),
          if (f.popularOnly)
            active('Popular', () => notifier.state = f.copyWith(popularOnly: false)),
        ],
      ),
    );
  }
}

class _ChatFiltersSheet extends ConsumerWidget {
  const _ChatFiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(chatFiltersProvider);
    final notifier = ref.read(chatFiltersProvider.notifier);
    final styles = ref.watch(stylesProvider).valueOrNull ?? const <String>[];
    final heading = GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary);

    Widget choice(String text, bool selected, VoidCallback onTap, Key key) =>
        ChoiceChip(
          key: key,
          label: Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: selected ? Colors.white : AppColors.textPrimary)),
          selected: selected,
          selectedColor: AppColors.accent,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
          showCheckmark: false,
          onSelected: (_) => onTap(),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Filter suggestions',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                if (!f.isEmpty)
                  TextButton(
                    onPressed: () => notifier.state = const ChatFilters(),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            Text('The assistant only suggests pieces that match.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Text('Style', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                choice('Any', f.style == null,
                    () => notifier.state = f.copyWith(clearStyle: true),
                    const Key('chat-style-any')),
                for (final s in styles)
                  choice(s, f.style == s,
                      () => notifier.state = f.copyWith(style: s),
                      Key('chat-style-$s')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Budget per piece', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                choice('Any', f.maxPrice == null,
                    () => notifier.state = f.copyWith(clearMaxPrice: true),
                    const Key('chat-budget-any')),
                for (final b in ChatFiltersBar.budgets)
                  choice('Up to ${Formatters.myr(b)}', f.maxPrice == b,
                      () => notifier.state = f.copyWith(maxPrice: b),
                      Key('chat-budget-$b')),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('chat-eco'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Eco-friendly only'),
              value: f.ecoOnly,
              onChanged: (v) => notifier.state = f.copyWith(ecoOnly: v),
            ),
            SwitchListTile(
              key: const Key('chat-popular'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Popular only'),
              subtitle: const Text('Pieces other buyers already chose'),
              value: f.popularOnly,
              onChanged: (v) => notifier.state = f.copyWith(popularOnly: v),
            ),
          ],
        ),
      ),
    );
  }
}

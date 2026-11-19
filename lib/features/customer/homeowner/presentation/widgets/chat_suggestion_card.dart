import '../../../../../shared/widgets/guest_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/chat_session.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../../notifications/data/product_feedback.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import 'chat_card_actions.dart';

enum _CardOverflow {
  open,
  wishlist,
  qtyPlus,
  qtyMinus,
  remove,
  similar,
}

class ChatSuggestionCard extends ConsumerWidget {
  const ChatSuggestionCard({
    super.key,
    required this.suggestion,
    required this.actions,
    this.showPlace = true,
  });

  final ChatSuggestionSnapshot suggestion;
  final ChatCardActions actions;
  final bool showPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = suggestion;
    final inCart =
        ref.watch(cartProvider).any((item) => item.product.id == s.productId);
    final saved = ref.watch(wishlistProvider).contains(s.productId);
    final verdict = (ref.watch(productFeedbackProvider).valueOrNull ??
        const <String, ProductFeedback>{})[s.productId];
    Future<void> toggle(FeedbackValue value) async {
      if (!await requireAccount(
          context, ref, 'teach the assistant what you like')) {
        return;
      }
      final uid = ref.read(currentUserProvider)?.uid;
      if (uid == null) return;
      final repo = ref.read(productFeedbackRepositoryProvider);
      try {
        if (verdict?.value == value) {
          await repo.clear(uid, s.productId);
        } else {
          await repo.save(uid,
              ProductFeedback(productId: s.productId, value: value, name: s.name));
        }
      } catch (e) {
        // Unawaited, a failed write vanished silently (a missing rule once
        // dropped every verdict unnoticed).
        if (context.mounted) {
          showAppSnackbar(context,
              userMessage(e, fallback: 'Could not save that. Please try again.'),
              isError: true);
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => actions.openProduct(s.productId),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ProductImage(
                    imageUrl: s.image,
                    width: 56,
                    height: 56,
                    errorIconSize: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Formatters.myr(s.price),
                        softWrap: false,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      if (s.reason.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          s.reason,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _VerdictButton(
                tooltip: 'More like this',
                icon: Icons.thumb_up_alt_outlined,
                selectedIcon: Icons.thumb_up_alt,
                selected: verdict?.value == FeedbackValue.like,
                onTap: () => toggle(FeedbackValue.like),
              ),
              _VerdictButton(
                tooltip: 'Not for me',
                icon: Icons.thumb_down_alt_outlined,
                selectedIcon: Icons.thumb_down_alt,
                selected: verdict?.value == FeedbackValue.dislike,
                onTap: () => toggle(FeedbackValue.dislike),
              ),
              TextButton.icon(
                onPressed: () => actions.addToCart(s),
                icon: const Icon(Icons.add_shopping_cart, size: 16),
                label: Text(
                  'Add',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (showPlace)
                TextButton.icon(
                  onPressed: () => actions.placeInLayout(s),
                  icon: const Icon(Icons.weekend_outlined, size: 16),
                  label: Text(
                    'Place',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondaryAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 34),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              PopupMenuButton<_CardOverflow>(
                icon: const Icon(Icons.more_vert, size: 18),
                padding: EdgeInsets.zero,
                tooltip: 'More actions',
                color: AppColors.surface,
                onSelected: (choice) => _onChoice(ref, choice),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _CardOverflow.open,
                    child: Text('Open product'),
                  ),
                  PopupMenuItem(
                    value: _CardOverflow.wishlist,
                    child: Text(
                        saved ? 'Remove from wishlist' : 'Save to wishlist'),
                  ),
                  if (inCart) ...[
                    const PopupMenuItem(
                      value: _CardOverflow.qtyPlus,
                      child: Text('Increase quantity'),
                    ),
                    const PopupMenuItem(
                      value: _CardOverflow.qtyMinus,
                      child: Text('Decrease quantity'),
                    ),
                    const PopupMenuItem(
                      value: _CardOverflow.remove,
                      child: Text('Remove from cart'),
                    ),
                  ] else
                    const PopupMenuItem(
                      value: _CardOverflow.similar,
                      child: Text('See similar'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onChoice(WidgetRef ref, _CardOverflow choice) {
    final s = suggestion;
    switch (choice) {
      case _CardOverflow.open:
        actions.openProduct(s.productId);
      case _CardOverflow.wishlist:
        actions.toggleWishlist(s);
      case _CardOverflow.qtyPlus:
        actions.bumpCartQty(s, 1);
      case _CardOverflow.qtyMinus:
        actions.bumpCartQty(s, -1);
      case _CardOverflow.remove:
        actions.removeFromCart(s);
      case _CardOverflow.similar:
        final category = _categoryOf(ref, s);
        if (category.isNotEmpty) actions.browseCategory(category);
    }
  }

  String _categoryOf(WidgetRef ref, ChatSuggestionSnapshot s) {
    final products = ref.read(marketplaceProductsProvider).valueOrNull;
    for (final p in products ?? const []) {
      if (p.id == s.productId) return p.category;
    }
    return '';
  }
}

// ── Like / dislike on a recommendation (FR17) ──

class _VerdictButton extends StatelessWidget {
  const _VerdictButton({
    required this.tooltip,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textSecondary;
    return IconButton(
      key: Key('verdict-$tooltip'),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(selected ? selectedIcon : icon, size: 17, color: color),
      onPressed: onTap,
    );
  }
}

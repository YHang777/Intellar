import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../models/product.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';

/// Live listings with a discount, biggest saving first.
List<Product> dealsFrom(List<Product> products, {int max = 8}) {
  final deals = [
    for (final p in products)
      if (p.isActive && p.stock > 0 && (p.originalPrice ?? 0) > p.price && p.price > 0) p,
  ]..sort((a, b) => _percentOff(b).compareTo(_percentOff(a)));
  return deals.take(max).toList();
}

int _percentOff(Product p) =>
    ((1 - p.price / (p.originalPrice ?? p.price)) * 100).round();

// FR20 / dashboard "ongoing promotions": what is on sale right now. Hidden
// when nothing is, so the dashboard never shows an empty section.
class DashboardDeals extends ConsumerWidget {
  const DashboardDeals({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const <Product>[];
    final deals = dealsFrom(products);
    if (deals.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('dashboard-deals'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Deals',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: deals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _DealTile(product: deals[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DealTile extends StatelessWidget {
  const _DealTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return InkWell(
      onTap: () => context.push('/marketplace/product/${p.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(product: p, fit: BoxFit.cover),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('-${_percentOff(p)}%',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(Formatters.myr(p.price),
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent)),
                      Text(Formatters.myr(p.originalPrice!),
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textHint,
                              decoration: TextDecoration.lineThrough)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

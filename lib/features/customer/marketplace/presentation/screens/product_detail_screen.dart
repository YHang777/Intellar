import '../../../../../shared/widgets/guest_gate.dart';
import '../../../../../core/utils/input_formatters.dart';
import '../../../../../services/notify/notify_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/product.dart';
import '../../../../../models/store_profile.dart';
import '../../../../../models/weekly_hours.dart';
import '../../../../../models/quote_request.dart';
import '../../../../../models/review.dart';
import '../../../../../services/marketplace_repository.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/product_card.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../../../shared/widgets/image_viewer.dart';
import '../../../../../shared/widgets/quantity_stepper.dart';
import '../../../../../shared/widgets/rating_stars.dart';
import '../../../../../shared/widgets/section_header.dart';
import '../../../../../shared/widgets/verified_badge.dart';
import '../../../../auth/data/models/app_user.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';

import '../providers/marketplace_providers.dart';
import '../widgets/robot_assistant/robot_assistant_host.dart';

const kBulkQuoteMinQty = 5;

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  final PageController _pageCtrl = PageController();
  int _page = 0;
  int _qty = 1;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    // Seller analytics: the backend counts one view per buyer per day and
    // ignores the seller's own visits. Fire-and-forget.
    NotifyClient.instance.productViewed(widget.productId);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchExternal(String url, String unsupportedMessage) async {
    final uri = Uri.parse(url);
    final can = await canLaunchUrl(uri);
    if (!can) {
      if (mounted) showAppSnackbar(context, unsupportedMessage);
      return;
    }
    final ok = await launchUrl(uri);
    if (!ok && mounted) showAppSnackbar(context, unsupportedMessage);
  }

  int _clampedQty(Product product) =>
      product.stock > 0 ? _qty.clamp(1, product.stock) : 1;

  Future<void> _addToCart(Product product) async {
    if (!await requireAccount(context, ref, 'add items to your cart')) return;
    if (!mounted) return;
    final qty = _clampedQty(product);
    ref.read(cartProvider.notifier).addItem(product, qty: qty);
    final message = qty > 1
        ? '${product.name} × $qty added to cart'
        : '${product.name} added to cart';
    showAddedToCartSnack(
      context,
      message,
      onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
    );
  }

  Future<void> _openQuoteDialog(Product product) async {
    if (!await requireAccount(context, ref, 'request a bulk quote')) return;
    if (!mounted) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) {
        showAppSnackbar(context, 'Sign in to request a bulk quote',
            isError: true);
      }
      return;
    }
    final request = await showDialog<QuoteRequest>(
      context: context,
      builder: (_) => _BulkQuoteDialog(
        product: product,
        initialQty: _clampedQty(product),
        user: user,
        onSubmit: (q) async {
          await ref.read(marketplaceRepositoryProvider).createQuoteRequest(q);
          NotifyClient.instance.quoteCreated(q.id);
        },
      ),
    );
    if (!mounted || request == null) return;
    showAppSnackbar(
      context,
      'Quote request sent — the supplier will contact you directly',
      color: AppColors.success,
      duration: const Duration(seconds: 3),
      actionLabel: 'View my quotes',
      onAction: () => context.pushNamed(RouteNames.homeownerOrderHistory),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final isWishlisted =
        ref.watch(wishlistProvider).contains(widget.productId);

    return productsAsync.when(
      loading: () => const _DetailSkeleton(),
      error: (_, __) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: EmptyState(
            icon: Icons.error_outline,
            title: "Couldn't load product",
            subtitle: 'Check your connection and try again',
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(marketplaceProductsProvider),
          ),
        ),
      ),
      data: (products) {
        final product = products
            .where((p) => p.id == widget.productId)
            .firstOrNull;
        if (product == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: EmptyState(
                icon: Icons.help_outline,
                title: 'Product not found',
                subtitle: 'It may have been removed or is no longer on sale',
                actionLabel: 'Go Back',
                onAction: () => context.pop(),
              ),
            ),
          );
        }

        return _buildDetail(product, isWishlisted);
      },
    );
  }

  Future<void> _openPhotos(List<String> images, int index) async {
    final end = await showImageViewer(context,
        images: images, initialIndex: index);
    if (!mounted || end == null || end == _page) return;
    _pageCtrl.jumpToPage(end);
  }

  Widget _buildDetail(Product product, bool isWishlisted) {
    final images = product.resolvedImages;
    final buyable = product.isActive && !product.isOutOfStock;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RobotAssistantHost(
        products: [product],
        focusProduct: product,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // ── Gallery ──
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: PageView.builder(
                          controller: _pageCtrl,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, index) {
                            final tag = index == _page
                                ? 'product-${product.id}'
                                : 'product-${product.id}-g$index';
                            return GestureDetector(
                              key: Key('product-photo-$index'),
                              onTap: images.isEmpty
                                  ? null
                                  : () => _openPhotos(images, index),
                              child: Hero(
                                tag: tag,
                                child: ProductImage(
                                  imageUrl: images[index],
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorIconSize: 56,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (images.isNotEmpty)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.open_in_full_rounded,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 14,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < images.length; i++)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                      width: i == _page ? 24 : 8,
                                      height: 8,
                                      margin:
                                          const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: i == _page
                                            ? Colors.white
                                            : Colors.white.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Info sections ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBadgeRow(product),
                        const SizedBox(height: 12),
                        Text(product.name,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        _buildRatingLine(product),
                        const SizedBox(height: 12),
                        _buildPriceRow(product),
                        const SizedBox(height: 8),
                        _buildStockLine(product),
                        const SizedBox(height: 8),
                        _buildPickupLine(),
                        const SizedBox(height: 14),
                        const Divider(),
                        const SizedBox(height: 10),
                        if (product.vision?.photoFlagOpen ?? false) ...[
                          _photoFlagNotice(),
                          const SizedBox(height: 12),
                        ],
                        _buildQuantityRow(product),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'About this item'),
                        Text(
                          product.description,
                          maxLines: _descExpanded ? null : 5,
                          overflow:
                              _descExpanded ? null : TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.5),
                        ),
                        if (product.description.length > 160)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _descExpanded = !_descExpanded),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _descExpanded ? 'Read less' : 'Read more',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Seller'),
                        _buildSellerCard(product),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _ReviewsSection(productId: product.id),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Related Products'),
                        _buildRelatedRail(product),
                      ],
                    ),
                  ),
                ),

                const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
              ],
            ),

            // ── Floating controls ──
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _FloatButton(
                      icon: Icons.arrow_back,
                      iconColor: Colors.white,
                      background: Colors.black.withValues(alpha: 0.35),
                      tooltip: 'Back',
                      onTap: () => context.pop(),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FloatButton(
                          icon: Icons.view_in_ar,
                          iconColor: Colors.white,
                          background: Colors.black.withValues(alpha: 0.35),
                          tooltip: 'View in AR',
                          onTap: () => context.pushNamed(
                            RouteNames.arViewer,
                            extra: product,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FloatButton(
                          icon: isWishlisted
                              ? Icons.favorite
                              : Icons.favorite_border,
                          iconColor: isWishlisted
                              ? AppColors.error
                              : Colors.white,
                          background: isWishlisted
                              ? Colors.white
                              : Colors.black.withValues(alpha: 0.35),
                          tooltip:
                              isWishlisted ? 'Remove from wishlist' : 'Wishlist',
                          onTap: () async {
                            if (!await requireAccount(
                                context, ref, 'save items to your wishlist')) {
                              return;
                            }
                            if (!context.mounted) return;
                            ref
                                .read(wishlistProvider.notifier)
                                .toggle(product.id);
                            showAppSnackbar(
                              context,
                              ref
                                      .read(wishlistProvider)
                                      .contains(product.id)
                                  ? 'Added to wishlist'
                                  : 'Removed from wishlist',
                              color: AppColors.accent,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // ── Bottom action bar ──
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: buyable
                        ? () => _addToCart(product)
                        : null,
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text('Add to Cart'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: buyable
                          ? const LinearGradient(
                              colors: [AppColors.accent, AppColors.gradientGreen],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: buyable
                          ? () async {
                              if (!await requireAccount(
                                  context, ref, 'buy products')) {
                                return;
                              }
                              if (!context.mounted) return;
                              context.pushNamed(
                                RouteNames.homeownerCheckout,
                                extra: BuyNowRequest(
                                  product: product,
                                  quantity: _clampedQty(product),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.bolt, size: 20),
                      label: Text(product.isOutOfStock
                          ? 'Out of Stock'
                          : 'Buy Now'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Info blocks ─────────────────────────────────────────────────────────

  Widget _buildBadgeRow(Product product) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (product.isEcoFriendly)
          _ChipBadge(
              text: 'Eco-Friendly',
              background: AppColors.success.withValues(alpha: 0.1),
              color: AppColors.success,
              icon: Icons.eco),
        _ChipBadge(
            text: product.category,
            background: AppColors.accent.withValues(alpha: 0.1),
            color: AppColors.accent),
        _ChipBadge(
            text: product.designStyle,
            background: AppColors.primary.withValues(alpha: 0.08),
            color: AppColors.primary),
        if (product.ratingCount == 0)
          _ChipBadge(
              text: 'New',
              background: AppColors.secondaryAccent.withValues(alpha: 0.1),
              color: AppColors.secondaryAccent),
      ],
    );
  }

  Widget _buildRatingLine(Product product) {
    if (product.ratingCount <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        RatingStars(rating: product.rating, size: 16),
        const SizedBox(width: 8),
        Text('${product.rating.toStringAsFixed(1)} (${product.ratingCount})',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildPriceRow(Product product) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(Formatters.myr(product.price),
            style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.accent)),
        if (product.originalPrice != null) ...[
          Text(Formatters.myr(product.originalPrice!),
              style: TextStyle(
                  fontSize: 16,
                  decoration: TextDecoration.lineThrough,
                  color: AppColors.textHint)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('-${product.discountPercent}%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error)),
          ),
        ],
      ],
    );
  }

  Widget _buildStockLine(Product product) {
    final (icon, color, label) = product.isOutOfStock
        ? (Icons.cancel, AppColors.error, 'Out of stock')
        : product.isLowStock
            ? (Icons.warning_amber_rounded, AppColors.warning,
                'Only ${product.stock} left — order soon')
            : (Icons.check_circle, AppColors.success, 'In stock');
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color)),
          ),
        ),
      ],
    );
  }

  Widget _buildPickupLine() {
    return const Row(
      children: [
        Icon(Icons.handshake_outlined, size: 16, color: AppColors.success),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Self-collection — collect from the seller',
            maxLines: 1,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.success),
          ),
        ),
      ],
    );
  }

  // Shown while our photo check says the picture may not be what the
  // listing describes (until an admin resolves it).
  Widget _photoFlagNotice() {
    return Container(
      key: const Key('photo-flag-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_gmailerrorred_outlined,
              size: 20, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'The photo may not match this listing. Our check has asked the '
              'seller to review it — confirm the details with them before '
              'buying.',
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityRow(Product product) {
    if (product.isOutOfStock) return const SizedBox.shrink();
    return Row(
      children: [
        const Text('Quantity',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(width: 12),
        // The stepper keeps its natural size where it fits and scales down
        // on narrow phones / large text instead of overflowing.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: QuantityStepper(
          value: _clampedQty(product),
          min: 1,
          max: product.stock,
          label: 'of ${product.stock}',
          onChanged: (v) => setState(() => _qty = v),
          onBlockedTap: () => showAppSnackbar(
            context,
            _qty >= product.stock
                ? 'Only ${product.stock} available — that\'s the maximum'
                : 'Minimum quantity is 1',
            color: AppColors.warning,
          ),
        ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSellerCard(Product product) {
    final supplier = product.supplier;
    final initial = supplier.name.trim().isNotEmpty
        ? supplier.name.trim()[0].toUpperCase()
        : '?';
    // The seller's brand colour tints their avatar; unset falls back to the
    // app accent.
    final brandValue = supplier.storeProfile.brandColorValue;
    final brand = (brandValue == null || brandValue == 0)
        ? AppColors.accent
        : Color(brandValue);
    final about = supplier.storeProfile.description.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                key: const Key('seller-avatar'),
                radius: 20,
                backgroundColor: brand.withValues(alpha: 0.14),
                child: Text(initial,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: brand)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(supplier.name,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                        if (supplier.isVerified) ...[
                          const SizedBox(width: 6),
                          VerifiedBadge(
                              verificationStatus: supplier.verificationStatus),
                        ],
                      ],
                    ),
                    if (supplier.address.isNotEmpty)
                      Text('Pickup at ${supplier.address}',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                    ..._hoursLines(supplier.storeProfile),
                  ],
                ),
              ),
            ],
          ),
          if (about.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(about,
                key: const Key('store-about'),
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary)),
          ],
          if (_storeDetailRows(supplier.storeProfile).isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('store-profile-block'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in _storeDetailRows(supplier.storeProfile))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(row.$1, size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(row.$2,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: supplier.phone.isNotEmpty
                      ? () => _launchExternal(
                          'tel:${supplier.phone.replaceAll(RegExp(r'[^\d+]'), '')}',
                          'Phone calls aren\'t supported on this device')
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: GoogleFonts.poppins(fontSize: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: supplier.email.isNotEmpty
                      ? () => _launchExternal(
                          'mailto:${supplier.email}',
                          'Email isn\'t supported on this device')
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: GoogleFonts.poppins(fontSize: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: const Text('Email'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openQuoteDialog(product),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: GoogleFonts.poppins(fontSize: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.request_quote, size: 16),
              label: const Text('Request bulk quote'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedRail(Product product) {
    final products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const [];
    final related = products
        .where((p) =>
            p.isActive &&
            p.id != product.id &&
            p.category.toLowerCase() == product.category.toLowerCase())
        .take(8)
        .toList();

    if (related.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < related.length; index++) ...[
              if (index > 0) const SizedBox(width: 12),
              _relatedCard(related[index]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _relatedCard(Product item) {
    return SizedBox(
            width: 150,
            child: ProductCard(
              product: item,
              compact: true,
              isWishlisted:
                  ref.watch(wishlistProvider).contains(item.id),
              onTap: () => context.pushNamed(
                RouteNames.homeownerProductDetail,
                pathParameters: {'id': item.id},
              ),
              onAddToCart: () async {
                if (!await requireAccount(context, ref, 'add items to your cart')) {
                  return;
                }
                if (!context.mounted) return;
                ref.read(cartProvider.notifier).addItem(item);
                showAddedToCartSnack(
                  context,
                  '${item.name} added to cart',
                  onViewCart: () => context.pushNamed(RouteNames.homeownerCart),
                );
              },
              onToggleWishlist: () async {
                if (!await requireAccount(
                    context, ref, 'save items to your wishlist')) {
                  return;
                }
                if (!context.mounted) return;
                final was = ref
                    .read(wishlistProvider)
                    .contains(item.id);
                ref.read(wishlistProvider.notifier).toggle(item.id);
                showAppSnackbar(
                  context,
                  was ? 'Removed from wishlist' : 'Added to wishlist',
                  color: AppColors.accent,
                );
              },
            ),
          );
  }
}

// ── Small building blocks ────────────────────────────────────────────────────

// Opening hours on the seller card: a live open/closed line (Malaysian time)
// and the week at a glance; a profile saved before the schedule existed
// shows its free-text hours instead.
List<Widget> _hoursLines(StoreProfile store, {DateTime? nowUtc}) {
  final weekly = store.weeklyHours;
  final note = store.hours.trim();
  if (weekly == null || weekly.isEmpty) {
    if (note.isEmpty) return const [];
    return [
      const SizedBox(height: 4),
      Text('Open $note',
          style: TextStyle(fontSize: 11, color: AppColors.textHint)),
    ];
  }
  final now = WeeklyHours.malaysiaNow(nowUtc);
  final open = weekly.isOpenAt(now);
  return [
    const SizedBox(height: 4),
    Text(
      weekly.statusAt(now),
      key: const Key('store-open-status'),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: open ? AppColors.success : AppColors.textSecondary,
      ),
    ),
    const SizedBox(height: 2),
    Text(weekly.summary,
        key: const Key('store-hours-summary'),
        style: TextStyle(fontSize: 11, color: AppColors.textHint)),
    if (note.isNotEmpty)
      Text(note, style: TextStyle(fontSize: 11, color: AppColors.textHint)),
  ];
}

// What a seller says about how they trade, in the order a buyer cares about.
List<(IconData, String)> _storeDetailRows(StoreProfile store) {
  final rows = <(IconData, String)>[];
  if (store.isEmpty) return rows;
  // Every order is paid in the app, whatever older store profiles say.
  rows.add((Icons.payments_outlined, 'Paid online at checkout — card or FPX'));
  if (store.pickupPolicy.trim().isNotEmpty) {
    rows.add((Icons.storefront_outlined, store.pickupPolicy.trim()));
  }
  if (store.returnPolicy.trim().isNotEmpty) {
    rows.add((Icons.replay_outlined, store.returnPolicy.trim()));
  }
  return rows;
}

class _FloatButton extends StatelessWidget {
  const _FloatButton({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({
    required this.text,
    required this.background,
    required this.color,
    this.icon,
  });

  final String text;
  final Color background;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          // A category/style longer than the line has nowhere to wrap to.
          Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ),
        ],
      ),
    );
  }
}

// ── Bulk quote request dialog ─────────────────────────────────────────────────

class _BulkQuoteDialog extends StatefulWidget {
  const _BulkQuoteDialog({
    required this.product,
    required this.initialQty,
    required this.user,
    required this.onSubmit,
  });

  final Product product;
  final int initialQty;
  final AppUser user;
  final Future<void> Function(QuoteRequest) onSubmit;

  @override
  State<_BulkQuoteDialog> createState() => _BulkQuoteDialogState();
}

class _BulkQuoteDialogState extends State<_BulkQuoteDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _qty;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _noteCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty < kBulkQuoteMinQty
        ? kBulkQuoteMinQty
        : widget.initialQty;
    _nameCtrl = TextEditingController(text: widget.user.name);
    _phoneCtrl = TextEditingController(text: widget.user.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static String? _nameValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Add your name so the supplier knows who to contact.';
    }
    return null;
  }

  static String? _phoneValidator(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'Add your phone number so the supplier can reach you.';
    }
    final digits = v.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (digits.length < 9 ||
        digits.length > 15 ||
        !RegExp(r'^\d+$').hasMatch(digits)) {
      return 'Enter a valid phone number (9–15 digits)';
    }
    return null;
  }

  Future<void> _send() async {
    if (_sending) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _sending = true);
    final request = QuoteRequest(
      id: MarketplaceRepository.newOrderId(),
      productId: widget.product.id,
      productName: widget.product.name,
      productImage: widget.product.resolvedImages.firstOrNull,
      supplierId: widget.product.resolvedSupplierId,
      customerId: widget.user.uid,
      customerName: _nameCtrl.text.trim(),
      customerEmail: widget.user.email,
      customerPhone: _phoneCtrl.text.trim(),
      quantity: _qty,
      note: _noteCtrl.text.trim(),
      status: QuoteRequest.statusSubmitted,
      createdAt: DateTime.now(),
    );
    try {
      await widget.onSubmit(request);
      if (!mounted) return;
      Navigator.of(context).pop(request);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppSnackbar(
        context,
        userMessage(e,
            fallback: 'Could not send your quote request. Please try again.'),
        isError: true,
        duration: const Duration(seconds: 4),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request bulk quote'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The supplier will contact you personally by phone or '
                      'email.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'Quantity',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  QuantityStepper(
                    value: _qty,
                    min: kBulkQuoteMinQty,
                    compact: true,
                    onChanged: (v) => setState(() => _qty = v),
                  ),
                ],
              ),
              Text(
                'Bulk quotes start at $kBulkQuoteMinQty units — for fewer, '
                'add to cart instead.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _nameValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: AppFormatters.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: _phoneValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText:
                      'What do you need? e.g. 20 units, delivery to Johor',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send request'),
        ),
      ],
    );
  }
}

// ── Reviews section (live) ───────────────────────────────────────────────────

class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(productReviewsProvider(productId));

    return reviewsAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Reviews'),
          for (var i = 0; i < 2; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 110, height: 10,
                              decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 6),
                          Container(
                              width: 60, height: 8,
                              decoration: BoxDecoration(
                                  color: AppColors.divider,
                                  borderRadius: BorderRadius.circular(4))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                      width: double.infinity, height: 10,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
        ],
      ),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Reviews'),
          Row(
            children: [
              Expanded(
                child: Text("Couldn't load reviews",
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(productReviewsProvider(productId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
      data: (reviews) {
        final count = reviews.length;
        final average = count > 0
            ? (reviews.fold<int>(0, (sum, r) => sum + r.rating) /
                    count)
                .toStringAsFixed(1)
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Reviews${count > 0 ? ' ($count)' : ''}',
              trailingLabel: average == null ? null : '$average avg',
            ),
            if (count == 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined,
                        size: 28,
                        color: AppColors.textHint.withValues(alpha: 0.7)),
                    const SizedBox(height: 8),
                    Text(
                      'No reviews yet — be the first after you collect your order.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                  ],
                ),
              )
            else
              for (final review in reviews)
                _ReviewTile(review: review),
          ],
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  String get _initial => review.userName.trim().isNotEmpty
      ? review.userName.trim()[0].toUpperCase()
      : '?';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: Text(_initial,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    Text(Formatters.shortDate(review.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textHint)),
                  ],
                ),
              ),
              RatingStars(rating: review.rating.toDouble(), size: 14),
            ],
          ),
          const SizedBox(height: 10),
          if (review.comment.trim().isNotEmpty)
            _ExpandableComment(text: review.comment),
        ],
      ),
    );
  }
}

class _ExpandableComment extends StatefulWidget {
  const _ExpandableComment({required this.text});

  final String text;

  @override
  State<_ExpandableComment> createState() => _ExpandableCommentState();
}

class _ExpandableCommentState extends State<_ExpandableComment> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.45,
        );
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    _expanded ? 'Show less' : 'Read more',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Loading skeleton ─────────────────────────────────────────────────────────

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Container(
            height: MediaQuery.of(context).size.width * 3 / 4,
            color: AppColors.surface,
            alignment: Alignment.center,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(width: 200, height: 18),
                const SizedBox(height: 12),
                _bar(width: 120, height: 12),
                const SizedBox(height: 12),
                _bar(width: 90, height: 20),
                const SizedBox(height: 16),
                _bar(width: double.infinity, height: 12),
                const SizedBox(height: 8),
                _bar(width: double.infinity, height: 12),
                const SizedBox(height: 8),
                _bar(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

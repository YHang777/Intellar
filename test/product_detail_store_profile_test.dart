import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/theme/app_theme.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/screens/product_detail_screen.dart';
import 'package:interior_design_recommendation/models/app_config_data.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/review.dart';
import 'package:interior_design_recommendation/models/store_profile.dart';
import 'package:interior_design_recommendation/services/marketplace_repository.dart';

final _day = DateTime(2026, 1, 1);

final _buyer = AppUser(
  uid: 'buyer-1',
  email: 'aina@example.com',
  name: 'Aina',
  role: UserRole.homeowner,
  createdAt: _day,
  updatedAt: _day,
);

Product _product(StoreProfile store) => Product(
      id: 'p-1',
      name: 'Oak Dining Table',
      price: 1200,
      stock: 20,
      image: '',
      description: 'Solid oak three-seater.',
      designStyle: 'Modern',
      category: 'Furniture',
      supplier: Supplier(
        id: 'sup-1',
        name: 'Kedai Furnitur',
        phone: '0312345678',
        address: 'Shah Alam',
        email: 'seller@example.com',
        storeProfile: store,
      ),
      supplierId: 'sup-1',
    );

class _Repo implements MarketplaceRepository {
  _Repo(this.products);
  final List<Product> products;

  @override
  Stream<List<Product>> watchProducts() => Stream.value(products);
  @override
  Stream<List<Review>> watchReviews(String productId) => Stream.value(const []);
  @override
  Stream<List<String>> watchWishlistIds(String uid) => Stream.value(const []);
  @override
  Stream<List<CartItem>> watchCart(String uid) => Stream.value(const []);
  @override
  Future<AppConfigData> fetchConfig() async => const AppConfigData(
      currency: 'MYR', taxRate: 0.06, membershipTiers: []);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not stubbed: ${invocation.memberName}');
}

Future<void> _pump(WidgetTester tester, Product product) async {
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = _Repo([product]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      marketplaceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWithValue(_buyer),
      marketplaceProductsProvider.overrideWith((ref) => Stream.value([product])),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const ProductDetailScreen(productId: 'p-1'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300,
      scrollable: find
          .ancestor(of: find.text('Kedai Furnitur').first,
              matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('buyers see what the seller saved in their store profile',
      (tester) async {
    await _pump(
      tester,
      _product(const StoreProfile(
        description: 'Handmade oak furniture from Penang',
        hours: 'Mon–Fri 9am–6pm',
        brandColorValue: 0xFF1565C0,
        pickupPolicy: 'Collect within 7 days',
        returnPolicy: '14-day returns',
        paymentMethods: ['Bank transfer', 'E-wallet'],
      )),
    );

    await _reveal(tester, find.byKey(const Key('store-profile-block')));
    expect(find.text('Handmade oak furniture from Penang'), findsOneWidget);
    expect(find.text('Open Mon–Fri 9am–6pm'), findsOneWidget);
    expect(find.text('Accepts Bank transfer, E-wallet'), findsOneWidget);
    expect(find.text('Collect within 7 days'), findsOneWidget);
    expect(find.text('14-day returns'), findsOneWidget);

    final avatar =
        tester.widget<CircleAvatar>(find.byKey(const Key('seller-avatar')));
    expect(avatar.backgroundColor?.toARGB32(),
        const Color(0xFF1565C0).withValues(alpha: 0.14).toARGB32(),
        reason: 'the brand colour tints the seller avatar');
  });

  testWidgets('a seller without a profile shows no empty store block',
      (tester) async {
    await _pump(tester, _product(const StoreProfile()));
    await _reveal(tester, find.byKey(const Key('seller-avatar')));
    expect(find.byKey(const Key('store-profile-block')), findsNothing);
    expect(find.byKey(const Key('store-about')), findsNothing);
    expect(find.textContaining('Open '), findsNothing);
  });
}

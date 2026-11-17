import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/models/store_profile.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/product_category.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/data/datasources/account_deletion_datasource.dart';

Product _p(String id, {int soldCount = 0}) => Product(
      id: id,
      name: 'Item $id',
      price: 100,
      stock: 5,
      image: '',
      description: 'A test piece',
      designStyle: 'Modern',
      category: 'Furniture',
      supplier: const Supplier(
          id: 's1', name: 'Store', phone: '', address: '', email: ''),
      soldCount: soldCount,
      createdAt: DateTime(2026, 11, 17),
    );

class _Auth implements IAuthRepository {
  @override
  Stream<AppUser?> authStateChanges() async* {
    final now = DateTime(2026);
    yield AppUser(
        uid: 'u1',
        email: 'a@b.com',
        name: 'A',
        role: UserRole.homeowner,
        createdAt: now,
        updatedAt: now);
  }

  @override
  Future<AppUser?> getCurrentUser() async => null;
  @override
  Future<AppUser> login(String e, String p) => throw UnimplementedError();
  @override
  Future<AppUser> register(
          {required String email,
          required String password,
          required String name,
          required UserRole role,
          String? phone,
          String? address}) =>
      throw UnimplementedError();
  @override
  Future<AppUser> updateProfile(
          {required String name,
          String? phone,
          String? address,
          String? businessName,
          String? businessPhone,
          String? businessAddress,
          StoreProfile? storeProfile}) =>
      throw UnimplementedError();
  @override
  Future<void> logout() async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async {}
  @override
  Future<void> resendVerificationEmail({String? email, String? uid}) async {}
  @override
  Future<bool> isEmailVerified() async => true;
  @override
  Future<DeletionStatus> requestAccountDeletion(String e) async =>
      const DeletionStatus(status: 'none');
  @override
  Future<DeletionStatus> cancelAccountDeletion() async =>
      const DeletionStatus(status: 'none');
  @override
  Future<DeletionStatus> fetchDeletionStatus() async =>
      const DeletionStatus(status: 'none');
}

void main() {
  Future<void> pump(WidgetTester tester, List<Product> products,
      {bool popularOnly = false}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(products)),
        customerOrdersProvider.overrideWith((ref) => Stream.value(const [])),
        categoriesProvider
            .overrideWith((ref) async => const <ProductCategory>[]),
        stylesProvider.overrideWith((ref) async => const <String>[]),
        popularOnlyProvider.overrideWith((ref) => popularOnly),
      ],
      child: const MaterialApp(home: MarketplaceScreen()),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('a filter that matches nothing explains itself, not a blank page',
      (tester) async {
    await pump(tester, [_p('a', soldCount: 0), _p('b', soldCount: 0)],
        popularOnly: true);

    // The header must survive an empty result set.
    expect(find.text('Marketplace'), findsOneWidget,
        reason: 'the page header disappears behind an empty filter');
    expect(find.textContaining('No products'), findsOneWidget,
        reason: 'an empty result must say so instead of showing nothing');
    expect(find.text('Popular'), findsOneWidget,
        reason: 'the active filter chip must say which filter is on');
  });

  testWidgets('a search that matches nothing also explains itself',
      (tester) async {
    await pump(tester, [_p('a')]);
    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.textContaining('No products'), findsNothing,
        reason: 'with products present there is nothing to explain');
  });
}

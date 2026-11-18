import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/datasources/account_deletion_datasource.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/screens/store_profile_screen.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/store_profile.dart';
import 'package:interior_design_recommendation/services/marketplace_repository.dart';

// Records the copy-out onto listings; everything else is unused here.
class _RecordingRepo implements MarketplaceRepository {
  _RecordingRepo({this.fail = false});
  final bool fail;
  String? syncedFor;
  StoreProfile? synced;
  Supplier? syncedSupplier;

  @override
  Future<int> syncSupplierDetails(Supplier supplier) async {
    if (fail) throw Exception('offline');
    syncedSupplier = supplier;
    syncedFor = supplier.id;
    synced = supplier.storeProfile;
    return 3;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAuth implements IAuthRepository {
  _RecordingAuth({this.initial = const StoreProfile()});
  final StoreProfile initial;
  StoreProfile? saved;
  int saves = 0;

  @override
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    StoreProfile? storeProfile,
  }) async {
    saves++;
    saved = storeProfile;
    final now = DateTime(2026, 11, 17);
    return AppUser(
      uid: 'u1',
      email: 'a@b.com',
      name: name,
      role: UserRole.supplier,
      storeProfile: storeProfile ?? const StoreProfile(),
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Stream<AppUser?> authStateChanges() async* {
    final now = DateTime(2026, 11, 17);
    yield AppUser(
        uid: 'u1',
        email: 'a@b.com',
        name: 'QA Store',
        role: UserRole.supplier,
        storeProfile: initial,
        createdAt: now,
        updatedAt: now);
  }

  @override
  Future<AppUser?> getCurrentUser() async => null;
  @override
  Future<AppUser> login(String e, String p) => throw UnimplementedError();
  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) =>
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
  late _RecordingRepo repo;

  Future<_RecordingAuth> pump(WidgetTester tester,
      {StoreProfile initial = const StoreProfile(), bool syncFails = false}) async {
    final auth = _RecordingAuth(initial: initial);
    repo = _RecordingRepo(fail: syncFails);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        marketplaceRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: StoreProfileScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return auth;
  }

  /// The screen is a lazy ListView: scroll before asserting on lower cards.
  // The screen is a lazy ListView, so off-screen widgets do not exist yet.
  // scrollUntilVisible (not ensureVisible) is the one that searches while
  // scrolling.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.ensureVisible(finder);
    // ensureVisible animates — tap only once it has settled, or the hit
    // lands at a stale position.
    await tester.pumpAndSettle();
  }

  testWidgets('offers every field the report asks a supplier to manage',
      (tester) async {
    await pump(tester);
    // Top of the screen first — scrolling pushes the heading out of view.
    expect(find.text('Store profile'), findsOneWidget);
    expect(find.text('Branding'), findsOneWidget);
    expect(find.text('Business hours'), findsOneWidget);

    await reveal(tester, find.text('Policies'));
    expect(find.text('Policies'), findsOneWidget);
    await reveal(tester, find.text('Accepted payment options'));
    expect(find.text('Accepted payment options'), findsOneWidget);
    for (final option in StoreProfile.paymentOptions) {
      expect(find.text(option), findsOneWidget);
    }
  });

  testWidgets('saving sends the drafted values to the account', (tester) async {
    final auth = await pump(tester);

    await tester.enterText(find.byKey(const Key('store-description')),
        'Oak furniture, made in Penang');
    await reveal(tester, find.byKey(const Key('store-hours')));
    await tester.enterText(
        find.byKey(const Key('store-hours')), 'Mon–Fri 9:00–18:00');
    await reveal(tester, find.byKey(const Key('store-pickup-policy')));
    await tester.enterText(find.byKey(const Key('store-pickup-policy')),
        'Collect within 7 days');
    await reveal(tester, find.byKey(const Key('pay-Bank-transfer')));
    await tester.tap(find.byKey(const Key('pay-Bank-transfer')));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('save-store-profile')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(auth.saves, 1);
    expect(auth.saved?.description, 'Oak furniture, made in Penang');
    expect(auth.saved?.hours, 'Mon–Fri 9:00–18:00');
    expect(auth.saved?.pickupPolicy, 'Collect within 7 days');
    expect(auth.saved?.paymentMethods, ['Bank transfer']);

    // Buyers read the profile from each listing, so it must be copied there.
    expect(repo.syncedFor, 'u1');
    expect(repo.synced?.hours, 'Mon–Fri 9:00–18:00');
    expect(repo.synced?.paymentMethods, ['Bank transfer']);
  });

  testWidgets('if listings cannot be updated, it says so and stays open',
      (tester) async {
    final auth = await pump(tester, syncFails: true);

    await tester.enterText(
        find.byKey(const Key('store-description')), 'Oak furniture');
    await tester.tap(find.byKey(const Key('save-store-profile')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(auth.saves, 1, reason: 'the account copy is still saved');
    expect(find.textContaining('listings could not be updated'), findsOneWidget);
    expect(find.byType(StoreProfileScreen), findsOneWidget,
        reason: 'stay so the seller can retry');
  });

  testWidgets('"no colour" clears the brand colour instead of storing 0',
      (tester) async {
    final auth = await pump(tester,
        initial: const StoreProfile(brandColorValue: 0xFF1565C0));

    await tester.tap(find.byKey(const Key('swatch-clear')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('save-store-profile')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(auth.saves, 1);
    expect(auth.saved?.brandColorValue, isNull);
  });

  testWidgets('a saved option can be turned off again', (tester) async {
    final auth = await pump(
      tester,
      initial: const StoreProfile(paymentMethods: ['E-wallet']),
    );
    const key = Key('pay-E-wallet');

    await reveal(tester, find.byKey(key));
    // Tap the control itself: the tile's centre sits on its label.
    await tester.tap(find.descendant(
        of: find.byKey(key), matching: find.byType(Checkbox)));
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('save-store-profile')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(auth.saved?.paymentMethods, isEmpty,
        reason: 'the option should be cleared, not just left alone');
  });
}


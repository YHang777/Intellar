import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/profile_screen.dart';

void main() {
  testWidgets('back while editing the profile cancels the edit, not the page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 11, 19);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(AppUser(
          uid: 'u1',
          email: 'a@b.com',
          name: 'Ana',
          role: UserRole.homeowner,
          createdAt: now,
          updatedAt: now,
        )),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pump();

    await tester.tap(find.text('Edit Profile'));
    await tester.pump();
    expect(find.text('Save Changes'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pump();

    expect(handled, isTrue);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Save Changes'), findsNothing);
    expect(find.text('Edit Profile'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/shared/widgets/guest_gate.dart';

Future<List<bool>> _tapGated(WidgetTester tester, AppUser user) async {
  final allowed = <bool>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [currentUserProvider.overrideWithValue(user)],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () async =>
                allowed.add(await requireAccount(context, ref, 'add items to your cart')),
            child: const Text('Add'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
  return allowed;
}

void main() {
  test('a guest is an onboarded homeowner with no email', () {
    final g = AppUser.guest('anon1');
    expect(g.isGuest, isTrue);
    expect(g.isHomeowner, isTrue);
    expect(g.onboardingCompleted, isTrue);
    expect(g.email, isEmpty);
    expect(g.copyWith(name: 'x').isGuest, isTrue, reason: 'copyWith keeps guest status');
  });

  testWidgets('guests get the sign-up sheet instead of the action', (tester) async {
    final allowed = await _tapGated(tester, AppUser.guest('anon1'));
    expect(find.byKey(const Key('guest-sign-up-sheet')), findsOneWidget);
    expect(find.textContaining('Sign up to add items to your cart'), findsOneWidget);
    await tester.tap(find.text('Keep browsing'));
    await tester.pumpAndSettle();
    expect(allowed, [false]);
  });

  testWidgets('signed-in users go straight through', (tester) async {
    final now = DateTime(2026, 11, 19);
    final user = AppUser(uid: 'u1', email: 'a@b.com', name: 'A', role: UserRole.homeowner,
        createdAt: now, updatedAt: now);
    final allowed = await _tapGated(tester, user);
    expect(allowed, [true]);
    expect(find.byKey(const Key('guest-sign-up-sheet')), findsNothing);
  });
}

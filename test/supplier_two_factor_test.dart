import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/settings/presentation/screens/security_settings_screen.dart';

AppUser _user(UserRole role, {bool twoFactor = false}) {
  final now = DateTime(2026, 11, 19);
  return AppUser(
    uid: 'u1',
    email: 'a@b.com',
    name: 'A',
    role: role,
    twoFactorEnabled: twoFactor,
    createdAt: now,
    updatedAt: now,
  );
}

Future<SwitchListTile> _switch(WidgetTester tester, AppUser user) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [currentUserProvider.overrideWithValue(user)],
    child: const MaterialApp(home: SecuritySettingsScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return tester.widget<SwitchListTile>(find.descendant(
      of: find.byKey(const Key('two-factor-switch')),
      matching: find.byType(SwitchListTile)));
}

void main() {
  testWidgets('a seller with two-step on can switch it off (code-checked)',
      (tester) async {
    final sw = await _switch(tester, _user(UserRole.supplier, twoFactor: true));
    expect(sw.value, isTrue);
    expect(sw.onChanged, isNotNull, reason: 'sellers may turn it off');
    expect(find.textContaining('Recommended for sellers'), findsOneWidget);
    expect(find.textContaining('needs a code'), findsOneWidget);
  });

  testWidgets('a homeowner keeps the optional switch', (tester) async {
    final sw = await _switch(tester, _user(UserRole.homeowner));
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNotNull);
    expect(find.textContaining('Recommended for sellers'), findsNothing);
  });
}

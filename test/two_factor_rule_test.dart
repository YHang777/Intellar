import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/data/repositories/auth_repository_impl.dart';

AppUser _u(UserRole role, {bool twoFactor = false}) => AppUser(
      uid: 'u',
      email: 'a@b.com',
      name: 'A',
      role: role,
      twoFactorEnabled: twoFactor,
      createdAt: DateTime(2026, 11, 19),
      updatedAt: DateTime(2026, 11, 19),
    );

void main() {
  test('sellers always need the code, even with the switch off', () {
    expect(needsTwoFactor(_u(UserRole.supplier)), isTrue);
    expect(needsTwoFactor(_u(UserRole.supplier, twoFactor: true)), isTrue);
  });

  test('homeowners only when they switched it on', () {
    expect(needsTwoFactor(_u(UserRole.homeowner)), isFalse);
    expect(needsTwoFactor(_u(UserRole.homeowner, twoFactor: true)), isTrue);
  });
}

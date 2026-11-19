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
  test('sellers follow their switch too (it starts on for them)', () {
    expect(needsTwoFactor(_u(UserRole.supplier, twoFactor: true)), isTrue);
    expect(needsTwoFactor(_u(UserRole.supplier)), isFalse);
  });

  test('a seller profile with no stored choice starts with two-step on', () {
    final seller = AppUser.fromFirestore(
        uid: 's1', email: 'a@b.com', data: {'name': 'A', 'role': 'supplier'});
    expect(seller.twoFactorEnabled, isTrue);
    final switchedOff = AppUser.fromFirestore(
        uid: 's2',
        email: 'a@b.com',
        data: {'name': 'A', 'role': 'supplier', 'twoFactorEnabled': false});
    expect(switchedOff.twoFactorEnabled, isFalse);
    final homeowner = AppUser.fromFirestore(
        uid: 'h1', email: 'a@b.com', data: {'name': 'A', 'role': 'homeowner'});
    expect(homeowner.twoFactorEnabled, isFalse);
  });

  test('homeowners only when they switched it on', () {
    expect(needsTwoFactor(_u(UserRole.homeowner)), isFalse);
    expect(needsTwoFactor(_u(UserRole.homeowner, twoFactor: true)), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/store_profile.dart';

void main() {
  group('StoreProfile', () {
    test('round-trips through Firestore shape', () {
      const p = StoreProfile(
        description: 'Oak furniture from Penang',
        hours: 'Mon–Fri 9:00–18:00',
        brandColorValue: 0xFF2E7D32,
        pickupPolicy: 'Collect within 7 days',
        returnPolicy: '14-day returns',
        paymentMethods: ['Bank transfer', 'Cash on collection'],
      );
      final back = StoreProfile.fromMap(p.toMap());
      expect(back.description, p.description);
      expect(back.hours, p.hours);
      expect(back.brandColorValue, 0xFF2E7D32);
      expect(back.paymentMethods, p.paymentMethods);
      expect(back.isEmpty, isFalse);
    });

    test('survives absent or malformed data', () {
      expect(const StoreProfile().isEmpty, isTrue);
      expect(StoreProfile.fromMap(null).isEmpty, isTrue);
      expect(StoreProfile.fromMap('nonsense').isEmpty, isTrue);
      expect(StoreProfile.fromMap({
        'paymentMethods': ['Card', '', '  ', 'E-wallet'],
        'brandColorValue': 'not-a-number',
      }).paymentMethods, ['Card', 'E-wallet']);
    });

    test('is carried on the supplier the buyer sees', () {
      const supplier = Supplier(
        id: 's1',
        name: 'Oak & Co',
        phone: '0123',
        address: '1 Jalan Test',
        email: 'a@b.com',
        storeProfile: StoreProfile(hours: 'Mon–Fri 9:00–18:00'),
      );
      expect(supplier.storeProfile.hours, 'Mon–Fri 9:00–18:00');

      final fromJson = Supplier.fromJson({
        'id': 's1',
        'name': 'Oak & Co',
        'storeProfile': {
          'hours': 'Sat 10:00–14:00',
          'paymentMethods': ['E-wallet'],
        },
      });
      expect(fromJson.storeProfile.hours, 'Sat 10:00–14:00');
      expect(fromJson.storeProfile.paymentMethods, ['E-wallet']);

      // Products written before this feature must not break.
      expect(Supplier.fromJson({'id': 's1', 'name': 'Old'}).storeProfile.isEmpty,
          isTrue);
    });

    test('the per-listing supplier copy carries the profile buyers see', () {
      const supplier = Supplier(
        id: 's1',
        name: 'Oak & Co',
        phone: '0123',
        address: '1 Jalan Test',
        email: 'a@b.com',
        storeProfile: StoreProfile(
          hours: 'Mon–Fri 9:00–18:00',
          paymentMethods: ['E-wallet'],
        ),
      );
      final json = supplier.toJson();
      expect(json['storeProfile'], isA<Map>());
      final back = Supplier.fromJson(Map<String, dynamic>.from(json));
      expect(back.storeProfile.hours, 'Mon–Fri 9:00–18:00');
      expect(back.storeProfile.paymentMethods, ['E-wallet']);

      // An empty profile adds nothing to old-style listings.
      const bare = Supplier(
          id: 's1', name: 'Old', phone: '', address: '', email: '');
      expect(bare.toJson().containsKey('storeProfile'), isFalse);
    });

    test('clearBrandColor removes the colour; plain copyWith keeps it', () {
      const p = StoreProfile(brandColorValue: 0xFF1565C0, hours: 'Sat');
      expect(p.copyWith(hours: 'Sun').brandColorValue, 0xFF1565C0);
      expect(p.copyWith(clearBrandColor: true).brandColorValue, isNull);
      expect(p.copyWith(clearBrandColor: true).hours, 'Sat');
    });
  });
}

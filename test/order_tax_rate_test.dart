import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/utils/pricing.dart';
import 'package:interior_design_recommendation/models/order.dart';

Map<String, dynamic> _json({double? taxRate}) => {
      'id': 'o1',
      'orderNumber': 'INT-1',
      'customerId': 'c1',
      'customerName': 'A',
      'customerEmail': 'a@b.com',
      'customerPhone': '0123',
      'items': <dynamic>[],
      'status': 'collected',
      'paymentMethod': 'card_fpx',
      'subtotal': 1000,
      'discount': 0,
      'tax': 60,
      'total': 1060,
      'createdAt': '2026-10-01T00:00:00Z',
      if (taxRate != null) 'taxRate': taxRate,
    };

void main() {
  test('an order keeps the tax rate it was charged at', () {
    final o = Order.fromJson(_json(taxRate: 0.06));
    expect(taxPercentLabel(o.chargedTaxRate), '6%');
    expect(o.toJson()['taxRate'], 0.06);
  });

  test('older orders without a stored rate derive it from their own amounts', () {
    final o = Order.fromJson(_json());
    expect(taxPercentLabel(o.chargedTaxRate), '6%');
    expect(o.toJson().containsKey('taxRate'), isFalse);
  });
}

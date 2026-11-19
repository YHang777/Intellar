import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/providers/supplier_providers.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _p(String id, String supplier, {int views = 0, int sold = 0}) => Product.fromJson({
      'id': id,
      'name': id,
      'price': 100,
      'stock': 5,
      'supplierId': supplier,
      'supplier': {'id': supplier, 'name': supplier},
      'viewCount': views,
      'soldCount': sold,
    });

void main() {
  final all = [
    _p('a', 'me', views: 40, sold: 2),
    _p('b', 'me', views: 120, sold: 3),
    _p('c', 'me'),
    _p('x', 'rival', views: 999),
  ];

  test('only my listings, most viewed first', () {
    expect(viewStats(all, 'me').map((s) => s.product.id), ['b', 'a', 'c']);
    expect(totalViews(all, 'me'), 160);
  });

  test('conversion is sold per 100 views, none without views', () {
    final b = viewStats(all, 'me').first;
    expect(b.conversionPercent, closeTo(2.5, 1e-9));
    expect(viewStats(all, 'me').last.conversionPercent, isNull);
  });

  test('a stored viewCount is read; a missing one is 0', () {
    expect(_p('a', 'me', views: 7).viewCount, 7);
    expect(Product.fromJson({'id': 'z', 'name': 'z', 'price': 1, 'stock': 1}).viewCount, 0);
  });
}

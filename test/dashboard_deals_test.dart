import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/dashboard_deals.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _p(String id, int price, {int? was, int stock = 3, bool active = true}) => Product(
      id: id,
      name: id,
      price: price,
      originalPrice: was,
      stock: stock,
      image: '',
      description: 'A test piece for deals',
      designStyle: 'Modern',
      category: 'Furniture',
      isActive: active,
      supplier: const Supplier(id: 's', name: 'S', phone: '', address: '', email: ''),
    );

void main() {
  test('only discounted, live, in-stock listings; biggest saving first', () {
    final deals = dealsFrom([
      _p('full', 100),
      _p('small', 90, was: 100), // 10%
      _p('big', 50, was: 100), // 50%
      _p('sold-out', 40, was: 100, stock: 0),
      _p('paused', 40, was: 100, active: false),
      _p('fake', 120, was: 100), // "was" lower than now: not a deal
    ]);
    expect(deals.map((p) => p.id), ['big', 'small']);
  });

  test('capped so the strip stays short', () {
    final many = [for (var i = 0; i < 20; i++) _p('d$i', 50, was: 100)];
    expect(dealsFrom(many), hasLength(8));
  });
}

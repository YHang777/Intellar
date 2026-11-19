import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/order.dart';
import 'package:interior_design_recommendation/services/marketplace_repository.dart';

class _Repo implements MarketplaceRepository {
  _Repo(this.orders);
  final List<Order> orders;
  @override
  Stream<List<Order>> watchSupplierOrders(String supplierId) =>
      Stream.value(orders);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not stubbed: ${invocation.memberName}');
}

Order _order(String id, PaymentStatus pay, OrderStatus status) => Order(
      id: id,
      orderNumber: id,
      customerId: 'c1',
      customerName: 'A',
      customerEmail: 'a@b.com',
      customerPhone: '0123',
      items: const [],
      status: status,
      paymentMethod: 'card_fpx',
      paymentStatus: pay,
      subtotal: 100,
      total: 106,
      createdAt: DateTime(2026, 11, 19),
    );

void main() {
  test('sellers never see orders that were not paid', () async {
    final container = ProviderContainer(overrides: [
      marketplaceRepositoryProvider.overrideWithValue(_Repo([
        _order('paid', PaymentStatus.paid, OrderStatus.pending),
        _order('at-checkout', PaymentStatus.unpaid, OrderStatus.pending),
        _order('failed', PaymentStatus.failed, OrderStatus.cancelled),
        _order('refunded', PaymentStatus.refunded, OrderStatus.cancelled),
      ])),
    ]);
    addTearDown(container.dispose);

    final orders = await container.read(supplierOrdersProvider('s1').future);
    expect(orders.map((o) => o.id), ['paid', 'refunded']);
  });
}

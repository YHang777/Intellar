import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_product_mapper.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_state_context.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _p(String id, {String style = 'Modern', int price = 300, bool eco = false, int sold = 0, bool active = true}) =>
    Product.fromJson({
      'id': id,
      'name': id,
      'price': price,
      'stock': 5,
      'designStyle': style,
      'isEcoFriendly': eco,
      'soldCount': sold,
      'isActive': active,
      'createdAt': '2026-11-1${id.length}T00:00:00Z',
      'supplier': {'id': 's', 'name': 'S'},
    });

void main() {
  final all = [
    _p('a', style: 'Modern', price: 150, eco: true, sold: 4),
    _p('bb', style: 'Classic', price: 450, sold: 9),
    _p('ccc', style: 'Modern', price: 900),
    _p('dddd', style: 'Modern', price: 120, active: false),
  ];

  List<String> ids(ChatFilters f) =>
      productsToChatContext(all, filters: f).map((p) => p.id).toList();

  test('no filters: every live product, as before', () {
    expect(ids(const ChatFilters()).toSet(), {'a', 'bb', 'ccc'});
  });

  test('the assistant only ever sees products that match', () {
    expect(ids(const ChatFilters(style: 'modern')).toSet(), {'a', 'ccc'},
        reason: 'style match ignores letter case');
    expect(ids(const ChatFilters(maxPrice: 500)).toSet(), {'a', 'bb'});
    expect(ids(const ChatFilters(ecoOnly: true)), ['a']);
    expect(ids(const ChatFilters(style: 'Modern', maxPrice: 500, ecoOnly: true)), ['a']);
    expect(ids(const ChatFilters(style: 'Bohemian')), isEmpty);
  });

  test('popular only keeps sold pieces, best sellers first', () {
    expect(ids(const ChatFilters(popularOnly: true)), ['bb', 'a']);
  });

  test('filters reach the assistant state block only when set', () {
    expect(const ChatFilters().toChatJson(), isNull);
    final state = buildChatStateJson(
      cartRows: const [],
      cartCount: 0,
      cartSubtotal: 0,
      budget: null,
      orders: const [],
      plan: null,
      pendingPlacements: 0,
      filters: const ChatFilters(style: 'Modern', maxPrice: 500).toChatJson(),
    );
    expect(state?['filters'], {'style': 'Modern', 'maxPrice': 500});
  });

  test('copyWith can clear individual filters', () {
    const f = ChatFilters(style: 'Modern', maxPrice: 500, ecoOnly: true);
    expect(f.activeCount, 3);
    expect(f.copyWith(clearStyle: true).style, isNull);
    expect(f.copyWith(clearMaxPrice: true).maxPrice, isNull);
    expect(f.copyWith(ecoOnly: false).isEmpty, isFalse);
  });
}

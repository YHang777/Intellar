import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/product.dart';

/// The catalogue provider is a stream — wait for its first emission before
/// reading any state derived from it.
Future<void> _settle(ProviderContainer container) =>
    container.read(marketplaceProductsProvider.future);

Product _p(String id, {int soldCount = 0, int ratingCount = 0}) {
  final now = DateTime(2026, 11, 17);
  return Product(
    id: id,
    name: 'Item $id',
    price: 100,
    stock: 5,
    image: 'assets/images/none.png',
    description: 'A test piece',
    designStyle: 'Modern',
    category: 'Furniture',
    supplier: const Supplier(
        id: 's1', name: 'Store', phone: '', address: '', email: ''),
    soldCount: soldCount,
    ratingCount: ratingCount,
    createdAt: now,
  );
}

void main() {
  test('soldCount parses, clamps, and is never written by a client save', () {
    // toJson deliberately omits it: it is the backend's counter, and a
    // client-side save must not be able to invent sales.
    expect(_p('a', soldCount: 7).toJson().containsKey('soldCount'), isFalse);

    expect(
      Product.fromJson({..._p('a').toJson(), 'soldCount': 7}).soldCount,
      7,
    );
    expect(Product.fromJson({..._p('a').toJson()}).soldCount, 0,
        reason: 'a doc without a counter reads as zero');
    expect(
      Product.fromJson({..._p('a').toJson(), 'soldCount': -3}).soldCount,
      0,
      reason: 'a rollback race must not show negative sales',
    );
  });

  test('popularity sort puts what sells on top, rating as the tiebreak',
      () async {
    final products = [
      _p('quiet', soldCount: 1, ratingCount: 9),
      _p('best', soldCount: 20),
      _p('mid', soldCount: 5),
      _p('tieA', soldCount: 3, ratingCount: 4),
      _p('tieB', soldCount: 3, ratingCount: 12),
    ];
    final container = ProviderContainer(overrides: [
      marketplaceProductsProvider.overrideWith((ref) => Stream.value(products)),
    ]);
    addTearDown(container.dispose);
    container.read(sortOptionProvider.notifier).state = SortOption.popularity;
    await _settle(container);

    final sorted = container.read(filteredProductsProvider);
    expect(sorted.map((p) => p.id).toList(),
        ['best', 'mid', 'tieB', 'tieA', 'quiet']);
  });

  test('popular-only filter shows just what sold, and clears cleanly', () async {
    final products = [_p('sold', soldCount: 3), _p('never', soldCount: 0)];
    final container = ProviderContainer(overrides: [
      marketplaceProductsProvider.overrideWith((ref) => Stream.value(products)),
    ]);
    addTearDown(container.dispose);
    await _settle(container);

    expect(container.read(filteredProductsProvider), hasLength(2));
    container.read(popularOnlyProvider.notifier).state = true;
    await _settle(container);
    expect(container.read(filteredProductsProvider).map((p) => p.id), ['sold']);
    expect(container.read(marketplaceFilterStateProvider).popularActive, isTrue);
    expect(container.read(activeFilterCountProvider), 1);

    resetMarketplaceFilters(_FakeRef(container));
    await _settle(container);
    expect(container.read(popularOnlyProvider), isFalse,
        reason: 'Clear all resets popularity too');
    expect(container.read(filteredProductsProvider), hasLength(2));
  });

  test('popularity is its own sort option with buyer-facing labels', () {
    expect(SortOption.popularity.label, 'Most Popular');
    expect(SortOption.popularity.chipLabel, 'Most Popular');
    expect(SortOption.values.length, 6);
    expect(SortOption.values, contains(SortOption.topRated));
  });
}

class _FakeRef implements WidgetRef {
  _FakeRef(this.container);
  final ProviderContainer container;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #read || name == #watch) {
      // ignore: avoid_dynamic_calls
      final provider = invocation.positionalArguments.first;
      return container.read(provider as ProviderListenable<dynamic>);
    }
    return super.noSuchMethod(invocation);
  }
}

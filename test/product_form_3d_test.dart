import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/providers/supplier_providers.dart';
import 'package:interior_design_recommendation/features/supplier/presentation/screens/product_form_screen.dart';

void main() {
  testWidgets('size fields appear only after ticking Generate a 3D model',
      (tester) async {
    tester.view.physicalSize = const Size(430, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        marketplaceProductsProvider.overrideWith((ref) => Stream.value(const [])),
        categoriesProvider.overrideWith((ref) async => const []),
        stylesProvider.overrideWith((ref) async => const ['Modern']),
        currentSupplierProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(home: ProductFormScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Generate a 3D model'), findsOneWidget);
    expect(find.text('Width (m)'), findsNothing, reason: 'off by default');

    await tester.ensureVisible(find.byKey(const Key('want-3d')));
    await tester.tap(find.byKey(const Key('want-3d')));
    await tester.pumpAndSettle();
    expect(find.text('Width (m)'), findsOneWidget);
    expect(find.text('Depth (m)'), findsOneWidget);
  });
}

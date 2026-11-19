import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/ar_previews.dart';
import 'package:interior_design_recommendation/features/customer/ar/presentation/screens/ar_previews_screen.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/dashboard_ar_previews.dart';

Future<void> _pump(WidgetTester tester, List<ArPreview> previews) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [arPreviewsProvider.overrideWith((ref) async => previews)],
    child: const MaterialApp(home: Scaffold(body: DashboardArPreviews())),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('no previews: no empty section on the dashboard', (tester) async {
    await _pump(tester, const []);
    expect(find.byKey(const Key('dashboard-ar-previews')), findsNothing);
  });

  testWidgets('saved previews show with a count (FR19)', (tester) async {
    await _pump(tester, [
      ArPreview(id: 'a', label: 'Sofa in lounge', path: '/missing/a.png',
          createdAt: DateTime(2026, 11, 19)),
      ArPreview(id: 'b', label: 'Lamp', path: '/missing/b.png',
          createdAt: DateTime(2026, 11, 18)),
    ]);
    expect(find.byKey(const Key('dashboard-ar-previews')), findsOneWidget);
    expect(find.text('AR previews'), findsOneWidget);
    expect(find.text('See all (2)'), findsOneWidget);
  });
}

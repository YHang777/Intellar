import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/presentation/widgets/ar_first_run_guide.dart';

Widget _host(ArGuideStep step, {double progress = 0.3, VoidCallback? onSkip}) =>
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.grey,
        body: ArFirstRunGuide(
            step: step, progress: progress, onSkip: onSkip ?? () {}),
      ),
    );

void main() {
  testWidgets('floor step shows the scene card, ring and a short caption',
      (tester) async {
    await tester.pumpWidget(_host(ArGuideStep.floor));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ar-guide-card')), findsOneWidget);
    expect(find.byKey(const Key('ar-guide-ring')), findsOneWidget);
    expect(find.text('Sweep the floor slowly'), findsOneWidget);
  });

  testWidgets('wall step explains the ticks', (tester) async {
    await tester.pumpWidget(_host(ArGuideStep.walls));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Now aim up at the walls'), findsOneWidget);
    expect(find.textContaining('means done'), findsOneWidget);
  });

  testWidgets('Skip calls back; the done state hides the ring and Skip',
      (tester) async {
    var skipped = false;
    await tester.pumpWidget(_host(ArGuideStep.floor, onSkip: () => skipped = true));
    await tester.tap(find.byKey(const Key('ar-guide-skip')));
    expect(skipped, isTrue);
    await tester.pumpWidget(_host(ArGuideStep.done));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ar-guide-ring')), findsNothing);
    expect(find.byKey(const Key('ar-guide-skip')), findsNothing);
    expect(find.text('You’re all set'), findsOneWidget);
  });
}

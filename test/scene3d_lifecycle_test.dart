import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/scene3d_controller.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/scene3d_view.dart';

Key? _viewKey(WidgetTester tester) =>
    tester.widget<AndroidView>(find.byType(AndroidView)).key;

void main() {
  testWidgets('returning from the background recreates the 3D view',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scene3DView(controller: Scene3DController()),
      ));
      final before = _viewKey(tester);

      // A brief interruption (notification shade) keeps the same view.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_viewKey(tester), before);

      // The share sheet / home button hides the app: rebuild on return.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_viewKey(tester), isNot(before));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

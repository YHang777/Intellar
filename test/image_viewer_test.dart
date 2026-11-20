import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/shared/widgets/image_viewer.dart';

void main() {
  testWidgets('opens full screen, swipes, and returns the photo ended on',
      (tester) async {
    int? result = -1;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showImageViewer(context,
                    images: const ['', '', ''], initialIndex: 0);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Pinch or double-tap to zoom'), findsOneWidget);

    await tester.fling(find.byKey(const Key('image-viewer-pages')),
        const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('image-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsNothing);
    expect(result, 1);
  });

  testWidgets('a single photo shows no counter', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ImageViewer(images: ['']),
    ));
    await tester.pump();
    expect(find.textContaining(' / '), findsNothing);
  });
}

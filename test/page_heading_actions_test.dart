import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/shared/widgets/page_heading.dart';

// Fits a 411dp row at full size in the test font (glyphs are fontSize-wide
// squares), so any squeeze from the actions shows up as a smaller title.
const _title = 'Store profile';

Widget _heading({List<Widget>? actions}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: PageHeading(
            title: _title,
            subtitle: 'Ready to design your space?',
            actions: actions,
          ),
        ),
      ),
    );

// Rendered height, after any FittedBox scaling (corners go through the
// transform, unlike getSize).
double _titleHeight(WidgetTester tester) {
  final f = find.text(_title);
  return tester.getBottomLeft(f).dy - tester.getTopLeft(f).dy;
}

void main() {
  setUp(() {});

  testWidgets('a top-right icon does not shrink the greeting', (tester) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_heading());
    await tester.pump();
    final bare = _titleHeight(tester);

    await tester.pumpWidget(_heading(actions: const [
      Icon(Icons.notifications_outlined, key: Key('bell')),
    ]));
    await tester.pump();

    expect(_titleHeight(tester), closeTo(bare, 0.5),
        reason: 'the greeting must keep its size beside one icon');
  });

  testWidgets('actions sit at the right edge, not mid-row', (tester) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_heading(actions: const [
      Icon(Icons.notifications_outlined, key: Key('bell')),
      Icon(Icons.edit_outlined, key: Key('edit')),
    ]));
    await tester.pump();

    expect(tester.getTopRight(find.byKey(const Key('edit'))).dx,
        closeTo(411, 1));
    // Top-aligned with the title, not vertically centred against the
    // subtitle block.
    expect(tester.getTopLeft(find.byKey(const Key('bell'))).dy,
        closeTo(tester.getTopLeft(find.byType(PageHeading)).dy, 1));
  });

  testWidgets('icons keep their full size', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_heading(actions: const [
      Icon(Icons.notifications_outlined, key: Key('bell')),
      Icon(Icons.edit_outlined, key: Key('edit')),
    ]));
    await tester.pump();

    final bell = find.byKey(const Key('bell'));
    expect(tester.getBottomRight(bell).dx - tester.getTopLeft(bell).dx,
        closeTo(24, 0.5));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/ar_previews.dart';
import 'package:interior_design_recommendation/features/customer/ar/presentation/screens/ar_previews_screen.dart';

/// A tiny but real PNG, so `Image.file` in the widget tests can decode it.
const _png1x1 = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory docs;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('ar-previews-');
  });

  tearDown(() async {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  group('ArPreviewStore', () {
    test('saves a PNG and lists it newest first', () async {
      final store = ArPreviewStore(root: docs);
      final first = await store.save(Uint8List.fromList(_png1x1), label: 'Oak floor');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second =
          await store.save(Uint8List.fromList(_png1x1), label: '  Walnut floor  ');

      expect(File(first.path).existsSync(), isTrue);
      expect(second.label, 'Walnut floor', reason: 'labels are trimmed');

      final list = await store.list();
      expect(list.map((p) => p.label).toList(),
          ['Walnut floor', 'Oak floor']);
      expect(list.first.path, second.path);
    });

    test('an empty label falls back to a sensible default', () async {
      final store = ArPreviewStore(root: docs);
      final p = await store.save(Uint8List.fromList(_png1x1), label: '   ');
      expect(p.label, 'AR preview');
    });

    test('delete removes the file and the row', () async {
      final store = ArPreviewStore(root: docs);
      final keep = await store.save(Uint8List.fromList(_png1x1), label: 'Keep');
      final gone = await store.save(Uint8List.fromList(_png1x1), label: 'Gone');

      await store.delete(gone.id);
      expect(File(gone.path).existsSync(), isFalse);
      expect(File(keep.path).existsSync(), isTrue);
      expect((await store.list()).map((p) => p.id), [keep.id]);
    });

    test('rows whose file vanished are not listed as history', () async {
      final store = ArPreviewStore(root: docs);
      final a = await store.save(Uint8List.fromList(_png1x1), label: 'A');
      await store.save(Uint8List.fromList(_png1x1), label: 'B');
      File(a.path).deleteSync();

      expect((await store.list()).map((p) => p.label), ['B']);
    });

    test('sharing a preview that is gone is refused with a clear error',
        () async {
      final store = ArPreviewStore(root: docs);
      final p = await store.save(Uint8List.fromList(_png1x1), label: 'A');
      File(p.path).deleteSync();
      await expectLater(
          store.share(p), throwsA(isA<FileSystemException>()));
    });
  });

  group('ArPreviewsScreen', () {
    ArPreview preview(String id, String label) => ArPreview(
        id: id,
        label: label,
        path: '${docs.path}/$id.png',
        createdAt: DateTime(2026, 11, 17, 10));

    Widget screen(FakeStore store) => ProviderScope(
          overrides: [arPreviewStoreProvider.overrideWithValue(store)],
          child: const MaterialApp(home: ArPreviewsScreen()),
        );

    testWidgets('shows saved previews and hides compare when only one',
        (tester) async {
      final store = FakeStore([preview('a', 'Oak floor')]);
      await tester.pumpWidget(screen(store));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Oak floor'), findsOneWidget);
      expect(find.textContaining('1 saved'), findsOneWidget);
      expect(find.byKey(const Key('ar-preview-compare')), findsNothing,
          reason: 'compare needs at least two');
      expect(find.text('No previews yet'), findsNothing);
    });

    testWidgets('empty state explains what saving a preview is for',
        (tester) async {
      await tester.pumpWidget(screen(FakeStore(const [])));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No previews yet'), findsOneWidget);
    });

    testWidgets('compare opens a side-by-side view of the two picks',
        (tester) async {
      final store = FakeStore([
        preview('a', 'Oak floor'),
        preview('b', 'Tile'),
      ]);
      await tester.pumpWidget(screen(store));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('ar-preview-compare')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pick two to compare'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ar-preview-a')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('ar-preview-b')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('ar-preview-do-compare')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ar-preview-do-compare')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Oak floor'), findsNWidgets(2),
          reason: 'the list behind and the compare view both show it');
      expect(find.text('Tile'), findsNWidgets(2));
      expect(find.byKey(const Key('compare-share')), findsOneWidget);
      expect(find.text('Compare'), findsOneWidget);
    });

    testWidgets('a photo can be deleted straight from its card menu',
        (tester) async {
      final store = FakeStore([preview('a', 'Oak floor'), preview('b', 'Tile')]);
      await tester.pumpWidget(screen(store));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('ar-preview-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete this photo?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.deleted, ['a']);
      expect(find.text('Oak floor'), findsNothing);
      expect(find.text('Tile'), findsOneWidget);
    });

    testWidgets('deleting from the photo view closes it', (tester) async {
      final store = FakeStore([preview('a', 'Oak floor'), preview('b', 'Tile')]);
      await tester.pumpWidget(screen(store));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('ar-preview-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ar-preview-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.deleted, ['a']);
      expect(find.byKey(const Key('ar-preview-delete')), findsNothing,
          reason: 'back on the list, not a page for a deleted photo');
      expect(find.text('Tile'), findsOneWidget);
    });

    testWidgets('tapping a preview in compare mode selects it, not opens it',
        (tester) async {
      final store = FakeStore([
        preview('a', 'Oak floor'),
        preview('b', 'Tile'),
      ]);
      await tester.pumpWidget(screen(store));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('ar-preview-compare')));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('ar-preview-a')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byKey(const Key('ar-preview-share')), findsNothing);
    });
  });
}

/// Stands in for the on-disk store so widget tests never touch a platform
/// channel (which never completes under `testWidgets`).
class FakeStore extends ArPreviewStore {
  FakeStore(this.previews, {this.failShare = false});
  List<ArPreview> previews;
  final bool failShare;
  final deleted = <String>[];
  final shared = <ArPreview>[];

  @override
  Future<List<ArPreview>> list() async => previews;

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    previews = previews.where((p) => p.id != id).toList();
  }

  @override
  Future<void> share(ArPreview preview) async {
    if (failShare) throw const FileSystemException('nope');
    shared.add(preview);
  }
}

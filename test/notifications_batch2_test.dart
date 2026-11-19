import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/notifications/data/app_notification.dart';
import 'package:interior_design_recommendation/features/notifications/data/notifications_repository.dart';
import 'package:interior_design_recommendation/features/notifications/presentation/notifications_screen.dart';
import 'package:interior_design_recommendation/services/notify/notify_client.dart';

AppUser _user({UserRole role = UserRole.homeowner}) {
  final now = DateTime(2026, 11, 17);
  return AppUser(
    uid: 'u1',
    email: 'a@b.com',
    name: 'A',
    role: role,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeRepo extends NotificationsRepository {
  final read = <String>[];
  final allRead = <String>[];

  @override
  Future<void> markRead(String uid, String id) async => read.add(id);

  @override
  Future<void> markAllRead(String uid, Iterable<String> ids) async =>
      allRead.addAll(ids);
}

void main() {
  group('AppNotification', () {
    test('parses the inbox row and its deep-link data', () {
      final n = AppNotification.fromMap('n1', {
        'kind': 'order_update',
        'title': 'Order confirmed',
        'body': 'Hi',
        'data': {'orderId': 'o1', 'productId': ''},
        'read': false,
        'createdAt': DateTime(2026, 11, 17, 9),
      });
      expect(n.orderId, 'o1');
      expect(n.productId, isNull, reason: 'empty strings are no link');
      expect(n.read, isFalse);
      expect(n.createdAt, DateTime(2026, 11, 17, 9));
    });

    test('taps route by role and payload', () {
      expect(routeForNotification(isSupplier: false, orderId: 'o1'),
          '/marketplace/orders/o1');
      expect(routeForNotification(isSupplier: true, orderId: 'o1'),
          '/supplier/orders/o1');
      expect(routeForNotification(isSupplier: false, quoteId: 'q1'),
          '/marketplace/orders?tab=quotes');
      expect(routeForNotification(isSupplier: true, quoteId: 'q1'),
          '/supplier/quotes/q1');
      expect(routeForNotification(isSupplier: false, productId: 'p1'),
          '/marketplace/product/p1');
      // A seller's low-stock notice opens the listing to restock it.
      expect(routeForNotification(isSupplier: true, productId: 'p1'),
          '/supplier/products/p1/edit');
      expect(routeForNotification(isSupplier: false), isNull);
    });
  });

  group('NotifyClient', () {
    test('posts with the bearer token and never throws', () async {
      late http.Request seen;
      final c = NotifyClient(
        client: MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
        idTokenProvider: () async => 'tok',
        baseUrl: 'https://api.test',
      );
      expect(await c.send('/api/notify/quote', {'quoteId': 'q1', 'event': 'created'}),
          isTrue);
      expect(seen.url.toString(), 'https://api.test/api/notify/quote');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body), {'quoteId': 'q1', 'event': 'created'});

      final failing = NotifyClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
        idTokenProvider: () async => 'tok',
        baseUrl: 'https://api.test',
        retryDelay: Duration.zero,
      );
      expect(await failing.send('/api/audit', {'action': 'x'}), isFalse);
    });

    test('a waking server gets one retry; a refusal does not', () async {
      var calls = 0;
      final waking = NotifyClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', calls == 1 ? 503 : 200);
        }),
        idTokenProvider: () async => 'tok',
        baseUrl: 'https://api.test',
        retryDelay: Duration.zero,
      );
      expect(await waking.send('/api/notify/order-status', {'orderId': 'o1'}),
          isTrue);
      expect(calls, 2);

      var refused = 0;
      final forbidden = NotifyClient(
        client: MockClient((_) async {
          refused++;
          return http.Response('{}', 403);
        }),
        idTokenProvider: () async => 'tok',
        baseUrl: 'https://api.test',
        retryDelay: Duration.zero,
      );
      expect(await forbidden.send('/api/notify/order-status', {'orderId': 'o1'}),
          isFalse);
      expect(refused, 1);
    });

    test('signed-out callers send nothing', () async {
      var calls = 0;
      final c = NotifyClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
        idTokenProvider: () async => null,
        baseUrl: 'https://api.test',
      );
      expect(await c.send('/api/audit', {'action': 'x'}), isFalse);
      expect(calls, 0);
    });
  });

  group('inbox', () {
    final items = [
      AppNotification(
          id: 'n1',
          kind: 'order_update',
          title: 'Ready for collection',
          body: 'Order ORD-1 is ready',
          data: const {'orderId': 'o1'},
          createdAt: DateTime(2026, 11, 17, 9, 30)),
      AppNotification(
          id: 'n2',
          kind: 'quote',
          title: 'The seller contacted you',
          body: 'About Sofa',
          data: const {'quoteId': 'q1'},
          read: true,
          createdAt: DateTime(2026, 11, 16, 8)),
    ];

    Future<(_FakeRepo, List<String>)> pump(WidgetTester tester,
        List<AppNotification> list) async {
      final repo = _FakeRepo();
      final pushed = <String>[];
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const NotificationsScreen()),
        GoRoute(
            path: '/marketplace/orders/:id',
            builder: (_, s) {
              pushed.add(s.uri.toString());
              return const Scaffold(body: Text('order page'));
            }),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user()),
          notificationsRepositoryProvider.overrideWithValue(repo),
          notificationsProvider.overrideWith((ref) => Stream.value(list)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return (repo, pushed);
    }

    testWidgets('lists rows, marks one read and opens its order',
        (tester) async {
      final (repo, pushed) = await pump(tester, items);
      expect(find.text('1 unread'), findsOneWidget);
      expect(find.byKey(const Key('unread-dot')), findsOneWidget);
      await tester.tap(find.byKey(const Key('notification-n1')));
      await tester.pumpAndSettle();
      expect(repo.read, ['n1']);
      expect(pushed, ['/marketplace/orders/o1']);
    });

    testWidgets('mark all as read sends only unread ids', (tester) async {
      final (repo, _) = await pump(tester, items);
      await tester.tap(find.byKey(const Key('mark-all-read')));
      await tester.pumpAndSettle();
      expect(repo.allRead, ['n1']);
    });

    testWidgets('empty inbox explains what will appear', (tester) async {
      await pump(tester, const []);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.byKey(const Key('mark-all-read')), findsNothing);
    });

    testWidgets('the bell shows the unread count', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_user()),
          notificationsProvider.overrideWith((ref) => Stream.value(items)),
        ],
        child: const MaterialApp(home: Scaffold(body: NotificationBell())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('1 unread notifications'), findsOneWidget);
    });
  });
}

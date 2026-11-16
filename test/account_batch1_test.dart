import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:interior_design_recommendation/app.dart';
import 'package:interior_design_recommendation/core/accessibility/accessibility_settings.dart';
import 'package:interior_design_recommendation/core/constants/app_colors.dart';
import 'package:interior_design_recommendation/features/auth/data/datasources/account_deletion_datasource.dart';
import 'package:interior_design_recommendation/features/auth/data/datasources/security_code_datasource.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/data/models/user_preferences.dart';
import 'package:interior_design_recommendation/features/auth/data/repositories/account_settings_repository.dart';
import 'package:interior_design_recommendation/features/auth/domain/repositories/auth_repository.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/auth/presentation/screens/two_factor_screen.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_state_context.dart';
import 'package:interior_design_recommendation/features/onboarding/presentation/onboarding_screen.dart';
import 'package:interior_design_recommendation/features/settings/presentation/screens/accessibility_settings_screen.dart';
import 'package:interior_design_recommendation/features/settings/presentation/screens/design_preferences_screen.dart';

AppUser _user({
  bool twoFactorEnabled = false,
  bool twoFactorPending = false,
  bool onboardingCompleted = true,
  UserRole role = UserRole.homeowner,
  DesignPreferences prefs = const DesignPreferences(),
}) {
  final now = DateTime(2026, 11, 1);
  return AppUser(
    uid: 'u1',
    email: 'owner@example.com',
    name: 'Owner',
    role: role,
    twoFactorEnabled: twoFactorEnabled,
    twoFactorPending: twoFactorPending,
    onboardingCompleted: onboardingCompleted,
    designPreferences: prefs,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppColors.highContrast = false;
  });

  group('preference models', () {
    test('AppUser reads the new profile fields from Firestore', () {
      final u = AppUser.fromFirestore(uid: 'u1', email: 'a@b.com', data: {
        'name': 'A',
        'role': 'homeowner',
        'twoFactorEnabled': true,
        'designPreferences': {
          'styles': ['Japandi', '  ', 'Modern'],
          'colours': ['Warm neutrals'],
          'ecoFriendly': true,
          'notes': ' cats ',
        },
        'notificationSettings': {'promotions': false},
        'privacySettings': {'shareDesignsWithAssistant': false},
      });
      expect(u.twoFactorEnabled, isTrue);
      expect(u.twoFactorPending, isFalse);
      expect(u.onboardingCompleted, isFalse,
          reason: 'a profile that never finished the tour sees it once');
      expect(u.designPreferences.styles, ['Japandi', 'Modern']);
      expect(u.designPreferences.notes, 'cats');
      expect(u.notificationSettings.promotions, isFalse);
      expect(u.notificationSettings.orderUpdates, isTrue);
      expect(u.privacySettings.shareDesignsWithAssistant, isFalse);
      expect(u.privacySettings.personalisedRecommendations, isTrue);
    });

    test('preferences become a compact chat block and vanish when empty', () {
      expect(const DesignPreferences().toChatJson(), isNull);
      final json = DesignPreferences(
        styles: const ['Scandinavian'],
        materials: const ['Wood'],
        ecoFriendly: true,
        notes: 'x' * 300,
      ).toChatJson()!;
      expect(json['styles'], ['Scandinavian']);
      expect(json.containsKey('colours'), isFalse);
      expect(json['ecoFriendly'], isTrue);
      expect((json['notes'] as String).length, DesignPreferences.maxNotes);
    });

    test('chat state carries preferences next to the other sections', () {
      final state = buildChatStateJson(
        cartRows: const [],
        cartCount: 0,
        cartSubtotal: 0,
        budget: null,
        orders: const [],
        plan: null,
        pendingPlacements: 0,
        preferences: const DesignPreferences(styles: ['Japandi']).toChatJson(),
      );
      expect(state, {
        'preferences': {
          'styles': ['Japandi']
        }
      });
      expect(
        buildChatStateJson(
          cartRows: const [],
          cartCount: 0,
          cartSubtotal: 0,
          budget: null,
          orders: const [],
          plan: null,
          pendingPlacements: 0,
        ),
        isNull,
      );
    });
  });

  group('SecurityCodeDatasource', () {
    SecurityCodeDatasource ds(MockClientHandler handler) =>
        SecurityCodeDatasource(
            client: MockClient(handler), idTokenProvider: () async => 'tok');

    test('sends the bearer token and parses the masked address', () async {
      late http.Request seen;
      final sent = await ds((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'sentTo': 'ow***@example.com',
              'expiresAt': '2026-11-16T10:10:00.000Z'
            }),
            200);
      }).sendLoginCode();
      expect(seen.url.path, '/api/account/2fa/send');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(sent.sentTo, 'ow***@example.com');
      expect(sent.expiresAt, isNotNull);
    });

    test('surfaces the server sentence and attempts left', () async {
      final call = ds((req) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'INVALID_CODE',
              'message': 'That code is not right.',
              'details': {'attemptsLeft': 3}
            }
          }),
          400)).verifyLoginCode('123456');
      await expectLater(
          call,
          throwsA(isA<SecurityCodeException>()
              .having((e) => e.message, 'message', 'That code is not right.')
              .having((e) => e.attemptsLeft, 'attemptsLeft', 3)
              .having((e) => e.code, 'code', 'INVALID_CODE')));
    });

    test('an expired session reads as a plain sentence', () async {
      final call = ds((req) async => http.Response('{}', 401))
          .confirmEmailChange('123456');
      await expectLater(
          call,
          throwsA(isA<SecurityCodeException>().having((e) => e.message,
              'message', 'Your session expired. Please sign in again.')));
    });
  });

  group('AuthStateNotifier account actions', () {
    test('verifying the code clears the pending gate', () async {
      final repo = _FakeAuthRepository(_user(
          twoFactorEnabled: true, twoFactorPending: true));
      final settings = _FakeSettings();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        accountSettingsRepositoryProvider.overrideWithValue(settings),
      ]);
      addTearDown(container.dispose);
      await container.read(authStateProvider.notifier).login('a', 'b');
      expect(container.read(currentUserProvider)!.twoFactorPending, isTrue);

      await container
          .read(authStateProvider.notifier)
          .verifyTwoFactorCode('123456');
      expect(settings.verified, ['123456']);
      expect(container.read(currentUserProvider)!.twoFactorPending, isFalse);
    });

    test('a wrong code keeps the gate closed', () async {
      final repo = _FakeAuthRepository(_user(
          twoFactorEnabled: true, twoFactorPending: true));
      final settings = _FakeSettings()..failVerify = true;
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        accountSettingsRepositoryProvider.overrideWithValue(settings),
      ]);
      addTearDown(container.dispose);
      await container.read(authStateProvider.notifier).login('a', 'b');
      await expectLater(
          container.read(authStateProvider.notifier).verifyTwoFactorCode('1'),
          throwsA(isA<SecurityCodeException>()));
      expect(container.read(currentUserProvider)!.twoFactorPending, isTrue);
    });

    test('saving preferences, settings and the tour patch the user', () async {
      final repo = _FakeAuthRepository(_user(onboardingCompleted: false));
      final settings = _FakeSettings();
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        accountSettingsRepositoryProvider.overrideWithValue(settings),
      ]);
      addTearDown(container.dispose);
      final n = container.read(authStateProvider.notifier);
      await n.login('a', 'b');

      await n.saveDesignPreferences(
          const DesignPreferences(styles: ['Modern']));
      await n.saveNotificationSettings(
          const NotificationSettings(promotions: false));
      await n.savePrivacySettings(
          const PrivacySettings(personalisedRecommendations: false));
      await n.completeOnboarding();
      await n.setTwoFactorEnabled(enabled: true, code: '123456');
      await n.confirmEmailChange('654321');

      final u = container.read(currentUserProvider)!;
      expect(u.designPreferences.styles, ['Modern']);
      expect(u.notificationSettings.promotions, isFalse);
      expect(u.privacySettings.personalisedRecommendations, isFalse);
      expect(u.onboardingCompleted, isTrue);
      expect(u.twoFactorEnabled, isTrue);
      expect(u.email, 'new@example.com');
      expect(settings.savedPrefs?.styles, ['Modern']);
      expect(settings.onboardingDone, isTrue);
    });
  });

  group('router gates', () {
    Future<void> pumpApp(WidgetTester tester, AppUser user) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
          accountSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        ],
        child: const InteriorDesignApp(),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a pending 2FA sign-in lands on the code screen',
        (tester) async {
      await pumpApp(tester,
          _user(twoFactorEnabled: true, twoFactorPending: true));
      expect(find.byType(TwoFactorScreen), findsOneWidget);
      expect(find.textContaining('ow***@example.com'), findsOneWidget);
    });

    testWidgets('a first sign-in opens the tour', (tester) async {
      await pumpApp(tester, _user(onboardingCompleted: false));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Scan your room'), findsOneWidget);
    });

    testWidgets('a supplier tour shows supplier slides', (tester) async {
      await pumpApp(tester,
          _user(onboardingCompleted: false, role: UserRole.supplier));
      expect(find.text('List your products'), findsOneWidget);
    });
  });

  testWidgets('the tour pages through to the preferences call to action',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(_user(onboardingCompleted: false))),
        accountSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      ],
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await tester.pumpAndSettle();
    for (var i = 0; i < homeownerSlides.length - 1; i++) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Make it yours'), findsOneWidget);
    expect(find.text('Set my preferences'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-later')), findsOneWidget);
  });

  testWidgets('design preferences cap each group and save the selection',
      (tester) async {
    final settings = _FakeSettings();
    final repo = _FakeAuthRepository(_user());
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      accountSettingsRepositoryProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);
    await container.read(authStateProvider.notifier).login('a', 'b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DesignPreferencesScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Japandi'));
    await tester.tap(find.widgetWithText(FilterChip, 'Modern'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Modern'));
    await tester.pump();
    await tester.scrollUntilVisible(
        find.byKey(const Key('preference-notes')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byKey(const Key('preference-notes')), 'two cats');
    await tester.tap(find.byKey(const Key('save-preferences')));
    await tester.pumpAndSettle();
    expect(settings.savedPrefs?.styles, ['Japandi']);
    expect(settings.savedPrefs?.notes, 'two cats');
    expect(container.read(currentUserProvider)!.designPreferences.styles,
        ['Japandi']);
  });

  testWidgets('accessibility settings scale text and switch the palette',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(null)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AccessibilitySettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra large'));
    await tester.tap(find.byKey(const Key('high-contrast-switch')));
    await tester.pumpAndSettle();
    final s = container.read(accessibilitySettingsProvider);
    expect(s.textSize, TextSizeOption.extraLarge);
    expect(s.highContrast, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('a11y_text_size'), 'extraLarge');
    expect(prefs.getBool('a11y_high_contrast'), isTrue);
  });

  testWidgets('the app root applies the chosen text scale and contrast',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'a11y_text_size': 'large',
      'a11y_high_contrast': true,
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository(null)),
      ],
      child: const InteriorDesignApp(),
    ));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('Welcome back'));
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(11.5, 0.001));
    expect(MediaQuery.highContrastOf(ctx), isTrue);
    expect(AppColors.textSecondary, const Color(0xFF374151));
    AppColors.highContrast = false;
  });
}

class _FakeSettings extends AccountSettingsRepository {
  final verified = <String>[];
  bool failVerify = false;
  DesignPreferences? savedPrefs;
  bool onboardingDone = false;

  @override
  Future<CodeSent> sendLoginCode() async =>
      const CodeSent(sentTo: 'ow***@example.com');

  @override
  Future<void> verifyLoginCode(String code) async {
    if (failVerify) {
      throw const SecurityCodeException('That code is not right.');
    }
    verified.add(code);
  }

  @override
  Future<bool> setTwoFactor({required bool enabled, required String code}) async =>
      enabled;

  @override
  Future<String> confirmEmailChange(String code) async => 'new@example.com';

  @override
  Future<void> saveDesignPreferences(DesignPreferences prefs) async {
    savedPrefs = prefs;
  }

  @override
  Future<void> saveNotificationSettings(NotificationSettings settings) async {}

  @override
  Future<void> savePrivacySettings(PrivacySettings settings) async {}

  @override
  Future<void> completeOnboarding() async {
    onboardingDone = true;
  }
}

class _FakeAuthRepository implements IAuthRepository {
  _FakeAuthRepository(this.user);

  final AppUser? user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield user;
  }

  @override
  Future<AppUser?> getCurrentUser() async => user;

  @override
  Future<AppUser> login(String email, String password) async => user!;

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) =>
      throw UnimplementedError();

  @override
  Future<AppUser> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) async {}

  @override
  Future<bool> isEmailVerified() async => true;

  @override
  Future<DeletionStatus> requestAccountDeletion(String confirmEmail) async =>
      const DeletionStatus(status: 'none');

  @override
  Future<DeletionStatus> cancelAccountDeletion() async =>
      const DeletionStatus(status: 'none');

  @override
  Future<DeletionStatus> fetchDeletionStatus() async =>
      const DeletionStatus(status: 'none');
}

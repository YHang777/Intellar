import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/account_deletion_datasource.dart';
import '../../data/datasources/firebase_auth_datasource.dart';
import '../../data/datasources/firestore_user_datasource.dart';
import '../../data/datasources/verification_email_datasource.dart';
import '../../data/models/app_user.dart';
import '../../../../models/store_profile.dart';
import '../../data/models/user_preferences.dart';
import '../../data/datasources/security_code_datasource.dart';
import '../../data/repositories/account_settings_repository.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../../../services/notify/notify_client.dart';
import '../../../../services/push/push_service.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepositoryImpl(
    authDatasource: FirebaseAuthDatasource(),
    firestoreDatasource: FirestoreUserDatasource(),
    verificationDatasource: VerificationEmailDatasource(),
    deletionDatasource: AccountDeletionDatasource(),
  );
});

final accountSettingsRepositoryProvider =
    Provider<AccountSettingsRepository>((ref) => AccountSettingsRepository());

class AuthStateNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  final IAuthRepository _repository;
  final AccountSettingsRepository? _settingsOverride;
  AccountSettingsRepository? _settingsLazy;
  StreamSubscription<AppUser?>? _authSub;

  bool _authStreamSuspended = false;

  AccountSettingsRepository get _settings =>
      _settingsOverride ?? (_settingsLazy ??= AccountSettingsRepository());

  AuthStateNotifier(this._repository, {AccountSettingsRepository? settings})
      : _settingsOverride = settings,
        super(const AsyncValue.loading()) {
    _authSub = _repository.authStateChanges().listen(
      (user) {
        if (_authStreamSuspended) return;
        state = AsyncValue.data(user);
      },
      onError: (error, stack) {
        if (_authStreamSuspended) return;
        state = AsyncValue.error(error, stack);
      },
    );
  }

  Future<void> login(String email, String password) async {
    _authStreamSuspended = true;
    state = const AsyncValue<AppUser?>.loading().copyWithPrevious(state);
    try {
      final user = await _repository.login(email, password);
      state = AsyncValue.data(user);
      _authStreamSuspended = false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<AppUser?> register({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? address,
  }) async {
    _authStreamSuspended = true;
    state = const AsyncValue<AppUser?>.loading().copyWithPrevious(state);
    try {
      final user = await _repository.register(
        email: email,
        password: password,
        name: name,
        role: role,
        phone: phone,
        address: address,
      );
      state = AsyncValue.data(null);
      return user;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> logout() async {
    _authStreamSuspended = false;
    await PushService.instance.unregister();
    await _repository.logout();
  }

  Future<void> updateProfile({
    required String name,
    String? phone,
    String? address,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    StoreProfile? storeProfile,
  }) async {
    final updated = await _repository.updateProfile(
      name: name,
      phone: phone,
      address: address,
      businessName: businessName,
      businessPhone: businessPhone,
      businessAddress: businessAddress,
      storeProfile: storeProfile,
    );
    state = AsyncValue.data(updated);
    NotifyClient.instance.audit('profile.update', targetType: 'user');
  }

  AppUser? get _user => state.valueOrNull;

  void _patch(AppUser Function(AppUser u) change) {
    final user = _user;
    if (user != null) state = AsyncValue.data(change(user));
  }

  Future<CodeSent> sendTwoFactorCode() => _settings.sendLoginCode();

  Future<void> verifyTwoFactorCode(String code) async {
    await _settings.verifyLoginCode(code);
    _patch((u) => u.copyWith(twoFactorPending: false));
  }

  Future<void> setTwoFactorEnabled({
    required bool enabled,
    required String code,
  }) async {
    final result = await _settings.setTwoFactor(enabled: enabled, code: code);
    _patch((u) => u.copyWith(twoFactorEnabled: result, twoFactorPending: false));
  }

  Future<CodeSent> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) =>
      _settings.requestEmailChange(
          newEmail: newEmail, currentPassword: currentPassword);

  Future<void> confirmEmailChange(String code) async {
    final email = await _settings.confirmEmailChange(code);
    _patch((u) => u.copyWith(email: email));
  }

  Future<void> saveDesignPreferences(DesignPreferences prefs) async {
    await _settings.saveDesignPreferences(prefs);
    _patch((u) => u.copyWith(designPreferences: prefs));
    NotifyClient.instance.audit('preferences.update', targetType: 'user');
  }

  Future<void> saveNotificationSettings(NotificationSettings settings) async {
    await _settings.saveNotificationSettings(settings);
    _patch((u) => u.copyWith(notificationSettings: settings));
    NotifyClient.instance.audit('settings.update',
        targetType: 'user', details: {'area': 'notifications'});
  }

  Future<void> savePrivacySettings(PrivacySettings settings) async {
    await _settings.savePrivacySettings(settings);
    _patch((u) => u.copyWith(privacySettings: settings));
    NotifyClient.instance.audit('settings.update',
        targetType: 'user', details: {'area': 'privacy'});
  }

  Future<void> completeOnboarding() async {
    _patch((u) => u.copyWith(onboardingCompleted: true));
    try {
      await _settings.completeOnboarding();
    } catch (_) {}
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _repository.sendPasswordResetEmail(email);
  }

  Future<void> resendVerificationEmail({
    required String email,
    required String uid,
  }) {
    return _repository.resendVerificationEmail(email: email, uid: uid);
  }

  Future<DeletionStatus> requestAccountDeletion(String confirmEmail) {
    return _repository.requestAccountDeletion(confirmEmail);
  }

  Future<DeletionStatus> cancelAccountDeletion() {
    return _repository.cancelAccountDeletion();
  }

  Future<DeletionStatus> fetchDeletionStatus() {
    return _repository.fetchDeletionStatus();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AsyncValue<AppUser?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthStateNotifier(repository,
      settings: ref.watch(accountSettingsRepositoryProvider));
});

class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier(StateNotifier<AsyncValue<AppUser?>> authNotifier) {
    _removeListener = authNotifier.addListener((_) => notifyListeners());
  }

  late final VoidCallback _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}

final authRefreshProvider = Provider<AuthRefreshNotifier>((ref) {
  final authNotifier = ref.watch(authStateProvider.notifier);
  final notifier = AuthRefreshNotifier(authNotifier);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (user) => user != null) ?? false;
});

final currentUserRoleProvider = Provider<UserRole?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (user) => user?.role);
});

final currentUserProvider = Provider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (user) => user);
});

final deletionStatusProvider = FutureProvider<DeletionStatus>((ref) async {
  final signedIn = ref.watch(isAuthenticatedProvider);
  if (!signedIn) return const DeletionStatus(status: 'none');
  return ref.watch(authRepositoryProvider).fetchDeletionStatus();
});

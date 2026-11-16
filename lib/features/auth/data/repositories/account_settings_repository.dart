import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/repositories/auth_repository.dart';
import '../datasources/firestore_user_datasource.dart';
import '../datasources/security_code_datasource.dart';
import '../datasources/two_factor_device_store.dart';
import '../models/user_preferences.dart';

class AccountSettingsRepository {
  AccountSettingsRepository({
    FirestoreUserDatasource? users,
    SecurityCodeDatasource? codes,
    TwoFactorDeviceStore? deviceStore,
    fb.FirebaseAuth? auth,
  })  : _usersOverride = users,
        _codesOverride = codes,
        _deviceStore = deviceStore ?? const TwoFactorDeviceStore(),
        _authOverride = auth;

  final FirestoreUserDatasource? _usersOverride;
  final SecurityCodeDatasource? _codesOverride;
  final TwoFactorDeviceStore _deviceStore;
  final fb.FirebaseAuth? _authOverride;

  FirestoreUserDatasource? _users;
  SecurityCodeDatasource? _codes;

  FirestoreUserDatasource get _userDs =>
      _usersOverride ?? (_users ??= FirestoreUserDatasource());
  SecurityCodeDatasource get _codeDs =>
      _codesOverride ?? (_codes ??= SecurityCodeDatasource());
  fb.FirebaseAuth get _auth => _authOverride ?? fb.FirebaseAuth.instance;

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AuthException('You are not signed in', code: 'not-signed-in');
    }
    return uid;
  }

  Future<CodeSent> sendLoginCode() => _codeDs.sendLoginCode();

  Future<void> verifyLoginCode(String code) async {
    final uid = _uid();
    await _codeDs.verifyLoginCode(code);
    await _deviceStore.markVerified(uid);
  }

  Future<bool> setTwoFactor({required bool enabled, required String code}) async {
    final uid = _uid();
    final result = await _codeDs.setTwoFactor(enabled: enabled, code: code);
    if (result) await _deviceStore.markVerified(uid);
    return result;
  }

  Future<CodeSent> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthException('You are not signed in', code: 'not-signed-in');
    }
    try {
      await user.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: currentPassword),
      );
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        throw const AuthException(
            'No internet connection. Check your network and try again.');
      }
      if (e.code == 'too-many-requests') {
        throw const AuthException(
            'Too many attempts. Wait a moment and try again.');
      }
      throw const AuthException('Your current password is incorrect.',
          code: 'wrong-password');
    }
    return _codeDs.requestEmailChange(newEmail.trim().toLowerCase());
  }

  Future<String> confirmEmailChange(String code) async {
    final email = await _codeDs.confirmEmailChange(code);
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await user.reload();
        await user.getIdToken(true);
      } catch (_) {}
    }
    return email;
  }

  Future<void> saveDesignPreferences(DesignPreferences prefs) =>
      _userDs.updateUser(_uid(), {'designPreferences': prefs.toMap()});

  Future<void> saveNotificationSettings(NotificationSettings settings) =>
      _userDs.updateUser(_uid(), {'notificationSettings': settings.toMap()});

  Future<void> savePrivacySettings(PrivacySettings settings) =>
      _userDs.updateUser(_uid(), {'privacySettings': settings.toMap()});

  Future<void> completeOnboarding() =>
      _userDs.updateUser(_uid(), {'onboardingCompleted': true});

  Future<bool> isDeviceVerified(String uid) => _deviceStore.isVerified(uid);

  Future<void> clearDevice(String uid) => _deviceStore.clear(uid);
}

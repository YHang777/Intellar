import 'package:shared_preferences/shared_preferences.dart';

class TwoFactorDeviceStore {
  const TwoFactorDeviceStore();

  static String _key(String uid) => '2fa_device_ok_$uid';

  Future<bool> isVerified(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(uid)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markVerified(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid), true);
  }

  Future<void> clear(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(uid));
    } catch (_) {}
  }
}

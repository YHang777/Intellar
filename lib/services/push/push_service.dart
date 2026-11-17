import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef PushTapHandler = void Function(Map<String, String> data);

// Registers this device for FCM after sign-in (token stored under
// users/{uid}/fcmTokens/{token}), shows pushes that arrive while the app is
// open as system notifications, and routes taps through [onTap].
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const channelId = 'intellar_default';

  PushTapHandler? onTap;

  final _local = FlutterLocalNotificationsPlugin();
  String? _uid;
  String? _token;
  bool _initialised = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      Firebase.apps.isNotEmpty;

  Future<void> _init() async {
    if (_initialised) return;
    _initialised = true;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final map = (jsonDecode(payload) as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()));
          onTap?.call(map);
        } catch (_) {}
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          'Orders and updates',
          description: 'Order, quote and recommendation notifications',
          importance: Importance.high,
        ));

    _subs.add(FirebaseMessaging.onMessage.listen(_showForeground));
    _subs.add(FirebaseMessaging.onMessageOpenedApp
        .listen((m) => onTap?.call(_data(m))));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      scheduleMicrotask(() => onTap?.call(_data(initial)));
    }
  }

  Map<String, String> _data(RemoteMessage m) =>
      m.data.map((k, v) => MapEntry(k, v.toString()));

  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    await _local.show(
      id: m.messageId.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Orders and updates',
          icon: 'ic_notification',
          color: Color(0xFF2E7D32),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(_data(m)),
    );
  }

  Future<void> register(String uid) async {
    if (!_supported || _uid == uid) return;
    try {
      await _init();
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token == null) return;
      _uid = uid;
      await _saveToken(uid, token);
      _subs.add(messaging.onTokenRefresh.listen((t) async {
        final old = _token;
        if (_uid == null) return;
        await _saveToken(_uid!, t);
        if (old != null && old != t) await _deleteToken(_uid!, old);
      }));
    } catch (e) {
      debugPrint('[push] register skipped: $e');
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    _token = token;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token)
        .set({
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteToken(String uid, String token) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('fcmTokens')
      .doc(token)
      .delete();

  // Before sign-out: this device stops receiving the old account's pushes.
  Future<void> unregister() async {
    final uid = _uid;
    final token = _token;
    _uid = null;
    if (!_supported || uid == null || token == null) return;
    try {
      await _deleteToken(uid, token).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[push] unregister skipped: $e');
    }
  }
}

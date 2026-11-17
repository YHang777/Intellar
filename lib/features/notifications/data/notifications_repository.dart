import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_race_retry.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'app_notification.dart';

class NotificationsRepository {
  NotificationsRepository({FirebaseFirestore? db}) : _dbOverride = db;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const int pageSize = 50;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  Stream<List<AppNotification>> watch(String uid) {
    if (_dbOverride == null && Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return retryOnPermissionDenied(() => _col(uid)
          .orderBy('createdAt', descending: true)
          .limit(pageSize)
          .snapshots()
          .map((s) => [
                for (final d in s.docs) AppNotification.fromMap(d.id, d.data()),
              ]));
  }

  Future<void> markRead(String uid, String id) =>
      _col(uid).doc(id).update({'read': true});

  Future<void> markAllRead(String uid, Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col(uid).doc(id), {'read': true});
    }
    await batch.commit();
  }

  Future<void> delete(String uid, String id) => _col(uid).doc(id).delete();
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsRepository());

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationsRepositoryProvider).watch(uid);
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => !n.read).length;
});

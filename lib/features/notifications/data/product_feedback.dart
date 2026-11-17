import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_race_retry.dart';
import '../../auth/presentation/providers/auth_providers.dart';

// A buyer's verdict on one recommendation (FR17: learn from feedback). +1 is
// "more like this", -1 is "not for me". Stored per product so the assistant
// can steer away from what they disliked and toward what they liked.
enum FeedbackValue { like, dislike }

class ProductFeedback {
  const ProductFeedback({
    required this.productId,
    required this.value,
    this.name = '',
    this.createdAt,
  });

  final String productId;
  final FeedbackValue value;
  final String name;
  final DateTime? createdAt;

  factory ProductFeedback.fromMap(String id, Map<String, dynamic> map) =>
      ProductFeedback(
        productId: map['productId']?.toString() ?? id,
        value: map['value'] == -1 ? FeedbackValue.dislike : FeedbackValue.like,
        name: map['name']?.toString() ?? '',
      );

  Map<String, Object?> toMap() => {
        'productId': productId,
        'name': name,
        'value': value == FeedbackValue.dislike ? -1 : 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class ProductFeedbackRepository {
  ProductFeedbackRepository({FirebaseFirestore? db}) : _dbOverride = db;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('product_feedback');

  Stream<Map<String, ProductFeedback>> watch(String uid) {
    if (_dbOverride == null && Firebase.apps.isEmpty) {
      return Stream.value(const {});
    }
    return retryOnPermissionDenied(() => _col(uid).snapshots().map((s) => {
          for (final d in s.docs) d.id: ProductFeedback.fromMap(d.id, d.data()),
        }));
  }

  Future<void> save(String uid, ProductFeedback fb) =>
      _col(uid).doc(fb.productId).set(fb.toMap());

  // Second tap on the same button clears the verdict.
  Future<void> clear(String uid, String productId) =>
      _col(uid).doc(productId).delete();
}


final productFeedbackRepositoryProvider =
    Provider<ProductFeedbackRepository>((ref) => ProductFeedbackRepository());

final productFeedbackProvider =
    StreamProvider<Map<String, ProductFeedback>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const {});
  return ref.watch(productFeedbackRepositoryProvider).watch(uid);
});

/// Verdicts grouped by name, ready for the chatbot's state block.
({
  List<String> liked,
  List<String> disliked,
}) feedbackForChat(Map<String, ProductFeedback> all) {
  final liked = <String>[];
  final disliked = <String>[];
  for (final fb in all.values) {
    final label = fb.name.trim();
    if (label.isEmpty) continue;
    (fb.value == FeedbackValue.like ? liked : disliked).add(label);
  }
  return (liked: liked, disliked: disliked);
}

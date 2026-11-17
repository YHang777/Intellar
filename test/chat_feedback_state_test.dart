import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/data/models/user_preferences.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_state_context.dart';
import 'package:interior_design_recommendation/features/notifications/data/product_feedback.dart';

class _FakeFeedbackRepo extends ProductFeedbackRepository {
  _FakeFeedbackRepo(this.map);
  Map<String, ProductFeedback> map;

  @override
  Stream<Map<String, ProductFeedback>> watch(String uid) => Stream.value(map);
}

void main() {
  AppUser user({DesignPreferences? prefs, PrivacySettings? privacy}) {
    final now = DateTime(2026, 11, 17);
    return AppUser(
      uid: 'u1',
      email: 'a@b.com',
      name: 'A',
      role: UserRole.homeowner,
      designPreferences: prefs ?? const DesignPreferences(styles: ['Modern']),
      privacySettings: privacy ?? const PrivacySettings(),
      createdAt: now,
      updatedAt: now,
    );
  }

  test('feedbackForChat groups verdicts by name', () {
    final out = feedbackForChat({
      'p1': const ProductFeedback(
          productId: 'p1', value: FeedbackValue.like, name: 'Sofa Bed'),
      'p2': const ProductFeedback(
          productId: 'p2', value: FeedbackValue.dislike, name: 'Glass Table'),
      'p3': const ProductFeedback(
          productId: 'p3', value: FeedbackValue.like, name: '   '),
    });
    expect(out.liked, ['Sofa Bed']);
    expect(out.disliked, ['Glass Table']);
  });

  test('the chat payload carries what the buyer liked and disliked', () async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(user()),
      productFeedbackRepositoryProvider.overrideWithValue(_FakeFeedbackRepo({
        'p1': const ProductFeedback(
            productId: 'p1', value: FeedbackValue.like, name: 'Sofa Bed'),
        'p2': const ProductFeedback(
            productId: 'p2', value: FeedbackValue.dislike, name: 'Glass Table'),
      })),
    ]);
    addTearDown(container.dispose);
    // The feedback provider is a stream — wait for its first emission.
    await container.read(productFeedbackProvider.future);

    final payload = container.read(chatStatePayloadProvider);
    expect(payload?['feedback'], {
      'likedProducts': ['Sofa Bed'],
      'dislikedProducts': ['Glass Table'],
    });
    expect(payload?['preferences'], isNotNull);
  });

  test('the privacy switch hides feedback from the assistant', () async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(user(
          privacy: const PrivacySettings(personalisedRecommendations: false))),
      productFeedbackRepositoryProvider.overrideWithValue(_FakeFeedbackRepo({
        'p1': const ProductFeedback(
            productId: 'p1', value: FeedbackValue.like, name: 'Sofa Bed'),
      })),
    ]);
    addTearDown(container.dispose);
    // The feedback provider is a stream — wait for its first emission.
    await container.read(productFeedbackProvider.future);

    final payload = container.read(chatStatePayloadProvider);
    expect(payload?['feedback'], isNull);
    expect(payload?['preferences'], isNull);
  });

  test('buildChatStateJson emits the block only when there is feedback', () {
    Map<String, Object?>? build(
            {List<String> liked = const [], List<String> disliked = const []}) =>
        buildChatStateJson(
          cartRows: const [],
          cartCount: 0,
          cartSubtotal: 0,
          budget: null,
          orders: const [],
          plan: null,
          pendingPlacements: 0,
          likedProducts: liked,
          dislikedProducts: disliked,
        );
    expect(build(), isNull);
    expect(build(liked: ['Sofa Bed'])?['feedback'], {
      'likedProducts': ['Sofa Bed'],
    });
  });
}

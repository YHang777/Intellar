import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/services/auth_race_retry.dart';

void main() {
  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  test('a permission-denied right after sign-in is retried', () async {
    var opens = 0;
    final stream = retryOnPermissionDenied<int>(() {
      opens++;
      return opens == 1 ? Stream<int>.error(denied()) : Stream<int>.value(7);
    }, delay: const Duration(milliseconds: 1));
    expect(await stream.first, 7);
    expect(opens, 2);
  });

  test('gives up after the allowed attempts and surfaces the error', () async {
    var opens = 0;
    final stream = retryOnPermissionDenied<int>(() {
      opens++;
      return Stream<int>.error(denied());
    }, attempts: 2, delay: const Duration(milliseconds: 1));
    await expectLater(stream.first, throwsA(isA<FirebaseException>()));
    expect(opens, 3);
  });

  test('other errors are not retried', () async {
    var opens = 0;
    final stream = retryOnPermissionDenied<int>(() {
      opens++;
      return Stream<int>.error(StateError('boom'));
    }, delay: const Duration(milliseconds: 1));
    await expectLater(stream.first, throwsA(isA<StateError>()));
    expect(opens, 1);
  });
}

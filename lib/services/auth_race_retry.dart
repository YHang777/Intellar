import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

// Right after a sign-in (especially switching accounts in one session),
// a listener can open before Firestore holds the new user's token and get
// permission-denied once. Reopen it a few times instead of leaving the
// screen stuck on an error.
Stream<T> retryOnPermissionDenied<T>(
  Stream<T> Function() open, {
  int attempts = 4,
  Duration delay = const Duration(milliseconds: 700),
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  var tries = 0;
  var cancelled = false;

  void listen() {
    sub = open().listen(
      controller.add,
      onError: (Object error, StackTrace stack) {
        final denied =
            error is FirebaseException && error.code == 'permission-denied';
        if (denied && tries < attempts && !cancelled) {
          tries++;
          sub?.cancel();
          Future<void>.delayed(delay * tries, () {
            if (!cancelled) listen();
          });
          return;
        }
        controller.addError(error, stack);
      },
      onDone: () {
        if (!cancelled) controller.close();
      },
    );
  }

  controller = StreamController<T>(
    onListen: listen,
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      cancelled = true;
      await sub?.cancel();
    },
  );
  return controller.stream;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/accessibility/accessibility_settings.dart';
import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/models/app_user.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/notifications/data/app_notification.dart';
import 'features/notifications/data/notifications_repository.dart';
import 'services/push/push_service.dart';

class InteriorDesignApp extends ConsumerStatefulWidget {
  const InteriorDesignApp({super.key});

  @override
  ConsumerState<InteriorDesignApp> createState() => _InteriorDesignAppState();
}

class _InteriorDesignAppState extends ConsumerState<InteriorDesignApp> {
  bool _bootstrapComplete = false;

  @override
  void initState() {
    super.initState();
    PushService.instance.onTap = _openFromPush;
    ref.listenManual<AppUser?>(currentUserProvider, (prev, next) {
      if (next != null && !next.twoFactorPending) {
        PushService.instance.register(next.uid);
      }
    }, fireImmediately: true);
    ref.listenManual<AccessibilitySettings>(accessibilitySettingsProvider,
        (prev, next) {
      if (prev == null || prev.highContrast == next.highContrast) return;
      AppColors.highContrast = next.highContrast;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) WidgetsBinding.instance.reassembleApplication();
      });
    });
  }

  void _openFromPush(Map<String, String> data) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    String? pick(String k) {
      final v = data[k];
      return (v == null || v.isEmpty) ? null : v;
    }
    final route = routeForNotification(
      isSupplier: user.isSupplier,
      orderId: pick('orderId'),
      quoteId: pick('quoteId'),
      productId: pick('productId'),
    );
    final id = pick('notificationId');
    if (id != null) {
      ref
          .read(notificationsRepositoryProvider)
          .markRead(user.uid, id)
          .catchError((_) {});
    }
    ref.read(appRouterProvider).push(route ?? '/notifications');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final authState = ref.watch(authStateProvider);
    final a11y = ref.watch(accessibilitySettingsProvider);
    AppColors.highContrast = a11y.highContrast;

    if (!authState.isLoading) _bootstrapComplete = true;

    return MaterialApp.router(
      title: 'Intellar',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final systemScale = media.textScaler.scale(1);
        child = MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
                (systemScale * a11y.textSize.scale).clamp(0.8, 2.0)),
            boldText: media.boldText || a11y.boldText,
            highContrast: media.highContrast || a11y.highContrast,
          ),
          child: child ?? const SizedBox.shrink(),
        );
        if (!_bootstrapComplete && authState.isLoading) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home_work_rounded,
                      size: 48, color: AppColors.accent),
                  SizedBox(height: 16),
                  CircularProgressIndicator(color: AppColors.accent),
                ],
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}

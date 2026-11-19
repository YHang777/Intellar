import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/float_button.dart';
import '../../../shared/widgets/page_heading.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/app_notification.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(
      BuildContext context, WidgetRef ref, AppNotification n) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (!n.read) {
      try {
        await ref.read(notificationsRepositoryProvider).markRead(user.uid, n.id);
      } catch (_) {}
    }
    final route = routeForNotification(
      isSupplier: user.isSupplier,
      orderId: n.orderId,
      quoteId: n.quoteId,
      productId: n.productId,
    );
    if (route != null && context.mounted) context.push(route);
  }

  Future<void> _markAll(
      BuildContext context, WidgetRef ref, List<AppNotification> list) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    final unread = [for (final n in list) if (!n.read) n.id];
    if (unread.isEmpty) return;
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead(uid, unread);
    } catch (e) {
      if (context.mounted) {
        showAppSnackbar(context, 'Could not update notifications.',
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final list = async.valueOrNull ?? const <AppNotification>[];
    final unread = list.where((n) => !n.read).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const FloatingBackButton(),
                  const Spacer(),
                  if (unread > 0)
                    TextButton(
                      key: const Key('mark-all-read'),
                      onPressed: () => _markAll(context, ref, list),
                      child: const Text('Mark all as read'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: PageHeading(
                title: 'Notifications',
                subtitle: unread == 0
                    ? 'You are all caught up'
                    : '$unread unread',
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load notifications',
                  subtitle: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(notificationsProvider),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState(
                        icon: Icons.notifications_none,
                        title: 'No notifications yet',
                        subtitle:
                            'Order updates, quote replies and new pieces that '
                            'match your style will appear here.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _NotificationTile(
                          n: items[i],
                          onTap: () => _open(context, ref, items[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});

  final AppNotification n;
  final VoidCallback onTap;

  IconData get _icon => switch (n.kind) {
        'new_order' => Icons.shopping_bag_outlined,
        'order_update' => Icons.local_shipping_outlined,
        'quote' => Icons.request_quote_outlined,
        'recommendation' => Icons.auto_awesome_outlined,
        'promotion' => Icons.local_offer_outlined,
        'low_stock' => Icons.inventory_2_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: n.read ? AppColors.surface : AppColors.accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('notification-${n.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: Icon(_icon, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: n.read ? FontWeight.w500 : FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.body,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    if (n.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        Formatters.shortDateTime(n.createdAt!),
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textHint),
                      ),
                    ],
                  ],
                ),
              ),
              if (!n.read)
                Container(
                  key: const Key('unread-dot'),
                  margin: const EdgeInsets.only(left: 8, top: 6),
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider);
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: count == 0 ? 'Notifications' : '$count unread notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: AppColors.error,
        child: Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/user_errors.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../auth/data/models/user_preferences.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer/homeowner/presentation/providers/design_providers.dart';
import '../widgets/settings_widgets.dart';

class NotificationPrivacyScreen extends ConsumerStatefulWidget {
  const NotificationPrivacyScreen({super.key});

  @override
  ConsumerState<NotificationPrivacyScreen> createState() =>
      _NotificationPrivacyScreenState();
}

class _NotificationPrivacyScreenState
    extends ConsumerState<NotificationPrivacyScreen> {
  NotificationSettings? _notif;
  PrivacySettings? _privacy;

  Future<void> _saveNotif(NotificationSettings next) async {
    final prev = _notif;
    setState(() => _notif = next);
    try {
      await ref.read(authStateProvider.notifier).saveNotificationSettings(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notif = prev);
      showAppSnackbar(context,
          userMessage(e, fallback: 'Could not save. Please try again.'),
          isError: true);
    }
  }

  Future<void> _savePrivacy(PrivacySettings next) async {
    final prev = _privacy;
    setState(() => _privacy = next);
    try {
      await ref.read(authStateProvider.notifier).savePrivacySettings(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _privacy = prev);
      showAppSnackbar(context,
          userMessage(e, fallback: 'Could not save. Please try again.'),
          isError: true);
    }
  }

  Future<void> _clearChats() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear AI chat history?',
      message: 'Every saved conversation with the design assistant on this '
          'phone will be deleted.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !mounted) return;
    ref.read(chatHistoryProvider.notifier).clearAll();
    showAppSnackbar(context, 'Chat history cleared');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final notif = _notif ?? user?.notificationSettings ?? const NotificationSettings();
    final privacy = _privacy ?? user?.privacySettings ?? const PrivacySettings();
    final homeowner = user?.isHomeowner ?? true;
    return SettingsPage(
      title: 'Notifications & privacy',
      subtitle: 'Choose what we send you and what we use',
      children: [
        SettingsCard(
          title: 'Notifications',
          children: [
            SettingsSwitchTile(
              key: const Key('notif-orders'),
              icon: Icons.local_shipping_outlined,
              title: 'Order updates',
              subtitle: homeowner
                  ? 'When a seller confirms or readies your order'
                  : 'When customers place or cancel orders',
              value: notif.orderUpdates,
              onChanged: (v) => _saveNotif(notif.copyWith(orderUpdates: v)),
            ),
            SettingsSwitchTile(
              key: const Key('notif-promotions'),
              icon: Icons.local_offer_outlined,
              title: 'Promotions',
              subtitle: 'Deals and new arrivals',
              value: notif.promotions,
              onChanged: (v) => _saveNotif(notif.copyWith(promotions: v)),
            ),
            if (homeowner)
              SettingsSwitchTile(
                key: const Key('notif-recommendations'),
                icon: Icons.auto_awesome_outlined,
                title: 'New recommendations',
                subtitle: 'Pieces that match your saved style',
                value: notif.recommendations,
                onChanged: (v) =>
                    _saveNotif(notif.copyWith(recommendations: v)),
              ),
          ],
        ),
        if (homeowner)
          SettingsCard(
            title: 'Privacy',
            children: [
              SettingsSwitchTile(
                key: const Key('privacy-personalised'),
                icon: Icons.tune,
                title: 'Personalised recommendations',
                subtitle:
                    'Let the design assistant use your saved design preferences',
                value: privacy.personalisedRecommendations,
                onChanged: (v) => _savePrivacy(
                    privacy.copyWith(personalisedRecommendations: v)),
              ),
              SettingsSwitchTile(
                key: const Key('privacy-designs'),
                icon: Icons.design_services_outlined,
                title: 'Share my room plan with the assistant',
                subtitle:
                    'Room size and placed furniture help it give better advice',
                value: privacy.shareDesignsWithAssistant,
                onChanged: (v) => _savePrivacy(
                    privacy.copyWith(shareDesignsWithAssistant: v)),
              ),
              SettingsActionTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear AI chat history',
                subtitle: 'Removes saved conversations from this phone',
                destructive: true,
                onTap: _clearChats,
              ),
            ],
          ),
      ],
    );
  }
}

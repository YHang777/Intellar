import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';

bool isGuestUser(WidgetRef ref) => ref.read(currentUserProvider)?.isGuest ?? false;

// Guests can explore everything; anything saved or bought needs an account.
// Returns true when the action may go ahead.
Future<bool> requireAccount(BuildContext context, WidgetRef ref, String action) async {
  if (!isGuestUser(ref)) return true;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SingleChildScrollView(child: GuestSignUpSheet(action: action)),
  );
  return false;
}

Future<void> leaveGuestMode(WidgetRef ref, GoRouter router, String route) async {
  await ref.read(authStateProvider.notifier).logout();
  router.go(route);
}

class GuestSignUpSheet extends ConsumerWidget {
  const GuestSignUpSheet({super.key, required this.action});

  final String action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          key: const Key('guest-sign-up-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_add_alt_1, color: AppColors.accent, size: 30),
            ),
            const SizedBox(height: 16),
            Text('Create a free account',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Sign up to $action. It only takes a minute, and you can keep '
                'exploring as a guest until then.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('guest-create-account'),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).maybePop();
                  leaveGuestMode(ref, router, '/register');
                },
                child: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('guest-sign-in'),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).maybePop();
                  leaveGuestMode(ref, router, '/login');
                },
                child: const Text('I already have an account'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep browsing'),
            ),
          ],
        ),
      ),
    );
  }
}

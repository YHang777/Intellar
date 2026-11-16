import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/code_entry_dialog.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_button.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key, this.autoSend = true});

  final bool autoSend;

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _ctrl = TextEditingController();
  late final ResendCountdown _countdown;
  String? _sentTo;
  String? _error;
  bool _sending = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _countdown = ResendCountdown(() {
      if (mounted) setState(() {});
    });
    if (widget.autoSend) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send());
    }
  }

  @override
  void dispose() {
    _countdown.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent =
          await ref.read(authStateProvider.notifier).sendTwoFactorCode();
      if (!mounted) return;
      setState(() => _sentTo = sent.sentTo);
      _countdown.start();
    } catch (e) {
      if (mounted) {
        setState(() => _error = userMessage(e,
            fallback: 'Could not send the code. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final code = _ctrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(authStateProvider.notifier).verifyTwoFactorCode(code);
      if (mounted) showAppSnackbar(context, 'Signed in');
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            userMessage(e, fallback: 'That code did not work. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentUserProvider)?.email ?? '';
    final wait = _countdown.secondsLeft;
    final target = _sentTo ?? email;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accentLight],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined,
                      size: 44, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Two-step verification',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _sending && _sentTo == null
                    ? 'Sending a code to $target…'
                    : 'Enter the 6-digit code we emailed to $target.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              CodeInputField(
                controller: _ctrl,
                errorText: _error,
                onSubmitted: (_) => _verifying ? null : _verify(),
              ),
              const SizedBox(height: 24),
              AuthButton(
                label: _verifying ? 'Checking…' : 'Verify',
                onPressed: _verifying ? null : _verify,
              ),
              const SizedBox(height: 12),
              AuthButton(
                label: wait > 0 ? 'Resend code in ${wait}s' : 'Resend code',
                isOutlined: true,
                onPressed: (_sending || wait > 0) ? null : _send,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => ref.read(authStateProvider.notifier).logout(),
                child: const Text('Sign in with a different account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/code_entry_dialog.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../auth/data/datasources/security_code_datasource.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../widgets/settings_widgets.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  bool _busy = false;

  AuthStateNotifier get _auth => ref.read(authStateProvider.notifier);

  Future<void> _toggleTwoFactor(bool enable) async {
    setState(() => _busy = true);
    try {
      final sent = await _auth.sendTwoFactorCode();
      if (!mounted) return;
      final ok = await showCodeEntryDialog(
        context,
        title: enable ? 'Turn on two-step verification' : 'Turn off two-step verification',
        sentTo: sent.sentTo,
        confirmLabel: enable ? 'Turn on' : 'Turn off',
        onSubmit: (code) =>
            _auth.setTwoFactorEnabled(enabled: enable, code: code),
        onResend: () async => (await _auth.sendTwoFactorCode()).sentTo,
      );
      if (ok && mounted) {
        showAppSnackbar(
            context,
            enable
                ? 'Two-step verification is on'
                : 'Two-step verification is off');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback: 'Could not send the code. Please try again.'),
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeEmail(String currentEmail) async {
    final request =
        await showDialog<({String email, String password, CodeSent sent})>(
      context: context,
      builder: (_) => _ChangeEmailDialog(
        currentEmail: currentEmail,
        onSubmit: (email, password) => _auth.requestEmailChange(
            newEmail: email, currentPassword: password),
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final sent = request.sent;
      final ok = await showCodeEntryDialog(
        context,
        title: 'Confirm your new email',
        sentTo: sent.sentTo,
        onSubmit: _auth.confirmEmailChange,
        onResend: () async => (await _auth.requestEmailChange(
                newEmail: request.email, currentPassword: request.password))
            .sentTo,
      );
      if (ok && mounted) {
        showAppSnackbar(context, 'Your email is now ${request.email}');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback: 'Could not change your email. Please try again.'),
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword(String email) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reset password?',
      message: 'A password reset link will be sent to $email.',
      confirmLabel: 'Send link',
    );
    if (!ok) return;
    try {
      await _auth.sendPasswordResetEmail(email);
      if (mounted) showAppSnackbar(context, 'Password reset email sent to $email');
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback: 'Could not send the reset email. Please try again.'),
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final email = user?.email ?? '';
    final enabled = user?.twoFactorEnabled ?? false;
    return SettingsPage(
      title: 'Login & security',
      subtitle: 'Protect your account',
      children: [
        SettingsCard(
          title: 'Two-step verification',
          children: [
            SettingsSwitchTile(
              key: const Key('two-factor-switch'),
              icon: Icons.shield_outlined,
              title: 'Email code at sign-in',
              subtitle: enabled
                  ? 'A 6-digit code is emailed to you each time you sign in.'
                  : 'Add a second step: a code emailed to $email.',
              value: enabled,
              onChanged: (_busy || user == null) ? null : _toggleTwoFactor,
            ),
          ],
        ),
        SettingsCard(
          title: 'Account',
          children: [
            SettingsActionTile(
              key: const Key('change-email-tile'),
              icon: Icons.alternate_email,
              title: 'Change email',
              subtitle: email,
              onTap: (_busy || user == null) ? null : () => _changeEmail(email),
            ),
            SettingsActionTile(
              icon: Icons.lock_outline,
              title: 'Change password',
              subtitle: 'We email you a secure reset link',
              onTap: email.isEmpty ? null : () => _resetPassword(email),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({required this.currentEmail, required this.onSubmit});

  final String currentEmail;
  final Future<CodeSent> Function(String email, String password) onSubmit;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await widget.onSubmit(email, password);
      if (mounted) {
        Navigator.of(context)
            .pop((email: email, password: password, sent: sent));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = userMessage(e,
            fallback: 'Could not send the code. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Change email'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'We will send a code to the new address to confirm it.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-email-field'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'New email'),
                validator: (v) {
                  final base = Validators.email(v);
                  if (base != null) return base;
                  if (v!.trim().toLowerCase() ==
                      widget.currentEmail.toLowerCase()) {
                    return 'That is already your email.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('current-password-field'),
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your current password.'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const Key('change-email-error'),
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send code'),
        ),
      ],
    );
  }
}

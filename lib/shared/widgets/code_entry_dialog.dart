import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/user_errors.dart';

const kCodeResendCooldown = Duration(seconds: 30);

class CodeInputField extends StatelessWidget {
  const CodeInputField({
    super.key,
    required this.controller,
    this.errorText,
    this.onSubmitted,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('code-input'),
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: onSubmitted,
      style: GoogleFonts.poppins(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: 10,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '000000',
        hintStyle: GoogleFonts.poppins(
          fontSize: 26,
          letterSpacing: 10,
          color: AppColors.textHint.withValues(alpha: 0.5),
        ),
        errorText: errorText,
        errorMaxLines: 2,
      ),
    );
  }
}

class ResendCountdown {
  ResendCountdown(this._onTick);

  final VoidCallback _onTick;
  Timer? _timer;
  int secondsLeft = 0;

  void start([Duration d = kCodeResendCooldown]) {
    _timer?.cancel();
    secondsLeft = d.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      secondsLeft = secondsLeft > 0 ? secondsLeft - 1 : 0;
      if (secondsLeft == 0) t.cancel();
      _onTick();
    });
  }

  void dispose() => _timer?.cancel();
}

Future<bool> showCodeEntryDialog(
  BuildContext context, {
  required String title,
  required String sentTo,
  required Future<void> Function(String code) onSubmit,
  required Future<String> Function() onResend,
  String confirmLabel = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CodeEntryDialog(
      title: title,
      sentTo: sentTo,
      onSubmit: onSubmit,
      onResend: onResend,
      confirmLabel: confirmLabel,
    ),
  );
  return ok ?? false;
}

class _CodeEntryDialog extends StatefulWidget {
  const _CodeEntryDialog({
    required this.title,
    required this.sentTo,
    required this.onSubmit,
    required this.onResend,
    required this.confirmLabel,
  });

  final String title;
  final String sentTo;
  final Future<void> Function(String code) onSubmit;
  final Future<String> Function() onResend;
  final String confirmLabel;

  @override
  State<_CodeEntryDialog> createState() => _CodeEntryDialogState();
}

class _CodeEntryDialogState extends State<_CodeEntryDialog> {
  final _ctrl = TextEditingController();
  late final ResendCountdown _countdown;
  late String _sentTo = widget.sentTo;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _countdown = ResendCountdown(() {
      if (mounted) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _countdown.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            userMessage(e, fallback: 'That code did not work. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final to = await widget.onResend();
      if (!mounted) return;
      setState(() {
        if (to.isNotEmpty) _sentTo = to;
        _ctrl.clear();
      });
      _countdown.start();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            userMessage(e, fallback: 'Could not send a new code.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wait = _countdown.secondsLeft;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'We sent a 6-digit code to $_sentTo. It expires in 10 minutes.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            CodeInputField(
              controller: _ctrl,
              errorText: _error,
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: (_busy || wait > 0) ? null : _resend,
                child: Text(wait > 0 ? 'Resend code in ${wait}s' : 'Resend code'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

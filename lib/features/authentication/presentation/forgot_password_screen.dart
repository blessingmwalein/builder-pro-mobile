import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/states.dart';
import 'auth_scaffold.dart';

/// Two steps against the real API: email → 6-digit code + new password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _showCompany = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _company.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy || !(_emailForm.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .forgotPassword(
            email: _email.text,
            companySlug: _showCompany ? _company.text : null,
          );
      if (mounted) setState(() => _codeSent = true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.fullMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy || !(_resetForm.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(
            email: _email.text,
            otp: _code.text,
            password: _password.text,
            companySlug: _showCompany ? _company.text : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Sign in with your new password.'),
        ),
      );
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.fullMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AuthScaffold(
      showBack: true,
      title: _codeSent ? 'Enter your code' : 'Reset password',
      subtitle: _codeSent
          ? 'We emailed a 6-digit code to ${_email.text.trim()}. It is valid for 15 minutes.'
          : "Enter your email and we'll send you a 6-digit code.",
      children: [
        if (!_codeSent)
          Form(
            key: _emailForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: _showCompany
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                  enabled: !_busy,
                  onSubmitted: (_) => _showCompany ? null : _sendCode(),
                ),
                if (_showCompany) ...[
                  const SizedBox(height: Space.lg),
                  AppTextField(
                    label: 'Company code',
                    controller: _company,
                    enabled: !_busy,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter your company code'
                        : null,
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _showCompany = true),
                      child: Text(
                        'My email is used by several companies',
                        style: AppType.bodySmall.copyWith(color: c.primaryText),
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Form(
            key: _resetForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: '6-digit code',
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  validator: Validators.otp,
                  enabled: !_busy,
                  maxLength: 6,
                ),
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'New password',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.password,
                  enabled: !_busy,
                ),
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'Confirm new password',
                  controller: _confirm,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  validator: Validators.matches(
                    () => _password.text,
                    'Passwords do not match',
                  ),
                  enabled: !_busy,
                  onSubmitted: (_) => _reset(),
                ),
              ],
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: Space.lg),
          Semantics(
            liveRegion: true,
            child: ErrorPanel(
              error: AppException(AppErrorKind.unknown, _error!),
              compact: true,
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        AppButton(
          label: _codeSent ? 'Update password' : 'Send code',
          onPressed: _codeSent ? _reset : _sendCode,
          loading: _busy,
        ),
        if (_codeSent)
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _codeSent = false;
                      _error = null;
                    }),
              child: const Text('Use a different email'),
            ),
          ),
      ],
    );
  }
}

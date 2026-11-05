import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_guard.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/session_state.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/states.dart';
import 'auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _company = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _needsCompany = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _company.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // never double-submit
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(
            email: _email.text,
            password: _password.text,
            companySlug: _needsCompany ? _company.text : null,
          );
      // The router reacts to the new session state and leaves this screen.
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        if (isMultipleAccountsError(e)) {
          _needsCompany = true;
          _error = 'This email is used by more than one company. Enter your company code to continue.';
        } else {
          _error = e.kind == AppErrorKind.unauthorized
              ? 'Incorrect email or password.'
              : e.fullMessage;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final expired = ref.watch(
      sessionProvider.select((s) => s.status == SessionStatus.expired),
    );

    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Use the email and password for your ownit2buildit account.',
      children: [
        if (expired && _error == null) ...[
          const StatusBanner(
            message: 'Your session expired. Please sign in again.',
            icon: Icons.lock_clock_outlined,
          ),
          const SizedBox(height: Space.lg),
        ],
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  validator: Validators.email,
                  enabled: !_busy,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'Password',
                  controller: _password,
                  focusNode: _passwordFocus,
                  obscure: true,
                  textInputAction: _needsCompany
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: Validators.password,
                  enabled: !_busy,
                  onSubmitted: (_) => _needsCompany ? null : _submit(),
                ),
                if (_needsCompany) ...[
                  const SizedBox(height: Space.lg),
                  AppTextField(
                    label: 'Company code',
                    controller: _company,
                    hint: 'e.g. acme-builders',
                    helper: 'The short name of your company, as set by your administrator.',
                    textInputAction: TextInputAction.done,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter your company code'
                        : null,
                    enabled: !_busy,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ],
            ),
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
        AppButton(label: 'Sign in', onPressed: _submit, loading: _busy),
        const SizedBox(height: Space.sm),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => context.push(Routes.forgotPassword),
            child: Text(
              'Forgot password?',
              style: AppType.bodyStrong.copyWith(color: c.primaryText),
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        Text(
          'New company? Create your account on the web at ownit2buildit.com. Team members receive an email invitation from their administrator.',
          textAlign: TextAlign.center,
          style: AppType.bodySmall.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

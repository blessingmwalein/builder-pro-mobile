import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/theme_mode.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/profile_actions.dart';

/// Light or dark, or whatever the phone is set to. It changes at once and is
/// remembered on this phone; it is not part of the profile that is saved below.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);
    // Icons are dropped when text is enlarged so the three choices still fit.
    final icons = MediaQuery.textScalerOf(context).scale(1) <= 1.15;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Appearance', style: AppType.label.copyWith(color: c.text)),
          const SizedBox(height: Space.sm),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: icons ? const Icon(Icons.brightness_auto_rounded) : null,
                label: const Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: icons ? const Icon(Icons.light_mode_rounded) : null,
                label: const Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: icons ? const Icon(Icons.dark_mode_rounded) : null,
                label: const Text('Dark'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'System follows your phone\'s setting. The choice applies on this phone only.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Change your own name and phone number. The email is shown but cannot be
/// changed here. People see your phone number in the team directory, so keep it
/// current. Also where the app's light or dark look is chosen.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _phone;
  bool _saving = false;
  AppException? _error;

  @override
  void initState() {
    super.initState();
    final u = ref.read(sessionProvider).me?.user;
    _first = TextEditingController(text: u?.firstName ?? '');
    _last = TextEditingController(text: u?.lastName ?? '');
    _phone = TextEditingController(text: u?.phone ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileActionsProvider)
          .update(
            firstName: _first.text,
            lastName: _last.text,
            phone: _phone.text,
          );
      if (!mounted) return;
      Snack.show(context, 'Profile updated.');
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = ref.watch(sessionProvider).me;
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: SafeArea(
        child: me == null
            ? const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Not signed in',
                message: 'Sign in to change your profile.',
              )
            : PageBody(
                children: [
                  const _AppearanceCard(),
                  const SizedBox(height: Space.lg),
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          label: 'First name',
                          controller: _first,
                          validator: (v) => validatePersonName(v, 'first name'),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Last name',
                          controller: _last,
                          validator: (v) => validatePersonName(v, 'last name'),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Phone (optional)',
                          controller: _phone,
                          hint: '+263 77 123 4567',
                          keyboardType: TextInputType.phone,
                          validator: validatePhone,
                        ),
                        const SizedBox(height: Space.lg),
                        Text(
                          'Email',
                          style: AppType.label.copyWith(color: c.text),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          me.user.email,
                          style: AppType.body.copyWith(color: c.textMuted),
                        ),
                        Text(
                          'Your email is how you sign in, so it is changed by your administrator.',
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: 'Save',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

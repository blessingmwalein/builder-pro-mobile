import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/destinations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/brand_mark.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/states.dart';

/// Shown while stored credentials are read and verified.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.shell,
      body: Center(
        child: Semantics(
          label: 'Loading ownit2buildit',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(height: 96, forceLight: true),
              const SizedBox(height: Space.x3),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: c.onShell.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// HTTP 402 from the API. Workers cannot fix this, so no billing actions are
/// offered; the screen explains and lets them check again or sign out.
class SubscriptionBlockedScreen extends ConsumerStatefulWidget {
  const SubscriptionBlockedScreen({super.key});

  @override
  ConsumerState<SubscriptionBlockedScreen> createState() =>
      _SubscriptionBlockedScreenState();
}

class _SubscriptionBlockedScreenState
    extends ConsumerState<SubscriptionBlockedScreen> {
  bool _checking = false;

  static String headline(String? code) => switch (code) {
    'TRIAL_EXPIRED' => "Your company's free trial has ended",
    'SUBSCRIPTION_EXPIRED' => "Your company's subscription has expired",
    'SUBSCRIPTION_INACTIVE' => "Your company's subscription is not active",
    'NO_SUBSCRIPTION' => "Your company hasn't finished setting up",
    _ => "Your company's subscription needs attention",
  };

  Future<void> _check() async {
    setState(() => _checking = true);
    await ref.read(sessionProvider.notifier).refreshMe();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(height: 48)),
                  const SizedBox(height: Space.x3),
                  Center(
                    child: IconTile(
                      Icons.lock_clock_outlined,
                      tone: StatusTone.warning,
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      headline(session.subscriptionCode),
                      textAlign: TextAlign.center,
                      style: AppType.pageTitle.copyWith(color: c.text),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    'Access is paused until your company\'s subscription is active again. '
                    'Please contact your company administrator.',
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: Space.x3),
                  AppButton(
                    label: 'Check again',
                    icon: Icons.refresh_rounded,
                    onPressed: _check,
                    loading: _checking,
                  ),
                  const SizedBox(height: Space.sm),
                  AppButton(
                    label: 'Sign out',
                    variant: AppButtonVariant.ghost,
                    onPressed: _checking
                        ? null
                        : () => ref.read(sessionProvider.notifier).logout(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app could not verify the session and has nothing cached to show.
class StartupFailedScreen extends ConsumerWidget {
  const StartupFailedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(sessionProvider.select((s) => s.error));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ErrorPanel(
                error: error ?? Exception('startup'),
                onRetry: () => ref.read(sessionProvider.notifier).bootstrap(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.xxl),
              child: AppButton(
                label: 'Sign out',
                variant: AppButtonVariant.ghost,
                onPressed: () => ref.read(sessionProvider.notifier).logout(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reached when navigation (including a deep link or notification tap) targets
/// something the user's permissions do not allow.
class AccessDeniedScreen extends ConsumerWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = planNavigation(ref.watch(permissionsProvider)).homePath;
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.lock_outline_rounded,
        title: "You don't have access to this",
        message: 'Your role does not include this area. Ask your administrator if you think you should have it.',
        actionLabel: 'Go back',
        onAction: () => context.go(home),
      ),
    );
  }
}

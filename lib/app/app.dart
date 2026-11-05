import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../features/notifications/application/push_providers.dart';
import '../features/notifications/data/push_models.dart';
import '../features/sync/application/sync_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';

/// Shows the banner for an alert that arrives while the app is open.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>(
  debugLabel: 'root-messenger',
);

class BuilderProApp extends ConsumerStatefulWidget {
  const BuilderProApp({super.key});

  @override
  ConsumerState<BuilderProApp> createState() => _BuilderProAppState();
}

class _BuilderProAppState extends ConsumerState<BuilderProApp>
    with WidgetsBindingObserver {
  DateTime _lastCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Permissions can change while the app is backgrounded (an admin edits the
  /// role). Re-read `/auth/me` on resume, at most once a minute.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) return;
    ref.read(appResumeProvider.notifier).bump();
    if (DateTime.now().difference(_lastCheck) < const Duration(minutes: 1)) {
      return;
    }
    _lastCheck = DateTime.now();
    ref.read(sessionProvider.notifier).refreshMe();
  }

  /// An alert arrived while the app is open: a short banner, with a way to open
  /// what it is about.
  void _showBanner(PushMessage m) {
    final messenger = rootMessengerKey.currentState;
    if (messenger == null) return;
    final route = m.route;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (m.body.isNotEmpty) Text(m.body),
            ],
          ),
          action: route == null
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => ref.read(routerProvider).go(route),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps what was saved without a connection moving to the server.
    ref.watch(syncTriggerProvider);
    // Alerts on this phone: registration, the stored inbox, taps.
    ref.watch(pushControllerProvider);
    ref.listen<PushMessage?>(incomingPushProvider, (_, m) {
      if (m != null) _showBanner(m);
    });
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: ref.watch(appConfigProvider).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: router,
    );
  }
}

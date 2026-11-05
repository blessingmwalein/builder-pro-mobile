import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/auth/session_state.dart';
import '../../shared/components/states.dart';
import '../router/destinations.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/tokens.dart';

/// Signed-in frame: content + permission-driven navigation.
/// Bottom bar on phones, side rail on tablets.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final plan = planNavigation(ref.watch(permissionsProvider));
    final wide = MediaQuery.sizeOf(context).width >= 840;

    final items = <_NavItem>[
      for (final d in plan.bottom)
        _NavItem(
          label: d.label,
          icon: d.icon,
          selectedIcon: d.selectedIcon,
          branchIndex: d.branchIndex,
        ),
      const _NavItem(
        label: 'More',
        icon: Icons.menu_rounded,
        selectedIcon: Icons.menu_rounded,
        branchIndex: moreBranchIndex,
      ),
    ];
    final current = navigationShell.currentIndex;
    final selected = selectedBarIndex([
      for (final i in items) i.branchIndex,
    ], current);

    void go(int i) {
      final branch = items[i].branchIndex;
      navigationShell.goBranch(
        branch,
        initialLocation: branch == navigationShell.currentIndex,
      );
    }

    final content = Column(
      children: [
        if (session.offline)
          const StatusBanner(message: 'Offline. Showing saved information.'),
        Expanded(child: navigationShell),
      ],
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _SideRail(items: items, selected: selected, onSelect: go),
              VerticalDivider(width: 1, color: context.colors.border),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: content),
      bottomNavigationBar: _BottomBar(
        items: items,
        selected: selected,
        onSelect: go,
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.branchIndex,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int branchIndex;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: Sizes.bottomBarHeight,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _BarButton(
                      item: items[i],
                      active: i == selected,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.primaryText : c.textMuted;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            AnimatedContainer(
              duration: Motion.normal,
              curve: Motion.standard,
              height: 3,
              width: active ? 36 : 0,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(3),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active ? item.selectedIcon : item.icon,
                    size: Sizes.iconMd + 2,
                    color: color,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.badge.copyWith(
                      color: color,
                      fontSize: 11.5,
                      letterSpacing: 0,
                    ),
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

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return NavigationRail(
      backgroundColor: c.surface,
      selectedIndex: selected,
      onDestinationSelected: onSelect,
      labelType: NavigationRailLabelType.all,
      indicatorColor: c.primarySoft,
      selectedIconTheme: IconThemeData(color: c.primaryText),
      unselectedIconTheme: IconThemeData(color: c.textMuted),
      selectedLabelTextStyle: AppType.badge.copyWith(color: c.primaryText),
      unselectedLabelTextStyle: AppType.badge.copyWith(color: c.textMuted),
      destinations: [
        for (final i in items)
          NavigationRailDestination(
            icon: Icon(i.icon),
            selectedIcon: Icon(i.selectedIcon),
            label: Text(i.label),
          ),
      ],
    );
  }
}

/// Used by [SessionStatus] aware widgets that need the plan without the shell.
NavPlan navPlanFor(SessionState s) => planNavigation(s.permissions);

/// Which bar item to light up. [barBranches] are the branch indexes of the bar
/// items (More is last). A destination that is not in the bar (opened from
/// More) keeps More lit instead of lighting up the first tab.
int selectedBarIndex(List<int> barBranches, int currentBranch) {
  final found = barBranches.indexOf(currentBranch);
  return found == -1 ? barBranches.length - 1 : found;
}

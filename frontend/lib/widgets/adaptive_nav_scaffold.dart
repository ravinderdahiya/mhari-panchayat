import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Shell scaffold: bottom [NavigationBar] on phones (exactly as before),
/// a left [NavigationRail] on tablets so the content gets the full width.
class AdaptiveNavScaffold extends StatelessWidget {
  const AdaptiveNavScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.railLeading,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final Widget body;

  /// Optional widget above the rail destinations (e.g. a primary action).
  final Widget? railLeading;

  @override
  Widget build(BuildContext context) {
    if (!context.isTablet) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
        ),
      );
    }

    return TabletRailScaffold(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      leading: railLeading,
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: d.icon,
            selectedIcon: d.selectedIcon,
            label: Text(d.label),
          ),
      ],
      body: body,
    );
  }
}

/// Tablet-only layout: rail on the left, [body] filling the rest.
class TabletRailScaffold extends StatelessWidget {
  const TabletRailScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.leading,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationRailDestination> destinations;
  final Widget body;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.background,
              groupAlignment: -0.85,
              leading: leading == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: leading,
                    ),
              destinations: destinations,
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

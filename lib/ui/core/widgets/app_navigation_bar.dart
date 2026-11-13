import 'package:flutter/material.dart';

/// The bottom bar of every page: Home, Procedures, Checklists and Settings.
///
/// Home, Checklists and Settings are wired. Procedures is shown disabled
/// until its page exists. The app shell shows it under every routed page.
class AppNavigationBar extends StatelessWidget {
  /// Creates the bar.
  const AppNavigationBar({
    required this.selectedIndex,
    required this.checklistsEnabled,
    required this.onHome,
    required this.onChecklists,
    required this.onSettings,
    super.key,
  });

  /// The entry of the page on screen: 0 Home, 2 Checklists, 3 Settings.
  final int selectedIndex;

  /// Whether a checklist is loaded, so the Checklists page has something to
  /// show.
  final bool checklistsEnabled;

  /// Called when Home is tapped.
  final VoidCallback onHome;

  /// Called when Checklists is tapped.
  final VoidCallback onChecklists;

  /// Called when Settings is tapped.
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            onHome();
          case 2:
            onChecklists();
          case 3:
            onSettings();
        }
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        const NavigationDestination(
          enabled: false,
          icon: Icon(Icons.menu_book_outlined),
          label: 'Procedures',
        ),
        NavigationDestination(
          enabled: checklistsEnabled,
          icon: const Icon(Icons.checklist),
          label: 'Checklists',
        ),
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../people/people_screen.dart';
import '../reminders/reminders_screen.dart';
import '../settings/settings_screen.dart';
import 'add_entry_sheet.dart';

/// The signed-in app: five destinations along the bottom. The middle "+" does
/// not switch tabs; it opens the add sheet. Tabs are kept alive so each keeps
/// its scroll position and search.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _addIndex = 2;

  int _selected = 0;

  /// Index into the tab stack (the "+" has no tab of its own).
  int get _stackIndex => _selected > _addIndex ? _selected - 1 : _selected;

  void _onSelected(int index) {
    if (index == _addIndex) {
      showAddEntrySheet(context);
      return;
    }
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _stackIndex,
        children: const [
          HomeScreen(),
          PeopleScreen(),
          RemindersScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: _onSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle, size: 36),
            label: 'Add',
          ),
          NavigationDestination(
            icon: Icon(Icons.alarm_outlined),
            selectedIcon: Icon(Icons.alarm),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

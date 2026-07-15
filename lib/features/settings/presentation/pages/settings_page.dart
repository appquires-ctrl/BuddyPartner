import 'package:flutter/material.dart';
import 'package:dating_app/core/widgets/feedback/app_empty_state.dart';

/// SettingsPage displays account preferences configurations.
/// Currently stubbed with an AppEmptyState illustration placeholder.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: const AppEmptyState(
        icon: Icons.settings_suggest_outlined,
        title: 'Settings Preferences',
        description: 'Manage coin balance alerts, account settings, notifications, and block lists.',
      ),
    );
  }
}

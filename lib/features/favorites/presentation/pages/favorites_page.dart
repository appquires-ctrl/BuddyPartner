import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/feedback/app_empty_state.dart';

/// FavoritesPage displays the list of user-favorited telecallers.
/// Currently stubbed with an AppEmptyState illustration placeholder.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: const AppEmptyState(
        icon: Icons.explore_outlined,
        title: 'Start Discovering',
        description:
            'Search by username or discover members you can connect with.',
      ),
    );
  }
}

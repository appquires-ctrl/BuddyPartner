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
        title: const Text('Favorites'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: const AppEmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'No Favorites Yet',
        description: 'Keep track of members you enjoyed talking to by adding them to your favorites.',
      ),
    );
  }
}

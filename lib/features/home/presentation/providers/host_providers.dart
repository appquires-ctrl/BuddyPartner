import 'package:flutter_riverpod/flutter_riverpod.dart';

/// HostUiModel represents the presentation model for host telecallers.
class HostUiModel {
  final String id;
  final String name;
  final int age;
  final String avatarUrl;
  final double rating;
  final int reviewsCount;
  final int ratePerMin;
  final bool isOnline;

  const HostUiModel({
    required this.id,
    required this.name,
    required this.age,
    required this.avatarUrl,
    required this.rating,
    required this.reviewsCount,
    required this.ratePerMin,
    required this.isOnline,
  });
}

/// hostsProvider supplies an empty list of host telecallers.
final hostsProvider = Provider<List<HostUiModel>>((ref) {
  return const []; // Cleaned up all mock telecaller users
});

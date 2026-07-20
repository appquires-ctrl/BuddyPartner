import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

/// CallLog represents an individual call history record.
class CallLog {
  final String id;
  final String callerId;
  final String matchedUserId;
  final String status;
  final String callType; // 'voice' or 'video'
  final int durationSeconds;
  final DateTime startedAt;
  final String otherUserName;
  final String? otherUserAvatar;

  CallLog({
    required this.id,
    required this.callerId,
    required this.matchedUserId,
    required this.status,
    required this.callType,
    required this.durationSeconds,
    required this.startedAt,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  factory CallLog.fromJson(Map<String, dynamic> json, String currentUserId) {
    debugPrint('CallLog JSON row: $json');
    debugPrint('CallLog currentUserId: $currentUserId');

    final callerJson = json['caller'];
    final matchedUserJson = json['matched_user'];

    dynamic otherUserJson;

    // Find the profile that doesn't belong to the current user
    if (callerJson != null && callerJson is Map && callerJson['id'] != currentUserId) {
      otherUserJson = callerJson;
    } else if (matchedUserJson != null && matchedUserJson is Map && matchedUserJson['id'] != currentUserId) {
      otherUserJson = matchedUserJson;
    } else {
      // Fallback if one of the sides is null
      final isCaller = json['caller_id'] == currentUserId;
      otherUserJson = isCaller ? matchedUserJson : callerJson;
    }

    String otherName = 'User';
    String? otherAvatar;

    if (otherUserJson != null && otherUserJson is Map) {
      otherName = (otherUserJson['full_name'] ?? otherUserJson['fullName']) as String? ?? 'User';
      otherAvatar = (otherUserJson['avatar_url'] ?? otherUserJson['avatarUrl']) as String?;
    }

    return CallLog(
      id: json['id'] as String? ?? '',
      callerId: json['caller_id'] as String? ?? '',
      matchedUserId: json['matched_user_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      callType: json['call_type'] as String? ?? 'voice',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ?? DateTime.now(),
      otherUserName: otherName,
      otherUserAvatar: otherAvatar,
    );
  }
}

/// Provider to fetch and cache call history records for the current user.
final callHistoryProvider = FutureProvider.autoDispose<List<CallLog>>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return const [];

  try {
    final apiClient = ref.watch(apiClientProvider);
    final response = await apiClient.dio.get('/api/calls/history');
    
    if (response.data == null) return const [];
    
    final list = List<Map<String, dynamic>>.from(response.data as List);
    return list.map((json) => CallLog.fromJson(json, user.id)).toList();
  } catch (e, stackTrace) {
    debugPrint('Error fetching call history: $e\n$stackTrace');
    rethrow;
  }
});

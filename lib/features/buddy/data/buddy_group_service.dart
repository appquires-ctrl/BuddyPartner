import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

final buddyGroupServiceProvider = Provider<BuddyGroupService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return BuddyGroupService(apiClient);
});

final myBuddyGroupsProvider = FutureProvider.autoDispose<List<BuddyGroup>>((ref) async {
  final service = ref.watch(buddyGroupServiceProvider);
  return service.getMyGroups();
});

class BuddyGroupService {
  final ApiClient _apiClient;

  BuddyGroupService(this._apiClient);

  String _extractError(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    } else if (data is String && data.isNotEmpty && !data.startsWith('<!DOCTYPE') && !data.startsWith('<html')) {
      return data;
    }
    return e.message ?? fallback;
  }

  /// Host creates a 6-person Garba Buddy Group Broadcast (509 coins deducted from host).
  Future<BuddyGroup> createGroupBroadcast({
    required String city,
    String targetGender = 'all',
    String? title,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/buddy-group/broadcast',
        data: {
          'city': city.trim(),
          'targetGender': targetGender,
          if (title != null && title.isNotEmpty) 'title': title.trim(),
        },
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final groupData = response.data['group'] as Map<String, dynamic>;
        return BuddyGroup.fromJson(groupData);
      }
      throw Exception(response.data?['message'] ?? 'Failed to create Garba group');
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Failed to create Garba group'));
    }
  }

  /// List open Garba groups with available slots in the city.
  Future<List<BuddyGroup>> listOpenGroups({
    String? city,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
        if (city != null && city.isNotEmpty) 'city': city.trim(),
      };

      final response = await _apiClient.dio.get(
        '/api/buddy-group/open',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawList = response.data['groups'] as List<dynamic>? ?? [];
        return rawList.map((j) => BuddyGroup.fromJson(j as Map<String, dynamic>)).toList();
      }
      return [];
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Failed to fetch open groups'));
    }
  }

  /// Join a Garba Buddy Group (0 coins, 0 OTP).
  Future<BuddyGroup> joinGroup(String groupId) async {
    try {
      final response = await _apiClient.dio.post('/api/buddy-group/$groupId/join');

      if (response.statusCode == 200 && response.data != null) {
        final groupData = response.data['group'] as Map<String, dynamic>? ?? {};
        return BuddyGroup.fromJson(groupData);
      }
      throw Exception(response.data?['message'] ?? 'Failed to join Garba group');
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Failed to join group'));
    }
  }

  /// Get all groups the user has joined (for Chat Tab -> Groups section).
  Future<List<BuddyGroup>> getMyGroups() async {
    try {
      final response = await _apiClient.dio.get('/api/buddy-group/my-groups');

      if (response.statusCode == 200 && response.data != null) {
        final rawList = response.data['groups'] as List<dynamic>? ?? [];
        return rawList.map((j) => BuddyGroup.fromJson(j as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      // Return empty list on network/404 errors so UI gracefully renders
      return [];
    }
  }

  /// Get group details and 6 members.
  Future<Map<String, dynamic>> getGroupDetails(String groupId) async {
    try {
      final response = await _apiClient.dio.get('/api/buddy-group/$groupId/details');
      if (response.statusCode == 200 && response.data != null) {
        return response.data['group'] as Map<String, dynamic>;
      }
      throw Exception('Failed to load group details');
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Failed to load group details'));
    }
  }

  /// Fetch message history.
  Future<List<Map<String, dynamic>>> getGroupMessages(String groupId, {int limit = 50, String? before}) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/buddy-group/$groupId/messages',
        queryParameters: {
          'limit': limit,
          if (before != null && before.isNotEmpty) 'before': before,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        final rawList = response.data['messages'] as List<dynamic>? ?? [];
        return rawList.cast<Map<String, dynamic>>();
      }
      return [];
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Failed to load messages'));
    }
  }

  /// Send message via REST.
  Future<Map<String, dynamic>> sendGroupMessage(String groupId, String content) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/buddy-group/$groupId/messages',
        data: {'content': content},
      );
      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        return response.data['message'] as Map<String, dynamic>;
      }
      throw Exception('Failed to send message');
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Failed to send message'));
    }
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

final buddyServiceProvider = Provider<BuddyService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return BuddyService(apiClient, ref);
});

class BuddyService {
  final ApiClient _apiClient;
  final Ref _ref;

  BuddyService(this._apiClient, this._ref);

  String? get _currentUserId => _ref.read(authStateProvider).value?.id;

  /// Post a new broadcast Buddy Activity Request.
  /// Deducts 100 coins immediately.
  Future<BuddyRequest> createRequest({
    required BuddyType buddyType,
    required String city,
    required BuddyTargetGender targetGender,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/buddy/request',
        data: {
          'buddyType': buddyType.id,
          'city': city.trim(),
          'targetGender': targetGender.id,
        },
      );

      if (response.statusCode == 201 && response.data != null) {
        final requestData = response.data['request'] as Map<String, dynamic>;
        return BuddyRequest.fromJson(requestData, currentUserId: _currentUserId);
      }
      throw Exception(response.data?['message'] ?? 'Failed to create buddy request');
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? 'Network error';
      throw Exception(msg);
    }
  }

  /// List open requests in a city visible to current user.
  Future<List<BuddyRequest>> listOpenRequests({
    String? city,
    BuddyType? buddyType,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };
      if (city != null && city.trim().isNotEmpty) {
        queryParams['city'] = city.trim();
      }
      if (buddyType != null) {
        queryParams['buddyType'] = buddyType.id;
      }

      final response = await _apiClient.dio.get(
        '/api/buddy/requests',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        final list = (response.data['requests'] as List<dynamic>?) ?? [];
        return list
            .map((item) => BuddyRequest.fromJson(item as Map<String, dynamic>, currentUserId: _currentUserId))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Atomically accept an open buddy request.
  Future<BuddyRequest> acceptRequest(String requestId) async {
    try {
      final response = await _apiClient.dio.post('/api/buddy/requests/$requestId/accept');

      if (response.statusCode == 200 && response.data != null) {
        final requestData = response.data['request'] as Map<String, dynamic>;
        return BuddyRequest.fromJson(requestData, currentUserId: _currentUserId);
      }
      throw Exception(response.data?['message'] ?? 'Failed to accept buddy request');
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? 'Failed to accept buddy request';
      throw Exception(msg);
    }
  }

  /// Submit the 6-digit handshake OTP to verify and unlock chat.
  Future<Map<String, dynamic>> verifyOtp({
    required String requestId,
    required String otpCode,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/api/buddy/requests/$requestId/verify-otp',
        data: {'otpCode': otpCode.trim()},
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception(response.data?['message'] ?? 'Failed to verify OTP');
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? 'Invalid OTP';
      throw Exception(msg);
    }
  }

  /// Fetch user's active/recent requests.
  Future<List<BuddyRequest>> getMyRequests() async {
    try {
      final response = await _apiClient.dio.get('/api/buddy/requests/my');
      if (response.statusCode == 200 && response.data != null) {
        final list = (response.data['requests'] as List<dynamic>?) ?? [];
        return list
            .map((item) => BuddyRequest.fromJson(item as Map<String, dynamic>, currentUserId: _currentUserId))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}

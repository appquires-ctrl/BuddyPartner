import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/api_client.dart';
import '../../domain/advertisement.dart';

final activeAdvertisementsProvider = FutureProvider<List<Advertisement>>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/api/advertisements/active');
    
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      if (data['success'] == true && data['advertisements'] is List) {
        return (data['advertisements'] as List)
            .map((item) => Advertisement.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  } catch (e) {
    debugPrint('Error fetching active advertisements: $e');
    return [];
  }
});

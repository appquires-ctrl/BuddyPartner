import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';

class CloudinaryUploadService {
  CloudinaryUploadService._();

  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5MB limit

  // Cloudinary credentials for direct client-side upload
  static const String cloudName = 'o8dwm2ig';
  static const String apiKey = '579652961933726';
  static const String apiSecret = '2bXI1THE9xSSdnjI33l2hv5SkSE';

  /// Prompts gallery image picker, validates size, and uploads to Cloudinary storage.
  /// Returns the Cloudinary HTTPS URL string on success, or null on cancel/error.
  static Future<String?> pickAndUploadAvatar({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final picker = ImagePicker();

    XFile? pickedFile;
    try {
      pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.showError(context, 'Failed to open gallery: $e');
      }
      return null;
    }

    // Handle user cancellation gracefully
    if (pickedFile == null) {
      return null;
    }

    // Validate file size (< 5MB)
    try {
      final fileLength = await pickedFile.length();
      if (fileLength > maxFileSizeBytes) {
        if (context.mounted) {
          AppSnackBar.showError(context, 'Image size must be less than 5MB.');
        }
        return null;
      }
    } catch (_) {}

    // Method A: Backend route — uploads to Cloudinary AND persists URL to DB in one step
    try {
      final apiClient = ref.read(apiClientProvider);

      MultipartFile multipartFile;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        multipartFile = MultipartFile.fromBytes(
          bytes,
          filename: pickedFile.name.isNotEmpty ? pickedFile.name : 'avatar.jpg',
        );
      } else {
        multipartFile = await MultipartFile.fromFile(
          pickedFile.path,
          filename: pickedFile.name.isNotEmpty ? pickedFile.name : 'avatar.jpg',
        );
      }

      final formData = FormData.fromMap({'file': multipartFile});

      final response = await apiClient.dio.post(
        '/api/auth/upload-avatar',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final imageUrl = data['imageUrl'] ?? data['url'];
        if (imageUrl != null && imageUrl.toString().trim().isNotEmpty) {
          return imageUrl.toString().trim();
        }
      }
    } catch (backendErr) {
      if (kDebugMode) {
        debugPrint('Backend upload failed, falling back to direct Cloudinary: $backendErr');
      }
    }

    // Method B: Direct signed upload to Cloudinary (fallback — does NOT auto-save to DB)
    try {
      final directUrl = await _uploadDirectToCloudinary(pickedFile);
      if (directUrl != null && directUrl.trim().isNotEmpty) {
        // Also persist via a lightweight backend PATCH call
        try {
          final apiClient = ref.read(apiClientProvider);
          await apiClient.dio.post('/api/auth/profile', data: {'avatarSeed': directUrl.trim()});
        } catch (_) {
          // Best-effort DB persist; URL still returned for local UI update
        }
        return directUrl.trim();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Direct Cloudinary upload also failed: $e');
      }
    }

    if (context.mounted) {
      AppSnackBar.showError(context, 'Failed to upload photo. Please try again.');
    }
    return null;
  }

  /// Direct signed upload to Cloudinary API
  static Future<String?> _uploadDirectToCloudinary(XFile pickedFile) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    const folder = 'buddypartner/avatars';
    final toSign = 'folder=$folder&timestamp=$timestamp$apiSecret';
    final signature = sha1.convert(utf8.encode(toSign)).toString();

    MultipartFile multipartFile;
    if (kIsWeb) {
      final bytes = await pickedFile.readAsBytes();
      multipartFile = MultipartFile.fromBytes(
        bytes,
        filename: pickedFile.name.isNotEmpty ? pickedFile.name : 'avatar.jpg',
      );
    } else {
      multipartFile = await MultipartFile.fromFile(
        pickedFile.path,
        filename: pickedFile.name.isNotEmpty ? pickedFile.name : 'avatar.jpg',
      );
    }

    final dio = Dio();
    final formData = FormData.fromMap({
      'file': multipartFile,
      'api_key': apiKey,
      'timestamp': timestamp,
      'folder': folder,
      'signature': signature,
    });

    final response = await dio.post(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      data: formData,
    );

    if (response.statusCode == 200 && response.data != null) {
      final secureUrl = response.data['secure_url'] ?? response.data['url'];
      if (secureUrl != null && secureUrl.toString().trim().isNotEmpty) {
        return secureUrl.toString().trim();
      }
    }
    return null;
  }
}

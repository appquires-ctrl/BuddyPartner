import 'dart:io';
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

    // Upload to Backend Cloudinary Endpoint
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

      final formData = FormData.fromMap({
        'file': multipartFile,
      });

      final response = await apiClient.dio.post(
        '/api/auth/upload-avatar',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final imageUrl = data['imageUrl'] ?? data['url'];
        if (imageUrl != null && imageUrl.toString().trim().isNotEmpty) {
          return imageUrl.toString().trim();
        }
      }

      if (context.mounted) {
        AppSnackBar.showError(context, 'Failed to upload photo. Please try again.');
      }
      return null;
    } catch (err) {
      if (context.mounted) {
        String msg = 'Error uploading photo. Please try again.';
        if (err is DioException && err.response?.data != null) {
          final errData = err.response?.data;
          if (errData is Map && (errData['error'] != null || errData['message'] != null)) {
            msg = errData['error'] ?? errData['message'];
          }
        }
        AppSnackBar.showError(context, msg);
      }
      return null;
    }
  }
}

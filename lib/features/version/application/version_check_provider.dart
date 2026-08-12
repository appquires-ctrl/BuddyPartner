import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:buddypartner/core/services/api_client.dart';

class VersionCheckState {
  final bool isLoading;
  final bool updateRequired;
  final String minimumSupportedVersion;
  final String currentVersion;
  final String storeUrl;
  final String? error;

  const VersionCheckState({
    this.isLoading = false,
    this.updateRequired = false,
    this.minimumSupportedVersion = '1.0.0',
    this.currentVersion = '1.0.0',
    this.storeUrl = 'https://play.google.com/store/apps/details?id=com.buddypartner.app',
    this.error,
  });

  VersionCheckState copyWith({
    bool? isLoading,
    bool? updateRequired,
    String? minimumSupportedVersion,
    String? currentVersion,
    String? storeUrl,
    String? error,
  }) {
    return VersionCheckState(
      isLoading: isLoading ?? this.isLoading,
      updateRequired: updateRequired ?? this.updateRequired,
      minimumSupportedVersion: minimumSupportedVersion ?? this.minimumSupportedVersion,
      currentVersion: currentVersion ?? this.currentVersion,
      storeUrl: storeUrl ?? this.storeUrl,
      error: error,
    );
  }
}

class VersionCheckNotifier extends Notifier<VersionCheckState> {
  @override
  VersionCheckState build() {
    Future.microtask(() => checkVersion());
    return const VersionCheckState(isLoading: true);
  }

  Future<void> checkVersion() async {
    state = state.copyWith(isLoading: true);

    String currentVerStr = '1.0.0';
    try {
      if (!kIsWeb) {
        final pkg = await PackageInfo.fromPlatform();
        currentVerStr = pkg.version;
      }
    } catch (e) {
      debugPrint('[VersionCheck] Error reading PackageInfo: $e');
    }

    final platform = kIsWeb ? 'android' : (Platform.isIOS ? 'ios' : 'android');
    final apiClient = ref.read(apiClientProvider);

    try {
      final response = await apiClient.dio.get(
        '/api/app/version-check',
        queryParameters: {
          'platform': platform,
          'currentVersion': currentVerStr,
        },
      );

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final minVerStr = (data['minimumSupportedVersion'] ?? '1.0.0').toString();
        final storeUrl = (data['storeUrl'] ?? '').toString();
        final serverUpdateReq = data['updateRequired'] == true;

        bool isOutdated = serverUpdateReq;
        try {
          final curVer = Version.parse(currentVerStr);
          final minVer = Version.parse(minVerStr);
          isOutdated = curVer < minVer;
        } catch (_) {
          // Fallback to server flag if semver parsing fails
        }

        state = VersionCheckState(
          isLoading: false,
          updateRequired: isOutdated,
          minimumSupportedVersion: minVerStr,
          currentVersion: currentVerStr,
          storeUrl: storeUrl.isNotEmpty
              ? storeUrl
              : (platform == 'ios'
                  ? 'https://apps.apple.com/app/id6400000000'
                  : 'https://play.google.com/store/apps/details?id=com.buddypartner.app'),
        );
        return;
      }
    } catch (e) {
      debugPrint('[VersionCheck] Network check failed ($e) — failing open to allow app startup');
    }

    // Fail open policy if version check network call fails
    state = state.copyWith(
      isLoading: false,
      updateRequired: false,
      currentVersion: currentVerStr,
    );
  }

  void forceUpdateRequired({required String minVersion, required String storeUrl}) {
    state = state.copyWith(
      isLoading: false,
      updateRequired: true,
      minimumSupportedVersion: minVersion,
      storeUrl: storeUrl,
    );
  }
}

final versionCheckProvider = NotifierProvider<VersionCheckNotifier, VersionCheckState>(
  VersionCheckNotifier.new,
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/version/application/version_check_provider.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';

class UpdateRequiredPage extends ConsumerStatefulWidget {
  const UpdateRequiredPage({super.key});

  @override
  ConsumerState<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends ConsumerState<UpdateRequiredPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Automatically re-check minimum version when user returns from Play Store / App Store
      ref.read(versionCheckProvider.notifier).checkVersion();
    }
  }

  Future<void> _launchStore(String urlStr) async {
    try {
      final uri = Uri.parse(urlStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('[UpdateRequiredPage] Failed to launch store URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final versionState = ref.watch(versionCheckProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.surfaceMuted,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),

                // Rocket / System Update Icon Badge
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    size: 48,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space32),

                // Title
                Text(
                  'Update Required',
                  style: typography.titleCard.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space12),

                // Body description
                Text(
                  'A new version of BuddyPartner is available with important updates and security improvements. Please update to continue.',
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space20),

                // Version details badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'Installed: v${versionState.currentVersion}  •  Required: v${versionState.minimumSupportedVersion}',
                    style: typography.bodySmall.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),

                const Spacer(),

                // Update Now primary button
                AppPrimaryButton(
                  text: 'Update Now',
                  icon: const Icon(Icons.download_rounded, size: 20, color: Colors.white),
                  onPressed: () => _launchStore(versionState.storeUrl),
                ),
                const SizedBox(height: 12),

                // Manual fallback check again button
                TextButton(
                  onPressed: () => ref.read(versionCheckProvider.notifier).checkVersion(),
                  child: Text(
                    'Already updated? Check again',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.space24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

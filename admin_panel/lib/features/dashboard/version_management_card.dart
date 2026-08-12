import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_colors.dart';
import '../../providers/admin_providers.dart';
import '../../services/api_service.dart';

class VersionManagementCard extends ConsumerStatefulWidget {
  const VersionManagementCard({super.key});

  @override
  ConsumerState<VersionManagementCard> createState() => _VersionManagementCardState();
}

class _VersionManagementCardState extends ConsumerState<VersionManagementCard> {
  final _androidVersionCtrl = TextEditingController();
  final _iosVersionCtrl = TextEditingController();
  bool _isSavingAndroid = false;
  bool _isSavingIos = false;

  @override
  void dispose() {
    _androidVersionCtrl.dispose();
    _iosVersionCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateVersion(String platform, String version) async {
    if (version.trim().isEmpty) return;

    if (platform == 'android') setState(() => _isSavingAndroid = true);
    if (platform == 'ios') setState(() => _isSavingIos = true);

    try {
      await ApiService.put(
        '/app-config/minimum-version',
        body: {
          'platform': platform,
          'version': version.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully updated $platform minimum version to $version'),
            backgroundColor: AdminColors.success,
          ),
        );
        ref.invalidate(appConfigProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update version: $e'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingAndroid = false;
          _isSavingIos = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(appConfigProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.system_update_rounded, color: AdminColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Minimum Supported App Version (Forced Update Gate)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AdminColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'App builds running versions lower than these will be blocked and forced to update via Play Store / App Store.',
            style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 16),

          configAsync.when(
            data: (config) {
              final androidMin = config['minimum_supported_version_android'] ?? '1.0.0';
              final iosMin = config['minimum_supported_version_ios'] ?? '1.0.0';

              if (_androidVersionCtrl.text.isEmpty) _androidVersionCtrl.text = androidMin;
              if (_iosVersionCtrl.text.isEmpty) _iosVersionCtrl.text = iosMin;

              return Row(
                children: [
                  // Android Platform Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.android, size: 18, color: Color(0xFF3DDC84)),
                              SizedBox(width: 6),
                              Text('Android', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _androidVersionCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Min Version',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isSavingAndroid
                                    ? null
                                    : () => _updateVersion('android', _androidVersionCtrl.text),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AdminColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: _isSavingAndroid
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Save'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // iOS Platform Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.apple, size: 18, color: Colors.black87),
                              SizedBox(width: 6),
                              Text('iOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _iosVersionCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Min Version',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isSavingIos
                                    ? null
                                    : () => _updateVersion('ios', _iosVersionCtrl.text),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AdminColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: _isSavingIos
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Save'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: AdminColors.primary)),
            error: (err, _) => Text('Error loading version config: $err', style: const TextStyle(color: AdminColors.danger)),
          ),
        ],
      ),
    );
  }
}

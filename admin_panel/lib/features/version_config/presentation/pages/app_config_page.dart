import 'package:flutter/material.dart';
import '../../../../services/api_service.dart';

class AppConfigPage extends StatefulWidget {
  const AppConfigPage({super.key});

  @override
  State<AppConfigPage> createState() => _AppConfigPageState();
}

class _AppConfigPageState extends State<AppConfigPage> {
  bool _isLoading = true;
  bool _isSavingAndroid = false;
  bool _isSavingIos = false;
  String? _errorMessage;

  final _androidVersionController = TextEditingController();
  final _androidStoreUrlController = TextEditingController();
  final _iosVersionController = TextEditingController();
  final _iosStoreUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAppConfig();
  }

  @override
  void dispose() {
    _androidVersionController.dispose();
    _androidStoreUrlController.dispose();
    _iosVersionController.dispose();
    _iosStoreUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchAppConfig() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.get('/app-config');
      if (res['success'] == true && res['config'] is Map) {
        final config = res['config'] as Map<String, dynamic>;
        setState(() {
          _androidVersionController.text = config['minimum_supported_version_android']?.toString() ?? '1.0.0';
          _androidStoreUrlController.text = config['store_url_android']?.toString() ?? '';
          _iosVersionController.text = config['minimum_supported_version_ios']?.toString() ?? '1.0.0';
          _iosStoreUrlController.text = config['store_url_ios']?.toString() ?? '';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Failed to load app config';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfig(String platform) async {
    final isAndroid = platform.toLowerCase() == 'android';
    final version = isAndroid ? _androidVersionController.text.trim() : _iosVersionController.text.trim();
    final storeUrl = isAndroid ? _androidStoreUrlController.text.trim() : _iosStoreUrlController.text.trim();

    if (version.isEmpty) {
      _showSnackBar('Please enter a valid version string');
      return;
    }

    setState(() {
      if (isAndroid) {
        _isSavingAndroid = true;
      } else {
        _isSavingIos = true;
      }
    });

    try {
      final res = await ApiService.put('/app-config/minimum-version', body: {
        'platform': platform,
        'version': version,
        'storeUrl': storeUrl,
      });

      if (res['success'] == true) {
        _showSnackBar(res['message'] ?? 'Successfully updated $platform version config!');
        _fetchAppConfig();
      } else {
        _showSnackBar(res['message'] ?? 'Failed to update version config');
      }
    } catch (e) {
      _showSnackBar('Error saving $platform config: $e');
    } finally {
      setState(() {
        if (isAndroid) {
          _isSavingAndroid = false;
        } else {
          _isSavingIos = false;
        }
      });
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'App Version Gate Config',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Enforce minimum required app versions and update store links per platform.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _fetchAppConfig,
                  tooltip: 'Refresh Config',
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
            else if (_errorMessage != null)
              Center(child: Text('Error: $_errorMessage', style: const TextStyle(color: Colors.red)))
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Android Config Card
                  Expanded(
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.android, color: Colors.green, size: 28),
                                SizedBox(width: 10),
                                Text(
                                  'Android Configuration',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _androidVersionController,
                              decoration: const InputDecoration(
                                labelText: 'Minimum Supported Version',
                                hintText: '1.0.0',
                                border: OutlineInputBorder(),
                                helperText: 'Users on versions below this will be forced to update.',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _androidStoreUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Google Play Store URL',
                                hintText: 'https://play.google.com/store/apps/details?id=...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSavingAndroid ? null : () => _saveConfig('android'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: _isSavingAndroid
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text('Update Android Version Gate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),

                  // iOS Config Card
                  Expanded(
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.apple, color: Colors.black, size: 28),
                                SizedBox(width: 10),
                                Text(
                                  'iOS Configuration',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _iosVersionController,
                              decoration: const InputDecoration(
                                labelText: 'Minimum Supported Version',
                                hintText: '1.0.0',
                                border: OutlineInputBorder(),
                                helperText: 'Users on versions below this will be forced to update.',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _iosStoreUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Apple App Store URL',
                                hintText: 'https://apps.apple.com/app/id...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSavingIos ? null : () => _saveConfig('ios'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: _isSavingIos
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text('Update iOS Version Gate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

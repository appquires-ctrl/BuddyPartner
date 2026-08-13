import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../services/api_service.dart';
import '../../data/advertisement_model.dart';

class AdvertisementsPage extends StatefulWidget {
  const AdvertisementsPage({super.key});

  @override
  State<AdvertisementsPage> createState() => _AdvertisementsPageState();
}

class _AdvertisementsPageState extends State<AdvertisementsPage> {
  List<Advertisement> _ads = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Form State
  bool _isSaving = false;
  String? _editingAdId;
  String? _uploadedImageUrl;
  PlatformFile? _pickedFile;

  final _imageUrlController = TextEditingController();
  final _clickUrlController = TextEditingController();
  final _displayOrderController = TextEditingController(text: '0');
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _fetchAds();
  }

  @override
  void dispose() {
    _imageUrlController.dispose();
    _clickUrlController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  Future<void> _fetchAds() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiService.get('/advertisements');
      if (res['success'] == true && res['advertisements'] is List) {
        final list = (res['advertisements'] as List)
            .map((item) => Advertisement.fromJson(item))
            .toList();
        setState(() {
          _ads = list;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Failed to load advertisements';
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

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.size > 5 * 1024 * 1024) {
          _showSnackBar('File too large. Maximum size is 5MB.');
          return;
        }

        setState(() {
          _pickedFile = file;
          _isSaving = true;
        });

        // Upload to backend
        final res = await ApiService.uploadFile(
          '/advertisements/upload-image',
          file.bytes!,
          file.name,
        );

        if (res['success'] == true && res['imageUrl'] != null) {
          setState(() {
            _uploadedImageUrl = res['imageUrl'];
            _imageUrlController.text = res['imageUrl'];
            _isSaving = false;
          });
          _showSnackBar('Image uploaded successfully!');
        } else {
          setState(() {
            _isSaving = false;
          });
          _showSnackBar(res['message'] ?? 'Failed to upload image');
        }
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      _showSnackBar('Error picking/uploading file: $e');
    }
  }

  bool _isValidHttpUrl(String url) {
    if (url.trim().isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _saveAd() async {
    final imageUrl = _imageUrlController.text.trim();
    final clickUrl = _clickUrlController.text.trim();
    final displayOrder = int.tryParse(_displayOrderController.text.trim()) ?? 0;

    if (imageUrl.isEmpty) {
      _showSnackBar('Please upload or enter an Image URL');
      return;
    }

    if (!_isValidHttpUrl(clickUrl)) {
      _showSnackBar('Please enter a valid http:// or https:// Click URL');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      if (_editingAdId == null) {
        // Create new ad
        final res = await ApiService.post('/advertisements', body: {
          'imageUrl': imageUrl,
          'clickUrl': clickUrl,
          'isActive': _isActive,
          'displayOrder': displayOrder,
        });

        if (res['success'] == true) {
          _showSnackBar('Advertisement created successfully!');
          _resetForm();
          _fetchAds();
        } else {
          _showSnackBar(res['message'] ?? 'Failed to create advertisement');
        }
      } else {
        // Edit existing ad
        final res = await ApiService.put('/advertisements/$_editingAdId', body: {
          'imageUrl': imageUrl,
          'clickUrl': clickUrl,
          'isActive': _isActive,
          'displayOrder': displayOrder,
        });

        if (res['success'] == true) {
          _showSnackBar('Advertisement updated successfully!');
          _resetForm();
          _fetchAds();
        } else {
          _showSnackBar(res['message'] ?? 'Failed to update advertisement');
        }
      }
    } catch (e) {
      _showSnackBar('Error saving advertisement: $e');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteAd(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Advertisement'),
        content: const Text('Are you sure you want to delete this advertisement?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await ApiService.delete('/advertisements/$id');
        if (res['success'] == true) {
          _showSnackBar('Advertisement deleted!');
          _fetchAds();
        } else {
          _showSnackBar(res['message'] ?? 'Failed to delete advertisement');
        }
      } catch (e) {
        _showSnackBar('Error deleting advertisement: $e');
      }
    }
  }

  void _editAd(Advertisement ad) {
    setState(() {
      _editingAdId = ad.id;
      _imageUrlController.text = ad.imageUrl;
      _uploadedImageUrl = ad.imageUrl;
      _clickUrlController.text = ad.clickUrl;
      _displayOrderController.text = ad.displayOrder.toString();
      _isActive = ad.isActive;
    });
  }

  void _resetForm() {
    setState(() {
      _editingAdId = null;
      _uploadedImageUrl = null;
      _pickedFile = null;
      _imageUrlController.clear();
      _clickUrlController.clear();
      _displayOrderController.text = '0';
      _isActive = true;
    });
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
                      'Home Screen Advertisements',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage dynamic ad banners shown at the bottom of the home screen.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _fetchAds,
                  tooltip: 'Refresh Advertisements',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Form Card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingAdId == null ? 'Create New Advertisement' : 'Edit Advertisement',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Image Upload / Preview Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Uploaded Image Box
                        Container(
                          width: 140,
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: _uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _uploadedImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                )
                              : const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined, color: Colors.grey),
                                      SizedBox(height: 4),
                                      Text('No image', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),

                        // Upload button & Manual URL input
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isSaving ? null : _pickImage,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: Text(_pickedFile == null ? 'Upload Banner Image' : 'Change Image'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _imageUrlController,
                                decoration: const InputDecoration(
                                  labelText: 'Image CDN URL',
                                  hintText: 'https://...',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _uploadedImageUrl = val.trim();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Click URL Input
                    TextField(
                      controller: _clickUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Destination Click-Through URL',
                        hintText: 'https://example.com/promo',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Display Order & IsActive Row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _displayOrderController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Display Order (e.g. 0, 1, 2)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Row(
                          children: [
                            const Text('Active Status:', style: TextStyle(fontWeight: FontWeight.w600)),
                            Switch(
                              value: _isActive,
                              onChanged: (val) {
                                setState(() {
                                  _isActive = val;
                                });
                              },
                            ),
                            Text(_isActive ? 'Active' : 'Inactive', style: TextStyle(color: _isActive ? Colors.green : Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Submit buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_editingAdId != null) ...[
                          TextButton(
                            onPressed: _resetForm,
                            child: const Text('Cancel Edit'),
                          ),
                          const SizedBox(width: 12),
                        ],
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveAd,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                          child: _isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  _editingAdId == null ? 'Save Advertisement' : 'Update Advertisement',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Table of Advertisements
            const Text(
              'Existing Advertisements',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
            else if (_errorMessage != null)
              Center(child: Text('Error: $_errorMessage', style: const TextStyle(color: Colors.red)))
            else if (_ads.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('No advertisements created yet.')),
                ),
              )
            else
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _ads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final ad = _ads[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 70,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.grey.shade200,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            ad.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                      title: Text(
                        ad.clickUrl,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: ad.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ad.isActive ? Colors.green.shade300 : Colors.grey.shade300),
                            ),
                            child: Text(
                              ad.isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: ad.isActive ? Colors.green.shade700 : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('Order: ${ad.displayOrder}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 12),
                          Text('Clicks: ${ad.clickCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editAd(ad),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteAd(ad.id),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

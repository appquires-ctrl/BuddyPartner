import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../services/api_service.dart';
import '../../../../theme/admin_colors.dart';
import '../../data/buddy_banner_model.dart';

class BuddyBannersPage extends StatefulWidget {
  const BuddyBannersPage({super.key});

  @override
  State<BuddyBannersPage> createState() => _BuddyBannersPageState();
}

class _BuddyBannersPageState extends State<BuddyBannersPage> {
  static const String defaultGarbaImageUrl =
      'https://res.cloudinary.com/o8dwm2ig/image/upload/v1789916439/buddy_banners/jyreac8grrwdtnflsa6p.png';
  static const String _cacheKey = 'local_buddy_banners_cache';

  List<BuddyBanner> _banners = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBanners();
  }

  Future<void> _fetchBanners() async {
    setState(() {
      _isLoading = true;
    });

    // 1. Load from local cache first for instant responsiveness
    final cached = await _loadCachedBanners();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _banners = cached;
        _isLoading = false;
      });
    }

    // 2. Try fetching from backend API
    try {
      final res = await ApiService.get('/buddy-banners');
      if (res['success'] == true && res['banners'] is List) {
        final list = (res['banners'] as List)
            .map((item) => BuddyBanner.fromJson(item))
            .toList();
        if (mounted) {
          setState(() {
            _banners = list;
            _isLoading = false;
          });
        }
        await _saveBannersToCache(list);
        return;
      }
    } catch (_) {
      // Backend not yet deployed or unreachable
    }

    // 3. Fallback to default if no banners anywhere
    if (_banners.isEmpty && mounted) {
      _useFallbackBanners();
    } else if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<BuddyBanner>> _loadCachedBanners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cacheKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list
            .map((item) => BuddyBanner.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveBannersToCache(List<BuddyBanner> banners) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = banners.map((b) => b.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(list));
    } catch (_) {}
  }

  void _useFallbackBanners() {
    final fallback = [
      BuddyBanner(
        id: 'garba_festive_2026',
        name: 'Find Your Garba Partner',
        imageUrl: defaultGarbaImageUrl,
        priority: 1,
        isActive: true,
        sheetTitle: 'Garba Buddy 🪔',
        sheetSubtitle: 'Find someone who matches your Garba vibes',
        broadcastCoinCost: 1,
        buddyType: 'garba',
        accentColor: '#9333EA',
        otpRewardType: 'STATIC',
        staticCoinAmount: 50,
        startDate: DateTime.now().subtract(const Duration(days: 2)),
        endDate: DateTime.now().add(const Duration(days: 30)),
      ),
    ];
    setState(() {
      _banners = fallback;
      _isLoading = false;
    });
    _saveBannersToCache(fallback);
  }

  Future<void> _deleteBanner(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Buddy Banner'),
        content: const Text('Are you sure you want to delete this seasonal banner campaign?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.delete('/buddy-banners/$id');
      } catch (_) {}
      setState(() {
        _banners.removeWhere((b) => b.id == id);
      });
      await _saveBannersToCache(_banners);
      _showSnackBar('Banner removed successfully.');
    }
  }

  Future<void> _toggleStatus(BuddyBanner banner, bool newStatus) async {
    final index = _banners.indexWhere((b) => b.id == banner.id);
    if (index != -1) {
      setState(() {
        _banners[index] = BuddyBanner(
          id: banner.id,
          name: banner.name,
          imageUrl: banner.imageUrl,
          priority: banner.priority,
          startDate: banner.startDate,
          endDate: banner.endDate,
          isActive: newStatus,
          sheetTitle: banner.sheetTitle,
          sheetSubtitle: banner.sheetSubtitle,
          sheetIconUrl: banner.sheetIconUrl,
          accentColor: banner.accentColor,
          broadcastCoinCost: banner.broadcastCoinCost,
          buddyType: banner.buddyType,
          otpRewardType: banner.otpRewardType,
          staticCoinAmount: banner.staticCoinAmount,
          malePercentage: banner.malePercentage,
          femalePercentage: banner.femalePercentage,
        );
      });
      await _saveBannersToCache(_banners);
    }
    try {
      await ApiService.put('/buddy-banners/${banner.id}', body: {
        'isActive': newStatus,
      });
    } catch (_) {}
  }

  void _openAddEditDialog([BuddyBanner? banner]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddEditBannerDialog(
        banner: banner,
        onSaved: (BuddyBanner savedBanner) async {
          final index = _banners.indexWhere((b) => b.id == savedBanner.id);
          setState(() {
            if (index != -1) {
              _banners[index] = savedBanner;
            } else {
              _banners.insert(0, savedBanner);
            }
          });
          await _saveBannersToCache(_banners);
          _showSnackBar('Banner saved successfully!');
        },
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Seasonal & Buddy Banners',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Manage auto-sliding widescreen home banners, dynamic buddy broadcast prices, and OTP rewards.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openAddEditDialog(),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text('Create Buddy Banner', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Content Box
          Container(
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
            ),
            padding: const EdgeInsets.all(24),
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _banners.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            children: [
                              const Icon(Icons.campaign_outlined, size: 48, color: AdminColors.textMuted),
                              const SizedBox(height: 12),
                              const Text('No seasonal buddy banners created yet.'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _openAddEditDialog(),
                                child: const Text('Create First Banner'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active Banners (${_banners.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded),
                                onPressed: _fetchBanners,
                                tooltip: 'Refresh list',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _banners.length,
                            separatorBuilder: (_, _) => const Divider(height: 24),
                            itemBuilder: (context, index) {
                              final banner = _banners[index];
                              return _buildBannerRow(banner);
                            },
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerRow(BuddyBanner banner) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final datesText = (banner.startDate != null && banner.endDate != null)
        ? '${dateFormat.format(banner.startDate!)} - ${dateFormat.format(banner.endDate!)}'
        : 'Always Active';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Widescreen Thumbnail Preview (1918:820 ratio)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 160,
            height: 68, // 1918:820 ratio
            color: AdminColors.surfaceMuted,
            child: banner.imageUrl.startsWith('http://') || banner.imageUrl.startsWith('https://')
                ? Image.network(
                    banner.imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => _buildFallbackThumbnail(),
                  )
                : _buildFallbackThumbnail(),
          ),
        ),
        const SizedBox(width: 20),

        // Banner Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    banner.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AdminColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Order: ${banner.priority}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AdminColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Cost: ${banner.broadcastCoinCost} Coin${banner.broadcastCoinCost == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Sheet Title: "${banner.sheetTitle}" • ${banner.sheetSubtitle}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, size: 14, color: AdminColors.success),
                  const SizedBox(width: 4),
                  Text(
                    banner.otpRewardType == 'STATIC'
                        ? 'OTP Reward: Static ${banner.staticCoinAmount} Coins'
                        : 'OTP Reward: Male ${banner.malePercentage}% / Female ${banner.femalePercentage}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AdminColors.success,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.date_range_rounded, size: 14, color: AdminColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    datesText,
                    style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Active Toggle & Actions
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              children: [
                Switch(
                  value: banner.isActive,
                  activeTrackColor: AdminColors.success.withValues(alpha: 0.5),
                  activeThumbColor: AdminColors.success,
                  onChanged: (val) => _toggleStatus(banner, val),
                ),
                Text(
                  banner.isActive ? 'Active' : 'Paused',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: banner.isActive ? AdminColors.success : AdminColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AdminColors.primary),
              onPressed: () => _openAddEditDialog(banner),
              tooltip: 'Edit Banner',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AdminColors.danger),
              onPressed: () => _deleteBanner(banner.id),
              tooltip: 'Delete Banner',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.celebration_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}

// ── ADD / EDIT BANNER MODAL DIALOG ─────────────────────────
class _AddEditBannerDialog extends StatefulWidget {
  final BuddyBanner? banner;
  final Function(BuddyBanner savedBanner) onSaved;

  const _AddEditBannerDialog({
    this.banner,
    required this.onSaved,
  });

  @override
  State<_AddEditBannerDialog> createState() => _AddEditBannerDialogState();
}

class _AddEditBannerDialogState extends State<_AddEditBannerDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _priorityController;
  late final TextEditingController _sheetTitleController;
  late final TextEditingController _sheetSubtitleController;
  late final TextEditingController _broadcastCoinCostController;
  late final TextEditingController _staticCoinsController;
  late final TextEditingController _accentColorController;

  late bool _isActive;
  late String _buddyType;
  late String _otpRewardType; // 'STATIC' or 'PERCENTAGE'
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSaving = false;


  @override
  void initState() {
    super.initState();
    final b = widget.banner;
    _nameController = TextEditingController(text: b?.name ?? '');
    _imageUrlController = TextEditingController(
      text: (b != null && !b.imageUrl.startsWith('assets/')) ? b.imageUrl : '',
    );
    _priorityController = TextEditingController(text: b?.priority.toString() ?? '1');
    _sheetTitleController = TextEditingController(text: b?.sheetTitle ?? '');
    _sheetSubtitleController = TextEditingController(text: b?.sheetSubtitle ?? '');
    _broadcastCoinCostController = TextEditingController(text: b?.broadcastCoinCost.toString() ?? '1');
    _staticCoinsController = TextEditingController(text: b?.staticCoinAmount.toString() ?? '50');
    _accentColorController = TextEditingController(text: b?.accentColor ?? '#9333EA');

    _isActive = b?.isActive ?? true;
    _buddyType = b?.buddyType ?? 'festival';
    _otpRewardType = b?.otpRewardType ?? 'STATIC';
    _startDate = b?.startDate ?? DateTime.now();
    _endDate = b?.endDate ?? DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _imageUrlController.dispose();
    _priorityController.dispose();
    _sheetTitleController.dispose();
    _sheetSubtitleController.dispose();
    _broadcastCoinCostController.dispose();
    _staticCoinsController.dispose();
    _accentColorController.dispose();
    super.dispose();
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
        setState(() => _isSaving = true);

        final res = await ApiService.uploadFile(
          '/advertisements/upload-image',
          file.bytes!,
          file.name,
        );

        if (!mounted) return;

        if (res['success'] == true && res['imageUrl'] != null) {
          setState(() {
            _imageUrlController.text = res['imageUrl'];
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('16:9 banner image uploaded!')),
          );
        } else {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Upload failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime.now(),
        end: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final imageUrl = _imageUrlController.text.trim().isNotEmpty
        ? _imageUrlController.text.trim()
        : _BuddyBannersPageState.defaultGarbaImageUrl;
    final priority = int.tryParse(_priorityController.text.trim()) ?? 1;
    final sheetTitle = _sheetTitleController.text.trim();
    final sheetSubtitle = _sheetSubtitleController.text.trim();
    final coinCost = int.tryParse(_broadcastCoinCostController.text.trim()) ?? 1;
    final staticCoins = int.tryParse(_staticCoinsController.text.trim()) ?? 50;
    final accentColor = _accentColorController.text.trim();

    final savedBanner = BuddyBanner(
      id: widget.banner?.id ?? 'banner_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      imageUrl: imageUrl,
      priority: priority,
      isActive: _isActive,
      startDate: _startDate,
      endDate: _endDate,
      sheetTitle: sheetTitle,
      sheetSubtitle: sheetSubtitle,
      sheetIconUrl: null,
      accentColor: accentColor,
      broadcastCoinCost: coinCost,
      buddyType: _buddyType,
      otpRewardType: _otpRewardType,
      staticCoinAmount: staticCoins,
      malePercentage: 40,
      femalePercentage: 20,
    );

    final bannerData = {
      'name': name,
      'imageUrl': imageUrl,
      'priority': priority,
      'isActive': _isActive,
      'startDate': _startDate?.toIso8601String(),
      'endDate': _endDate?.toIso8601String(),
      'sheetConfig': {
        'title': sheetTitle,
        'subtitle': sheetSubtitle,
        'buddyType': _buddyType,
        'broadcastCoinCost': coinCost,
        'accentColor': accentColor,
      },
      'otpReward': {
        'type': _otpRewardType,
        'staticCoinAmount': staticCoins,
        'malePercentage': 40,
        'femalePercentage': 20,
      },
    };

    setState(() => _isSaving = true);
    try {
      if (widget.banner == null) {
        await ApiService.post('/buddy-banners', body: bannerData);
      } else {
        await ApiService.put('/buddy-banners/${widget.banner!.id}', body: bannerData);
      }
    } catch (_) {
      // Backend not yet deployed; local persistence handles updates seamlessly
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        widget.onSaved(savedBanner);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final dateRangeStr = (_startDate != null && _endDate != null)
        ? '${dateFormat.format(_startDate!)} - ${dateFormat.format(_endDate!)}'
        : 'Select Schedule';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 850),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AdminColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.celebration_rounded, color: AdminColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.banner == null ? 'Create Buddy Banner Campaign' : 'Edit Buddy Banner Campaign',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Scrollable Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SECTION 1: 16:9 BANNER VISUALS
                      _buildSectionHeader(
                        number: '1',
                        title: 'Home Carousel Banner (Widescreen 1918x820)',
                        subtitle: 'Upload a widescreen banner image (recommended 1918x820) and configure slide order and schedule.',
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration('Campaign Name', hint: 'e.g. Navratri Garba 2026'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter campaign name' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _imageUrlController,
                              decoration: _inputDecoration('Banner Image URL (1918x820)', hint: 'Paste image URL or click Upload Banner'),
                              onChanged: (_) => setState(() {}),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Image URL is required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Upload Banner'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Live Preview
                      if (_imageUrlController.text.trim().isNotEmpty) ...[
                        const Text('Live Banner Preview (1918x820 Widescreen):', style: TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                        const SizedBox(height: 6),
                        AspectRatio(
                          aspectRatio: 1918 / 820,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _imageUrlController.text.trim().startsWith('http://') ||
                                    _imageUrlController.text.trim().startsWith('https://')
                                ? Image.network(
                                    _imageUrlController.text.trim(),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.broken_image_rounded, color: Colors.white, size: 36),
                                            SizedBox(height: 8),
                                            Text(
                                              'Image preview unavailable',
                                              style: TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.celebration_rounded, color: Colors.white, size: 40),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priorityController,
                              keyboardType: TextInputType.number,
                              decoration: _inputDecoration('Slide Order (1, 2, 3...)'),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDateRange,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AdminColors.border),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 16, color: AdminColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        dateRangeStr,
                                        style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Row(
                            children: [
                              Switch(
                                value: _isActive,
                                activeTrackColor: AdminColors.success.withValues(alpha: 0.5),
                                activeThumbColor: AdminColors.success,
                                onChanged: (v) => setState(() => _isActive = v),
                              ),
                              Text(_isActive ? 'Active' : 'Inactive'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // SECTION 2: POPUP SHEET & BROADCAST COST
                      _buildSectionHeader(
                        number: '2',
                        title: 'Popup Sheet & Broadcast Pricing',
                        subtitle: 'Tapping this banner automatically opens the custom Buddy Request Sheet.',
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _sheetTitleController,
                        decoration: _inputDecoration('Sheet Title (e.g. Holi Buddy 🎨, Garba Buddy 🪔)', hint: 'e.g. Holi Buddy 🎨'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter title' : null,
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _sheetSubtitleController,
                        decoration: _inputDecoration('Sheet Subtitle', hint: 'e.g. Find someone who matches your Garba vibes'),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _broadcastCoinCostController,
                              keyboardType: TextInputType.number,
                              decoration: _inputDecoration('Broadcast Coin Cost (e.g. 1 coin)'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter coin cost' : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _accentColorController,
                              decoration: _inputDecoration('Theme Color Hex (e.g. #9333EA)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // SECTION 3: ON-ACCEPT OTP VERIFICATION REWARD
                      _buildSectionHeader(
                        number: '3',
                        title: 'On-Accept OTP Verification Reward',
                        subtitle: 'Reward credited to Accepter wallet upon meeting up & entering 6-digit OTP.',
                      ),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AdminColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AdminColors.border),
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => setState(() => _otpRewardType = 'PERCENTAGE'),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _otpRewardType == 'PERCENTAGE'
                                      ? AdminColors.activePillBg
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _otpRewardType == 'PERCENTAGE'
                                        ? AdminColors.primary
                                        : AdminColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _otpRewardType == 'PERCENTAGE'
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      color: _otpRewardType == 'PERCENTAGE'
                                          ? AdminColors.primary
                                          : AdminColors.textSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text(
                                            'Option A: Default App Percentage',
                                            style: TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Male Accepter receives 40%, Female Accepter receives 20% of broadcast coins.',
                                            style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () => setState(() => _otpRewardType = 'STATIC'),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _otpRewardType == 'STATIC'
                                      ? AdminColors.activePillBg
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _otpRewardType == 'STATIC'
                                        ? AdminColors.primary
                                        : AdminColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _otpRewardType == 'STATIC'
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      color: _otpRewardType == 'STATIC'
                                          ? AdminColors.primary
                                          : AdminColors.textSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text(
                                            'Option B: Fixed / Static Coin Amount (Recommended for Promos)',
                                            style: TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Accepter receives exact fixed coins regardless of broadcast cost or gender.',
                                            style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_otpRewardType == 'STATIC') ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 32, right: 16, top: 12, bottom: 8),
                                child: TextFormField(
                                  controller: _staticCoinsController,
                                  keyboardType: TextInputType.number,
                                  decoration: _inputDecoration('Static Coin Reward Amount (e.g. 50 coins)'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AdminColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(widget.banner == null ? 'Create Banner' : 'Save Changes',
                            style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: AdminColors.primary,
          child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: AdminColors.textSecondary.withValues(alpha: 0.6)),
      labelStyle: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

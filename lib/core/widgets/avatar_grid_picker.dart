import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/constants/avatar_catalog.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/cloudinary_upload_service.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';

/// AvatarGridPicker renders a 4-column avatar selection grid where:
/// - Index 0 is reserved for "Upload Photo" (integrates with Cloudinary)
/// - Indices 1..15 render predefined avatars from AvatarCatalog
class AvatarGridPicker extends ConsumerStatefulWidget {
  final String? selectedGender;
  final String? selectedAvatarSeed;
  final ValueChanged<String> onAvatarSelected;
  final double radius;
  final int crossAxisCount;
  final double spacing;

  const AvatarGridPicker({
    super.key,
    required this.selectedGender,
    required this.selectedAvatarSeed,
    required this.onAvatarSelected,
    this.radius = 26,
    this.crossAxisCount = 4,
    this.spacing = 10,
  });

  @override
  ConsumerState<AvatarGridPicker> createState() => _AvatarGridPickerState();
}

class _AvatarGridPickerState extends ConsumerState<AvatarGridPicker> {
  bool _isUploading = false;
  String? _uploadedPhotoUrl;

  @override
  void initState() {
    super.initState();
    _checkInitialUploadedUrl();
  }

  @override
  void didUpdateWidget(covariant AvatarGridPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkInitialUploadedUrl();
  }

  void _checkInitialUploadedUrl() {
    final seed = widget.selectedAvatarSeed;
    if (seed != null && (seed.startsWith('http://') || seed.startsWith('https://'))) {
      if (_uploadedPhotoUrl != seed) {
        _uploadedPhotoUrl = seed;
      }
    }
  }

  Future<void> _handleUploadTap() async {
    // If an image is already uploaded and currently selected, tapping it opens gallery to re-upload.
    // If an image is already uploaded but not currently selected, tapping it selects the uploaded image.
    final isUploadedSelected = widget.selectedAvatarSeed != null &&
        widget.selectedAvatarSeed == _uploadedPhotoUrl &&
        _uploadedPhotoUrl!.isNotEmpty;

    if (_uploadedPhotoUrl != null && _uploadedPhotoUrl!.isNotEmpty && !isUploadedSelected) {
      widget.onAvatarSelected(_uploadedPhotoUrl!);
      return;
    }

    // Trigger Image Picker & Cloudinary Upload
    if (_isUploading) return;

    setState(() => _isUploading = true);

    final uploadedUrl = await CloudinaryUploadService.pickAndUploadAvatar(
      context: context,
      ref: ref,
    );

    if (mounted) {
      setState(() => _isUploading = false);
    }

    if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
      setState(() {
        _uploadedPhotoUrl = uploadedUrl;
      });
      widget.onAvatarSelected(uploadedUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final predefinedSeeds = AvatarCatalog.getSeedsForGender(widget.selectedGender);
    final totalCount = predefinedSeeds.length + 1; // Index 0 + 15 predefined avatars

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        crossAxisSpacing: widget.spacing,
        mainAxisSpacing: widget.spacing,
        childAspectRatio: 1.0,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // Index 0: Upload Photo Option
        if (index == 0) {
          return _buildUploadPhotoTile(colors, typography);
        }

        // Indices 1..15: Predefined Avatars
        final seed = predefinedSeeds[index - 1];
        final isSelected = seed == widget.selectedAvatarSeed;

        return AppAvatar(
          avatarSeed: seed,
          gender: widget.selectedGender,
          radius: widget.radius,
          isSelected: isSelected,
          onTap: () => widget.onAvatarSelected(seed),
        );
      },
    );
  }

  Widget _buildUploadPhotoTile(dynamic colors, dynamic typography) {
    final hasUploaded = _uploadedPhotoUrl != null && _uploadedPhotoUrl!.trim().isNotEmpty;
    final isSelected = hasUploaded && (widget.selectedAvatarSeed == _uploadedPhotoUrl);
    final double size = widget.radius * 2;
    final activeBorderColor = colors.primary;

    if (_isUploading) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary.withValues(alpha: 0.08),
          border: Border.all(color: colors.primary, width: 2),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: colors.primary,
          ),
        ),
      );
    }

    if (hasUploaded) {
      return GestureDetector(
        onTap: _handleUploadTap,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AppAvatar(
              avatarSeed: _uploadedPhotoUrl,
              radius: widget.radius,
              isSelected: isSelected,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default "Upload Photo" circular item
    return GestureDetector(
      onTap: _handleUploadTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary.withValues(alpha: 0.08),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 20,
              color: colors.primary,
            ),
            const SizedBox(height: 2),
            Text(
              'Upload',
              style: TextStyle(
                color: colors.primary,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

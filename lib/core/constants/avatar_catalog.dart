/// AvatarCatalog defines the curated set of bundled DiceBear SVG avatars
/// for male and female user profiles on LoopCall.
class AvatarCatalog {
  AvatarCatalog._();

  static const String defaultStyle = 'avataaars';

  static const List<String> maleSeeds = [
    'male_1_new',
    'male_2_new',
    'male_3_new',
    'male_4_new',
    'male_5_new',
    'male_6_new',
    'male_7_new',
    'male_8_new',
    'male_9_new',
    'male_10_new',
    'male_1',
    'male_2',
    'male_3',
    'male_4',
    'male_5',
    'male_6',
    'male_7',
    'male_8',
    'male_9',
    'male_10',
    'male_11',
    'male_12',
    'male_13',
    'male_14',
    'male_15',
    'male_16',
    'male_17',
    'male_18',
    'male_19',
    'male_20',
  ];

  static const List<String> femaleSeeds = [
    'female_1_new',
    'female_2_new',
    'female_3_new',
    'female_4_new',
    'female_5_new',
    'female_6_new',
    'female_7_new',
    'female_8_new',
    'female_9_new',
    'female_10_new',
    'female_1',
    'female_2',
    'female_3',
    'female_4',
    'female_5',
    'female_6',
    'female_7',
    'female_8',
    'female_9',
    'female_10',
    'female_11',
    'female_12',
    'female_13',
    'female_14',
    'female_15',
    'female_16',
    'female_17',
    'female_18',
    'female_19',
    'female_20',
  ];

  /// Get list of curated avatar seeds for the specified gender.
  static List<String> getSeedsForGender(String? gender) {
    final g = (gender ?? '').trim().toLowerCase();
    if (g == 'female' || g == 'girl' || g == 'woman' || g == 'f') {
      return femaleSeeds;
    }
    return maleSeeds;
  }

  /// Maps an avatar seed to its corresponding local SVG asset path.
  static String? getAssetPath(String? seed, {String? gender}) {
    if (seed == null || seed.trim().isEmpty) {
      return null;
    }

    final cleanSeed = seed.trim().toLowerCase();
    final folder = (gender ?? '').toLowerCase().contains('female') ? 'female' : 'male';

    // Strip leading 'avatar_' or 'assets/avatars/...' if present
    String s = cleanSeed;
    if (s.contains('/')) {
      s = s.split('/').last;
    }
    if (s.startsWith('avatar_')) {
      s = s.replaceFirst('avatar_', '');
    }
    if (s.endsWith('.svg')) {
      s = s.replaceAll('.svg', '');
    }

    // Direct seed matching male_* or female_*
    if (s.startsWith('male_')) {
      return 'assets/avatars/male/avatar_$s.svg';
    } else if (s.startsWith('female_')) {
      return 'assets/avatars/female/avatar_$s.svg';
    }

    // Numeric seeds e.g. "1_new", "5", etc.
    if (s.endsWith('_new')) {
      final numStr = s.replaceAll('_new', '');
      final numVal = int.tryParse(numStr) ?? 1;
      final safeNum = ((numVal - 1) % 10) + 1;
      return 'assets/avatars/$folder/avatar_${folder}_${safeNum}_new.svg';
    } else {
      final numVal = int.tryParse(s) ?? ((cleanSeed.hashCode.abs() % 20) + 1);
      final safeNum = ((numVal - 1) % 20) + 1;
      return 'assets/avatars/$folder/avatar_${folder}_$safeNum.svg';
    }
  }
}

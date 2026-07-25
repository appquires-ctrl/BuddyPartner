/// AvatarCatalog defines the curated set of bundled DiceBear SVG avatars
/// for male and female user profiles on LoopCall.
class AvatarCatalog {
  AvatarCatalog._();

  static const String defaultStyle = 'avataaars';

  static const List<String> maleSeeds = [
    'female_10q',
    'female_15w',
    'female_18q',
    'female_4_newq',
    'female_7_newa',
    'female_8_newq',
    'female_8q',
    'male_14q',
    'male_2f',
    'male_3j',
    'male_4q',
    'male_7q',
  ];

  static const List<String> femaleSeeds = [
    'female_1',
    'female_11',
    'female_12',
    'female_15',
    'female_1_new',
    'female_20',
    'female_3',
    'female_3_new',
    'female_7',
    'female_7_new',
    'female_9',
    'female_9_new',
    'male_12',
    'male_20',
    'male_8_new',
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

    final cleanSeed = seed.trim();
    final folder = (gender ?? '').toLowerCase().contains('female') ? 'female' : 'male';

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

    return 'assets/avatars/$folder/avatar_$s.svg';
  }
}

/// AvatarCatalog defines the curated set of bundled DiceBear SVG avatars
/// for male and female user profiles on BuddyPartner.
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

  /// Aliases mapping legacy seeds or un-suffixed seeds to guaranteed existing assets
  static const Map<String, String> seedAliases = {
    'male_2': 'male_2f',
    'male_3': 'male_3j',
    'male_4': 'male_4q',
    'male_7': 'male_7q',
    'male_14': 'male_14q',
    'male_1': 'male_2f',
    'male_1_new': 'male_2f',
    'female_10': 'female_10q',
    'female_15_male': 'female_15w',
    'female_18': 'female_18q',
    'female_4_new': 'female_4_newq',
    'female_7_newa': 'female_7_newa',
    'female_8_new': 'female_8_newq',
    'female_8': 'female_8q',
    'Felix': 'male_2f',
    'Alexander': 'male_2f',
    'Benjamin': 'male_3j',
    'Daniel': 'male_4q',
    'Ethan': 'male_7q',
    'Amelia': 'female_1',
    'Bella': 'female_3',
    'Charlotte': 'female_7',
    'Diana': 'female_9',
    'Emma': 'female_11',
    'Fiona': 'female_12',
    'Grace': 'female_15',
    'Hannah': 'female_20',
  };

  /// Guaranteed default seeds for each gender
  static const String defaultMaleSeed = 'male_2f';
  static const String defaultFemaleSeed = 'female_1';

  /// Get the guaranteed default seed for the given gender
  static String getDefaultSeedForGender(String? gender) {
    final g = (gender ?? '').trim().toLowerCase();
    if (g == 'female' || g == 'girl' || g == 'woman' || g == 'f') {
      return defaultFemaleSeed;
    }
    return defaultMaleSeed;
  }

  /// Get list of curated avatar seeds for the specified gender.
  static List<String> getSeedsForGender(String? gender) {
    final g = (gender ?? '').trim().toLowerCase();
    if (g == 'female' || g == 'girl' || g == 'woman' || g == 'f') {
      return femaleSeeds;
    }
    return maleSeeds;
  }

  /// Maps an avatar seed to its corresponding local SVG asset path.
  /// If the seed is unknown or doesn't match an asset, safely falls back
  /// to a valid bundled avatar instead of returning a broken path.
  static String? getAssetPath(String? seed, {String? gender}) {
    if (seed == null || seed.trim().isEmpty) {
      return null;
    }

    final cleanSeed = seed.trim();

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

    // 1. Check exact alias map first
    if (seedAliases.containsKey(s)) {
      s = seedAliases[s]!;
    }

    final isFemale = (gender ?? '').toLowerCase().contains('female');

    // 2. Direct match in maleSeeds
    if (maleSeeds.contains(s)) {
      return 'assets/avatars/male/avatar_$s.svg';
    }

    // 3. Direct match in femaleSeeds
    if (femaleSeeds.contains(s)) {
      return 'assets/avatars/female/avatar_$s.svg';
    }

    // 4. Prefix match against existing male seeds
    for (final ms in maleSeeds) {
      if (ms.startsWith(s) || s.startsWith(ms)) {
        return 'assets/avatars/male/avatar_$ms.svg';
      }
    }

    // 5. Prefix match against existing female seeds
    for (final fs in femaleSeeds) {
      if (fs.startsWith(s) || s.startsWith(fs)) {
        return 'assets/avatars/female/avatar_$fs.svg';
      }
    }

    // 6. Safe deterministic fallback based on gender and seed hash code
    final targetPool = isFemale ? femaleSeeds : maleSeeds;
    final folder = isFemale ? 'female' : 'male';
    final safeIndex = s.hashCode.abs() % targetPool.length;
    final fallbackSeed = targetPool[safeIndex];
    return 'assets/avatars/$folder/avatar_$fallbackSeed.svg';
  }
}

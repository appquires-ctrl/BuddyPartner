class BuddyBanner {
  final String id;
  final String name;
  final String imageUrl;
  final int priority;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final String sheetTitle;
  final String sheetSubtitle;
  final String? sheetIconUrl;
  final String accentColor;
  final int broadcastCoinCost;
  final String buddyType;
  final String otpRewardType; // 'STATIC' or 'PERCENTAGE'
  final int staticCoinAmount;
  final int malePercentage;
  final int femalePercentage;
  final String? createdAt;

  BuddyBanner({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.priority,
    this.startDate,
    this.endDate,
    required this.isActive,
    required this.sheetTitle,
    required this.sheetSubtitle,
    this.sheetIconUrl,
    this.accentColor = '#9333EA',
    this.broadcastCoinCost = 1,
    this.buddyType = 'garba',
    this.otpRewardType = 'STATIC',
    this.staticCoinAmount = 50,
    this.malePercentage = 40,
    this.femalePercentage = 20,
    this.createdAt,
  });

  factory BuddyBanner.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        return DateTime.tryParse(d);
      }
      return null;
    }

    final sheet = json['sheetConfig'] as Map<String, dynamic>? ??
        json['sheet_config'] as Map<String, dynamic>? ??
        {};

    final otp = json['otpReward'] as Map<String, dynamic>? ??
        json['otp_reward'] as Map<String, dynamic>? ??
        {};

    return BuddyBanner(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['title']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? json['image_url']?.toString() ?? '',
      priority: (json['priority'] is int)
          ? json['priority']
          : int.tryParse(json['priority']?.toString() ?? '1') ?? 1,
      startDate: parseDate(json['startDate'] ?? json['start_date']),
      endDate: parseDate(json['endDate'] ?? json['end_date']),
      isActive: json['isActive'] == true || json['is_active'] == true,
      sheetTitle: sheet['title']?.toString() ?? json['sheetTitle']?.toString() ?? 'Garba Buddy 🪔',
      sheetSubtitle: sheet['subtitle']?.toString() ?? json['sheetSubtitle']?.toString() ?? 'Find someone who matches your Garba vibes',
      sheetIconUrl: sheet['iconUrl']?.toString() ?? sheet['icon_url']?.toString() ?? json['sheetIconUrl']?.toString(),
      accentColor: sheet['accentColor']?.toString() ?? sheet['accent_color']?.toString() ?? '#9333EA',
      broadcastCoinCost: (sheet['broadcastCoinCost'] as num? ??
              sheet['broadcast_coin_cost'] as num? ??
              sheet['coinCost'] as num? ??
              json['broadcastCoinCost'] as num? ??
              1)
          .toInt(),
      buddyType: sheet['buddyType']?.toString() ?? sheet['type']?.toString() ?? json['buddyType']?.toString() ?? 'garba',
      otpRewardType: otp['type']?.toString().toUpperCase() == 'PERCENTAGE' ? 'PERCENTAGE' : 'STATIC',
      staticCoinAmount: (otp['staticCoinAmount'] as num? ?? otp['static_coin_amount'] as num? ?? 50).toInt(),
      malePercentage: (otp['malePercentage'] as num? ?? otp['male_percentage'] as num? ?? 40).toInt(),
      femalePercentage: (otp['femalePercentage'] as num? ?? otp['female_percentage'] as num? ?? 20).toInt(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'priority': priority,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        'isActive': isActive,
        'sheetConfig': {
          'title': sheetTitle,
          'subtitle': sheetSubtitle,
          if (sheetIconUrl != null) 'iconUrl': sheetIconUrl,
          'accentColor': accentColor,
          'broadcastCoinCost': broadcastCoinCost,
          'buddyType': buddyType,
        },
        'otpReward': {
          'type': otpRewardType,
          'staticCoinAmount': staticCoinAmount,
          'malePercentage': malePercentage,
          'femalePercentage': femalePercentage,
        },
      };
}

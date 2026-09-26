class PromoCode {
  final int id;
  final String code;
  final String title;
  final String? description;
  final String rewardType;
  final String? targetProductId;
  final String? googlePlayOfferId;
  final double discountAmount;
  final int coinsReward;
  final int vipDaysReward;
  final int? maxUsesTotal;
  final int maxUsesPerUser;
  final int timesRedeemed;
  final DateTime startsAt;
  final DateTime expiresAt;
  final bool isActive;
  final DateTime createdAt;

  PromoCode({
    required this.id,
    required this.code,
    required this.title,
    this.description,
    required this.rewardType,
    this.targetProductId,
    this.googlePlayOfferId,
    this.discountAmount = 0.0,
    this.coinsReward = 0,
    this.vipDaysReward = 0,
    this.maxUsesTotal,
    this.maxUsesPerUser = 1,
    this.timesRedeemed = 0,
    required this.startsAt,
    required this.expiresAt,
    this.isActive = true,
    required this.createdAt,
  });

  factory PromoCode.fromJson(Map<String, dynamic> json) {
    return PromoCode(
      id: json['id'] as int? ?? 0,
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      rewardType: json['reward_type'] as String? ?? 'GOOGLE_PLAY_OFFER',
      targetProductId: json['target_product_id'] as String?,
      googlePlayOfferId: json['google_play_offer_id'] as String?,
      discountAmount: (json['discount_amount'] != null)
          ? double.tryParse(json['discount_amount'].toString()) ?? 0.0
          : 0.0,
      coinsReward: json['coins_reward'] as int? ?? 0,
      vipDaysReward: json['vip_days_reward'] as int? ?? 0,
      maxUsesTotal: json['max_uses_total'] as int?,
      maxUsesPerUser: json['max_uses_per_user'] as int? ?? 1,
      timesRedeemed: json['times_redeemed'] as int? ?? 0,
      startsAt: json['starts_at'] != null
          ? DateTime.tryParse(json['starts_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString()) ??
              DateTime.now().add(const Duration(days: 30))
          : DateTime.now().add(const Duration(days: 30)),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'title': title,
      'description': description,
      'rewardType': rewardType,
      'targetProductId': targetProductId,
      'googlePlayOfferId': googlePlayOfferId,
      'discountAmount': discountAmount,
      'coinsReward': coinsReward,
      'vipDaysReward': vipDaysReward,
      'maxUsesTotal': maxUsesTotal,
      'maxUsesPerUser': maxUsesPerUser,
      'timesRedeemed': timesRedeemed,
      'startsAt': startsAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'isActive': isActive,
    };
  }
}

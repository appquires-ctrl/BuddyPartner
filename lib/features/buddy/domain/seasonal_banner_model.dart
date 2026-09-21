import 'package:flutter/material.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

enum OtpRewardType {
  percentage,
  staticReward;

  static OtpRewardType fromString(String? val) {
    if (val?.toUpperCase() == 'STATIC' || val?.toUpperCase() == 'STATIC_REWARD') {
      return OtpRewardType.staticReward;
    }
    return OtpRewardType.percentage;
  }
}

class OtpRewardConfig {
  final OtpRewardType type;
  final int staticCoinAmount;
  final double malePercentage;
  final double femalePercentage;

  const OtpRewardConfig({
    this.type = OtpRewardType.staticReward,
    this.staticCoinAmount = 50,
    this.malePercentage = 0.40,
    this.femalePercentage = 0.20,
  });

  factory OtpRewardConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OtpRewardConfig();
    return OtpRewardConfig(
      type: OtpRewardType.fromString(json['type'] as String?),
      staticCoinAmount: (json['staticCoinAmount'] as num? ?? json['static_coin_amount'] as num?)?.toInt() ?? 50,
      malePercentage: () {
        final val = (json['malePercentage'] as num? ?? json['male_percentage'] as num?)?.toDouble() ?? 40.0;
        return val > 1.0 ? val / 100.0 : val;
      }(),
      femalePercentage: () {
        final val = (json['femalePercentage'] as num? ?? json['female_percentage'] as num?)?.toDouble() ?? 20.0;
        return val > 1.0 ? val / 100.0 : val;
      }(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type == OtpRewardType.staticReward ? 'STATIC' : 'PERCENTAGE',
    'staticCoinAmount': staticCoinAmount,
    'malePercentage': (malePercentage * 100).round(),
    'femalePercentage': (femalePercentage * 100).round(),
  };
}

class SeasonalSheetConfig {
  final String title;
  final String subtitle;
  final String? iconUrl;
  final Color accentColor;
  final int broadcastCoinCost;
  final BuddyType buddyType;

  const SeasonalSheetConfig({
    required this.title,
    required this.subtitle,
    this.iconUrl,
    this.accentColor = const Color(0xFF9333EA),
    this.broadcastCoinCost = 1,
    this.buddyType = BuddyType.garba,
  });

  factory SeasonalSheetConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SeasonalSheetConfig(
        title: 'Garba Buddy 🪔',
        subtitle: 'Find someone who matches your Garba vibes',
        broadcastCoinCost: 1,
        buddyType: BuddyType.garba,
        accentColor: Color(0xFF9333EA),
      );
    }

    Color parseColor(dynamic hex) {
      if (hex is String && hex.isNotEmpty) {
        final clean = hex.replaceAll('#', '');
        if (clean.length == 6) {
          return Color(int.parse('0xFF$clean'));
        } else if (clean.length == 8) {
          return Color(int.parse('0x$clean'));
        }
      }
      return const Color(0xFF9333EA);
    }

    final typeStr = json['buddyType'] as String? ?? json['type'] as String? ?? 'garba';
    final parsedType = BuddyType.fromString(typeStr);

    return SeasonalSheetConfig(
      title: json['title'] as String? ?? 'Garba Buddy 🪔',
      subtitle: json['subtitle'] as String? ?? 'Find someone who matches your Garba vibes',
      iconUrl: json['iconUrl'] as String? ?? json['icon_url'] as String?,
      accentColor: parseColor(json['accentColor'] ?? json['accent_color']),
      broadcastCoinCost: (json['broadcastCoinCost'] as num? ?? json['broadcast_coin_cost'] as num? ?? json['coinCost'] as num?)?.toInt() ?? 1,
      buddyType: parsedType,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    if (iconUrl != null) 'iconUrl': iconUrl,
    'accentColor': '#${accentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    'broadcastCoinCost': broadcastCoinCost,
    'buddyType': buddyType.id,
  };
}

class SeasonalBannerModel {
  final String id;
  final String name;
  final String imageUrl;
  final int priority;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final SeasonalSheetConfig sheetConfig;
  final OtpRewardConfig otpReward;

  const SeasonalBannerModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.priority = 1,
    this.startDate,
    this.endDate,
    this.isActive = true,
    required this.sheetConfig,
    this.otpReward = const OtpRewardConfig(),
  });

  factory SeasonalBannerModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        return DateTime.tryParse(d);
      }
      return null;
    }

    return SeasonalBannerModel(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['title'] as String? ?? 'Seasonal Promo',
      imageUrl: json['imageUrl'] as String? ?? json['image_url'] as String? ?? '',
      priority: (json['priority'] as num?)?.toInt() ?? 1,
      startDate: parseDate(json['startDate'] ?? json['start_date']),
      endDate: parseDate(json['endDate'] ?? json['end_date']),
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
      sheetConfig: SeasonalSheetConfig.fromJson(
        json['sheetConfig'] as Map<String, dynamic>? ?? json['sheet_config'] as Map<String, dynamic>?,
      ),
      otpReward: OtpRewardConfig.fromJson(
        json['otpReward'] as Map<String, dynamic>? ?? json['otp_reward'] as Map<String, dynamic>?,
      ),
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
    'sheetConfig': sheetConfig.toJson(),
    'otpReward': otpReward.toJson(),
  };
}

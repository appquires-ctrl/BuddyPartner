import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/domain/seasonal_banner_model.dart';

void main() {
  group('Buddy Activity Feature Tests', () {
    test('All 12 BuddyTypes have valid assets, titles, IDs, and coin costs', () {
      expect(BuddyType.values.length, 12);

      final expectedIds = [
        'movie',
        'pizza',
        'coffee',
        'hangout',
        'trip',
        'cricket',
        'shopping',
        'night_out',
        'clubbing',
        'long_drive',
        'garba',
        'festival',
      ];

      for (final type in BuddyType.values) {
        expect(expectedIds.contains(type.id), isTrue, reason: 'Unknown ID: ${type.id}');
        expect(type.title.isNotEmpty, isTrue);
        expect(type.subtitle.isNotEmpty, isTrue);
        expect(type.stickerAsset.isNotEmpty, isTrue);
        expect(type.gradientColors.length, 2);
        expect(type.coinCost >= 1, isTrue);
      }

      // Assert exact pricing
      expect(BuddyType.movie.coinCost, 1999);
      expect(BuddyType.pizza.coinCost, 499);
      expect(BuddyType.coffee.coinCost, 499);
      expect(BuddyType.hangout.coinCost, 999);
      expect(BuddyType.trip.coinCost, 999);
      expect(BuddyType.cricket.coinCost, 199);
      expect(BuddyType.shopping.coinCost, 799);
      expect(BuddyType.nightOut.coinCost, 2499);
      expect(BuddyType.clubbing.coinCost, 1499);
      expect(BuddyType.longDrive.coinCost, 999);
      expect(BuddyType.garba.coinCost, 1);
      expect(BuddyType.festival.coinCost, 1);
    });

    test('BuddyType.fromString handles valid and fallback values', () {
      expect(BuddyType.fromString('pizza'), BuddyType.pizza);
      expect(BuddyType.fromString('coffee'), BuddyType.coffee);
      expect(BuddyType.fromString('cricket'), BuddyType.cricket);
      expect(BuddyType.fromString('night_out'), BuddyType.nightOut);
      expect(BuddyType.fromString('unknown_type'), BuddyType.movie); // default fallback
      expect(BuddyType.fromString(null), BuddyType.movie);
    });

    test('BuddyTargetGender and Status parsing and fallbacks', () {
      expect(BuddyTargetGender.fromString('male'), BuddyTargetGender.male);
      expect(BuddyTargetGender.fromString('female'), BuddyTargetGender.female);
      expect(BuddyTargetGender.fromString('all'), BuddyTargetGender.all);
      expect(BuddyTargetGender.fromString('invalid'), BuddyTargetGender.all);

      expect(BuddyRequestStatus.fromString('open'), BuddyRequestStatus.open);
      expect(BuddyRequestStatus.fromString('accepted'), BuddyRequestStatus.accepted);
      expect(BuddyRequestStatus.fromString('otp_verified'), BuddyRequestStatus.otpVerified);
      expect(BuddyRequestStatus.fromString(null), BuddyRequestStatus.open);
    });

    test('BuddyRequest fromJson and toJson parsing', () {
      final json = {
        'id': 'buddy_req_101',
        'initiator_id': 'user_initiator_1',
        'buddy_type': 'pizza',
        'city': 'Mumbai',
        'target_gender': 'all',
        'status': 'accepted',
        'accepter_id': 'user_accepter_2',
        'otp_code': '482910',
        'otp_attempts': 1,
        'initiator_coin_cost': 100,
        'accepter_coin_reward': 50,
        'created_at': '2026-09-14T10:00:00.000Z',
        'accepted_at': '2026-09-14T10:05:00.000Z',
        'conversation_id': 'conv_12345',
        'initiator': {
          'id': 'user_initiator_1',
          'full_name': 'Rohan Sharma',
          'gender': 'Male',
        },
        'accepter': {
          'id': 'user_accepter_2',
          'full_name': 'Priya Patel',
          'gender': 'Female',
        },
      };

      final req = BuddyRequest.fromJson(json, currentUserId: 'user_initiator_1');

      expect(req.id, 'buddy_req_101');
      expect(req.initiatorId, 'user_initiator_1');
      expect(req.isInitiator, isTrue);
      expect(req.buddyType, BuddyType.pizza);
      expect(req.city, 'Mumbai');
      expect(req.targetGender, BuddyTargetGender.all);
      expect(req.status, BuddyRequestStatus.accepted);
      expect(req.accepterId, 'user_accepter_2');
      expect(req.otpCode, '482910');
      expect(req.otpAttempts, 1);
      expect(req.initiatorCoinCost, 100);
      expect(req.accepterCoinReward, 50);
      expect(req.conversationId, 'conv_12345');
      expect(req.initiator?.fullName, 'Rohan Sharma');
      expect(req.accepter?.fullName, 'Priya Patel');

      final serialized = req.toJson();
      expect(serialized['id'], 'buddy_req_101');
      expect(serialized['buddyType'], 'pizza');
      expect(serialized['initiatorCoinCost'], 100);
      expect(serialized['accepterCoinReward'], 50);
    });

    test('BuddyRequest copyWith modifies fields correctly', () {
      final req = BuddyRequest(
        id: 'req_1',
        initiatorId: 'user_1',
        buddyType: BuddyType.movie,
        city: 'Delhi',
        targetGender: BuddyTargetGender.female,
        status: BuddyRequestStatus.open,
        createdAt: DateTime(2026, 9, 14),
      );

      final accepted = req.copyWith(
        status: BuddyRequestStatus.accepted,
        otpCode: '123456',
        accepterId: 'user_2',
      );

      expect(accepted.id, 'req_1');
      expect(accepted.status, BuddyRequestStatus.accepted);
      expect(accepted.otpCode, '123456');
      expect(accepted.accepterId, 'user_2');
      expect(accepted.city, 'Delhi');
    });

    test('SeasonalBannerModel and OtpRewardConfig parse correctly from JSON', () {
      final json = {
        'id': 'banner_diwali_2026',
        'name': 'Diwali Buddy',
        'imageUrl': 'https://res.cloudinary.com/test/image.png',
        'priority': 2,
        'isActive': true,
        'sheetConfig': {
          'title': 'Diwali Spark 🪔',
          'subtitle': 'Celebrate Diwali with a buddy',
          'broadcastCoinCost': 5,
          'buddyType': 'garba',
          'accentColor': '#FF6D00',
        },
        'otpReward': {
          'type': 'STATIC',
          'staticCoinAmount': 50,
          'malePercentage': 40,
          'femalePercentage': 20,
        },
      };

      final banner = SeasonalBannerModel.fromJson(json);
      expect(banner.id, 'banner_diwali_2026');
      expect(banner.name, 'Diwali Buddy');
      expect(banner.sheetConfig.broadcastCoinCost, 5);
      expect(banner.sheetConfig.buddyType, BuddyType.garba);
      expect(banner.otpReward.type, OtpRewardType.staticReward);
      expect(banner.otpReward.staticCoinAmount, 50);

      // Percentage mode test
      final pctJson = {
        'id': 'banner_pct',
        'name': 'Percentage Promo',
        'imageUrl': 'https://test.com/pct.png',
        'priority': 1,
        'sheetConfig': {'title': 'Promo', 'broadcastCoinCost': 100},
        'otpReward': {
          'type': 'PERCENTAGE',
          'malePercentage': 40,
          'femalePercentage': 20,
        },
      };

      final pctBanner = SeasonalBannerModel.fromJson(pctJson);
      expect(pctBanner.otpReward.type, OtpRewardType.percentage);
      expect(pctBanner.otpReward.malePercentage, 0.40);
      expect(pctBanner.otpReward.femalePercentage, 0.20);
    });
  });
}


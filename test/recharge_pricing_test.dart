import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/core/services/google_play_purchase_service.dart';
import 'package:buddypartner/core/utils/digital_asset_pricing.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';

void main() {
  group('Recharge Pricing Tests (Option B: 18% GST)', () {
    test('DigitalAssetPricing utility calculates 18% GST correctly across all tiers', () {
      expect(DigitalAssetPricing.fromBase(49).gstRupees, equals(9));
      expect(DigitalAssetPricing.fromBase(49).totalPriceRupees, equals(58));

      expect(DigitalAssetPricing.fromBase(99).gstRupees, equals(18));
      expect(DigitalAssetPricing.fromBase(99).totalPriceRupees, equals(117));

      expect(DigitalAssetPricing.fromBase(199).gstRupees, equals(36));
      expect(DigitalAssetPricing.fromBase(199).totalPriceRupees, equals(235));

      expect(DigitalAssetPricing.fromBase(499).gstRupees, equals(90));
      expect(DigitalAssetPricing.fromBase(499).totalPriceRupees, equals(589));

      expect(DigitalAssetPricing.fromBase(999).gstRupees, equals(180));
      expect(DigitalAssetPricing.fromBase(999).totalPriceRupees, equals(1179));

      expect(DigitalAssetPricing.fromBase(2500).gstRupees, equals(450));
      expect(DigitalAssetPricing.fromBase(2500).totalPriceRupees, equals(2950));
    });

    test('rechargePlansProvider has all 6 updated pricing tiers with base and GST breakdown', () {
      final container = ProviderContainer();
      final plans = container.read(rechargePlansProvider);

      expect(plans.length, equals(6));

      // Tier 1: ₹49 base + ₹9 GST = ₹58 total -> 49 coins
      final plan49 = plans.firstWhere((p) => p.id == 'plan_49');
      expect(plan49.basePriceRupees, equals(49));
      expect(plan49.gstRupees, equals(9));
      expect(plan49.totalPriceRupees, equals(58));
      expect(plan49.price, equals(58.0));
      expect(plan49.coins, equals(49));
      expect(plan49.bonusCoins, equals(0));
      expect(plan49.totalCoins, equals(49));

      // Tier 2: ₹99 base + ₹18 GST = ₹117 total -> 99 coins
      final plan99 = plans.firstWhere((p) => p.id == 'plan_99');
      expect(plan99.basePriceRupees, equals(99));
      expect(plan99.gstRupees, equals(18));
      expect(plan99.totalPriceRupees, equals(117));
      expect(plan99.price, equals(117.0));
      expect(plan99.coins, equals(99));
      expect(plan99.bonusCoins, equals(0));
      expect(plan99.totalCoins, equals(99));
      expect(plan99.isPopular, isTrue);

      // Tier 3: ₹199 base + ₹36 GST = ₹235 total -> 199 coins
      final plan199 = plans.firstWhere((p) => p.id == 'plan_199');
      expect(plan199.basePriceRupees, equals(199));
      expect(plan199.gstRupees, equals(36));
      expect(plan199.totalPriceRupees, equals(235));
      expect(plan199.price, equals(235.0));
      expect(plan199.coins, equals(199));
      expect(plan199.bonusCoins, equals(0));
      expect(plan199.totalCoins, equals(199));

      // Tier 4: ₹499 base + ₹90 GST = ₹589 total -> 549 coins (499 + 50 bonus)
      final plan499 = plans.firstWhere((p) => p.id == 'plan_499');
      expect(plan499.basePriceRupees, equals(499));
      expect(plan499.gstRupees, equals(90));
      expect(plan499.totalPriceRupees, equals(589));
      expect(plan499.price, equals(589.0));
      expect(plan499.coins, equals(499));
      expect(plan499.bonusCoins, equals(50));
      expect(plan499.totalCoins, equals(549));

      // Tier 5: ₹999 base + ₹180 GST = ₹1179 total -> 1099 coins (999 + 100 bonus)
      final plan999 = plans.firstWhere((p) => p.id == 'plan_999');
      expect(plan999.basePriceRupees, equals(999));
      expect(plan999.gstRupees, equals(180));
      expect(plan999.totalPriceRupees, equals(1179));
      expect(plan999.price, equals(1179.0));
      expect(plan999.coins, equals(999));
      expect(plan999.bonusCoins, equals(100));
      expect(plan999.totalCoins, equals(1099));

      // Tier 6: ₹2500 base + ₹450 GST = ₹2950 total -> 2750 coins (2500 + 250 bonus)
      final plan2500 = plans.firstWhere((p) => p.id == 'plan_2500');
      expect(plan2500.basePriceRupees, equals(2500));
      expect(plan2500.gstRupees, equals(450));
      expect(plan2500.totalPriceRupees, equals(2950));
      expect(plan2500.price, equals(2950.0));
      expect(plan2500.coins, equals(2500));
      expect(plan2500.bonusCoins, equals(250));
      expect(plan2500.totalCoins, equals(2750));
    });

    test('kGooglePlayCoinProductIds includes all new plan product IDs', () {
      expect(kGooglePlayCoinProductIds.contains('plan_49'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_99'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_199'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_499'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_999'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_2500'), isTrue);
    });

    test('findRecommendedRechargePlan selects optimal plan for Buddy Activities', () {
      final container = ProviderContainer();
      final plans = container.read(rechargePlansProvider);

      // Night Out: 2499 coins deficit -> plan_2500 (2750 coins)
      final nightOutPlan = findRecommendedRechargePlan(plans, 2499);
      expect(nightOutPlan.id, equals('plan_2500'));
      expect(nightOutPlan.totalCoins, equals(2750));
      expect(nightOutPlan.basePriceRupees, equals(2500));

      // Movie: 1999 coins deficit -> plan_2500 (2750 coins)
      final moviePlan = findRecommendedRechargePlan(plans, 1999);
      expect(moviePlan.id, equals('plan_2500'));
      expect(moviePlan.totalCoins, equals(2750));

      // Clubbing: 1499 coins deficit -> plan_2500 (2750 coins)
      final clubbingPlan = findRecommendedRechargePlan(plans, 1499);
      expect(clubbingPlan.id, equals('plan_2500'));

      // Pizza / Coffee: 499 coins deficit -> plan_499 (549 coins)
      final pizzaPlan = findRecommendedRechargePlan(plans, 499);
      expect(pizzaPlan.id, equals('plan_499'));
      expect(pizzaPlan.totalCoins, equals(549));

      // Hangout / Trip / Long Drive: 999 coins deficit -> plan_999 (1099 coins)
      final hangoutPlan = findRecommendedRechargePlan(plans, 999);
      expect(hangoutPlan.id, equals('plan_999'));
      expect(hangoutPlan.totalCoins, equals(1099));

      // Cricket: 199 coins deficit -> plan_199 (199 coins)
      final cricketPlan = findRecommendedRechargePlan(plans, 199);
      expect(cricketPlan.id, equals('plan_199'));
      expect(cricketPlan.totalCoins, equals(199));

      // Shopping: 799 coins deficit -> plan_999 (1099 coins)
      final shoppingPlan = findRecommendedRechargePlan(plans, 799);
      expect(shoppingPlan.id, equals('plan_999'));

      // Small promo (e.g. Garba 1 coin) -> plan_49 (49 coins)
      final garbaPlan = findRecommendedRechargePlan(plans, 1);
      expect(garbaPlan.id, equals('plan_49'));

      // Partial balance scenario: user has 1000 coins and needs Night Out (2499) -> deficit 1499 -> plan_2500
      final partialNightOut = findRecommendedRechargePlan(plans, 2499 - 1000);
      expect(partialNightOut.id, equals('plan_2500'));

      // Partial balance scenario: user has 600 coins and needs Hangout (999) -> deficit 399 -> plan_499
      final partialHangout = findRecommendedRechargePlan(plans, 999 - 600);
      expect(partialHangout.id, equals('plan_499'));
    });
  });
}

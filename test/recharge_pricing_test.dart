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
    });

    test('rechargePlansProvider has all 5 updated pricing tiers with base and GST breakdown', () {
      final container = ProviderContainer();
      final plans = container.read(rechargePlansProvider);

      expect(plans.length, equals(5));

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
    });

    test('kGooglePlayCoinProductIds includes all new plan product IDs', () {
      expect(kGooglePlayCoinProductIds.contains('plan_49'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_99'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_199'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_499'), isTrue);
      expect(kGooglePlayCoinProductIds.contains('plan_999'), isTrue);
    });
  });
}

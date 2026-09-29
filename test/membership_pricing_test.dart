import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/core/services/google_play_purchase_service.dart';
import 'package:buddypartner/core/utils/digital_asset_pricing.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';

void main() {
  group('Membership Pricing & Tier Tests (Option B)', () {
    test('SubscriptionPlan.defaultPlans has Option B base price, 18% GST, and total price', () {
      final plans = SubscriptionPlan.defaultPlans;

      expect(plans.length, equals(3));

      // Tier 1: 1 Month -> ₹199 base + ₹36 GST = ₹235 total
      final plan1 = plans.firstWhere((p) => p.id == '1_month');
      expect(plan1.basePriceRupees, equals(199));
      expect(plan1.gstRupees, equals(36));
      expect(plan1.totalPriceRupees, equals(235));
      expect(plan1.priceRupees, equals(235));
      expect(plan1.durationDays, equals(30));
      expect(plan1.title, equals('1 Month Membership'));
      expect(plan1.badge, equals('POPULAR'));

      // Tier 2: 6 Months -> ₹399 base + ₹72 GST = ₹471 total
      final plan2 = plans.firstWhere((p) => p.id == '6_months');
      expect(plan2.basePriceRupees, equals(399));
      expect(plan2.gstRupees, equals(72));
      expect(plan2.totalPriceRupees, equals(471));
      expect(plan2.priceRupees, equals(471));
      expect(plan2.durationDays, equals(180));
      expect(plan2.title, equals('6 Months Membership'));
      expect(plan2.badge, equals('BEST VALUE'));

      // Tier 3: 1 Year -> ₹699 base + ₹126 GST = ₹825 total
      final plan3 = plans.firstWhere((p) => p.id == '1_year');
      expect(plan3.basePriceRupees, equals(699));
      expect(plan3.gstRupees, equals(126));
      expect(plan3.totalPriceRupees, equals(825));
      expect(plan3.priceRupees, equals(825));
      expect(plan3.durationDays, equals(365));
      expect(plan3.title, equals('1 Year Membership'));
      expect(plan3.badge, equals('MAX SAVINGS'));

      // Verify 1-day (₹9) and 7-day (₹59) plans are completely removed
      expect(plans.any((p) => p.id == '1_day'), isFalse);
      expect(plans.any((p) => p.id == '7_days'), isFalse);
    });

    test('kGooglePlaySubscriptionProductIds includes all membership product IDs and aliases', () {
      expect(kGooglePlaySubscriptionProductIds.contains('membership_1_month'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('membership_6_months'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('membership_1_year'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('pass_1_month'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('pass_6_months'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('pass_1_year'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('1_month'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('6_months'), isTrue);
      expect(kGooglePlaySubscriptionProductIds.contains('1_year'), isTrue);
    });

    test('Subscription promo discount follows base-first discounting and 18% GST', () {
      // 1 Month: ₹199 base - ₹50 discount -> ₹149 taxable base + ₹27 GST = ₹176 total
      final pricing1m = DigitalAssetPricing.fromBaseWithDiscount(basePrice: 199, discount: 50);
      expect(pricing1m.basePriceRupees, equals(149));
      expect(pricing1m.gstRupees, equals(27));
      expect(pricing1m.totalPriceRupees, equals(176));

      // 6 Months: ₹399 base - ₹100 discount -> ₹299 taxable base + ₹54 GST = ₹353 total
      final pricing6m = DigitalAssetPricing.fromBaseWithDiscount(basePrice: 399, discount: 100);
      expect(pricing6m.basePriceRupees, equals(299));
      expect(pricing6m.gstRupees, equals(54));
      expect(pricing6m.totalPriceRupees, equals(353));

      // 1 Year: ₹699 base - ₹150 discount -> ₹549 taxable base + ₹99 GST = ₹648 total
      final pricing1y = DigitalAssetPricing.fromBaseWithDiscount(basePrice: 699, discount: 150);
      expect(pricing1y.basePriceRupees, equals(549));
      expect(pricing1y.gstRupees, equals(99));
      expect(pricing1y.totalPriceRupees, equals(648));
    });
  });
}

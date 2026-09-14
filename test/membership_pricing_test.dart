import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/core/services/google_play_purchase_service.dart';
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
  });
}

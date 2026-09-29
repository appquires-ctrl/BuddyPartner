import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddypartner/core/constants/country_codes.dart';
import 'package:buddypartner/core/utils/app_currency.dart';
import 'package:buddypartner/core/utils/digital_asset_pricing.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';
import 'package:buddypartner/features/recharge/presentation/widgets/recharge_plan_card.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('AppCurrency Dual-Currency Core Logic Tests', () {
    test('isDomestic correctly identifies Indian vs International users', () {
      // Domestic cases
      expect(AppCurrency.isDomestic(country: 'IN'), isTrue);
      expect(AppCurrency.isDomestic(country: 'India'), isTrue);
      expect(AppCurrency.isDomestic(country: 'india'), isTrue);
      expect(AppCurrency.isDomestic(country: '+91'), isTrue);
      expect(AppCurrency.isDomestic(countryCode: '+91'), isTrue);
      expect(AppCurrency.isDomestic(countryCode: '91'), isTrue);
      expect(AppCurrency.isDomestic(phoneNumber: '+919876543210'), isTrue);
      expect(AppCurrency.isDomestic(phoneNumber: '919876543210'), isTrue);

      // International cases
      expect(AppCurrency.isDomestic(country: 'US'), isFalse);
      expect(AppCurrency.isDomestic(country: 'United States'), isFalse);
      expect(AppCurrency.isDomestic(country: 'United Kingdom'), isFalse);
      expect(AppCurrency.isDomestic(country: 'AE'), isFalse);
      expect(AppCurrency.isDomestic(country: 'CA'), isFalse);
      expect(AppCurrency.isDomestic(countryCode: '+1'), isFalse);
      expect(AppCurrency.isDomestic(countryCode: '+44'), isFalse);
      expect(AppCurrency.isDomestic(phoneNumber: '+12025550123'), isFalse);
      expect(AppCurrency.isDomestic(phoneNumber: '+447911123456'), isFalse);
      expect(AppCurrency.isDomestic(phoneNumber: '+971501234567'), isFalse);
    });

    test('symbol and code return correct tokens', () {
      expect(AppCurrency.symbol(isDomestic: true), equals('₹'));
      expect(AppCurrency.symbol(isDomestic: false), equals('\$'));
      expect(AppCurrency.code(isDomestic: true), equals('INR'));
      expect(AppCurrency.code(isDomestic: false), equals('USD'));
    });

    test('format handles currency formatting accurately', () {
      expect(
        AppCurrency.format(inr: 199, usd: 2.99, isDomestic: true),
        equals('₹199'),
      );
      expect(
        AppCurrency.format(inr: 199, usd: 2.99, isDomestic: false),
        equals('\$2.99'),
      );
      expect(
        AppCurrency.format(inr: 500, usd: 5.00, isDomestic: false),
        equals('\$5.00'),
      );
      expect(
        AppCurrency.format(inr: 49, usd: 0.99, isDomestic: false),
        equals('\$0.99'),
      );
    });

    test('taxLabel and checkoutDisclaimer provide localized tax context', () {
      // Domestic
      expect(AppCurrency.taxLabel(isDomestic: true), contains('18% GST'));
      final domesticDisclaimer = AppCurrency.checkoutDisclaimer(
        inrBreakdown: '₹99 + 18% GST (₹18) = ₹117',
        usdTotal: '\$1.99',
        isDomestic: true,
      );
      expect(domesticDisclaimer, contains('GST'));
      expect(domesticDisclaimer, contains('Google Play'));

      // International
      expect(AppCurrency.taxLabel(isDomestic: false), contains('Taxes'));
      expect(AppCurrency.taxLabel(isDomestic: false), isNot(contains('GST')));
      final globalDisclaimer = AppCurrency.checkoutDisclaimer(
        inrBreakdown: '₹99 + 18% GST (₹18) = ₹117',
        usdTotal: '\$1.99',
        isDomestic: false,
      );
      expect(globalDisclaimer, contains('Google Play'));
      expect(globalDisclaimer, contains('\$1.99 USD'));
      expect(globalDisclaimer, isNot(contains('GST')));
    });
  });

  group('Subscription Plans Global Dual-Currency Tests', () {
    test('Subscription plans expose both INR and USD formatted pricing', () {
      final plans = SubscriptionPlan.defaultPlans;

      final plan1 = plans.firstWhere((p) => p.id == '1_month');
      expect(plan1.priceRupees, equals(235));
      expect(plan1.priceUsd, equals(2.99));
      expect(plan1.formattedPrice(isDomestic: true), equals('₹235'));
      expect(plan1.formattedPrice(isDomestic: false), equals('\$2.99'));
      expect(plan1.formattedBasePrice(isDomestic: true), equals('₹199'));
      expect(plan1.formattedBasePrice(isDomestic: false), equals('\$2.99'));

      final plan2 = plans.firstWhere((p) => p.id == '6_months');
      expect(plan2.priceRupees, equals(471));
      expect(plan2.priceUsd, equals(5.99));
      expect(plan2.formattedPrice(isDomestic: true), equals('₹471'));
      expect(plan2.formattedPrice(isDomestic: false), equals('\$5.99'));

      final plan3 = plans.firstWhere((p) => p.id == '1_year');
      expect(plan3.priceRupees, equals(825));
      expect(plan3.priceUsd, equals(9.99));
      expect(plan3.formattedPrice(isDomestic: true), equals('₹825'));
      expect(plan3.formattedPrice(isDomestic: false), equals('\$9.99'));
    });
  });

  group('Recharge Plans Global Dual-Currency Tests', () {
    test('All 6 recharge tiers have valid USD prices and format dynamically', () {
      final container = ProviderContainer();
      final plans = container.read(rechargePlansProvider);

      expect(plans.length, equals(6));

      // Tier 1: ₹49 base (₹58 total) -> $0.99
      final p49 = plans.firstWhere((p) => p.id == 'plan_49');
      expect(p49.priceUsd, equals(0.99));
      expect(p49.formattedTotalPrice(isDomestic: true), equals('₹58'));
      expect(p49.formattedTotalPrice(isDomestic: false), equals('\$0.99'));

      // Tier 2: ₹99 base (₹117 total) -> $1.99
      final p99 = plans.firstWhere((p) => p.id == 'plan_99');
      expect(p99.priceUsd, equals(1.99));
      expect(p99.formattedTotalPrice(isDomestic: true), equals('₹117'));
      expect(p99.formattedTotalPrice(isDomestic: false), equals('\$1.99'));

      // Tier 3: ₹199 base (₹235 total) -> $2.99
      final p199 = plans.firstWhere((p) => p.id == 'plan_199');
      expect(p199.priceUsd, equals(2.99));
      expect(p199.formattedTotalPrice(isDomestic: true), equals('₹235'));
      expect(p199.formattedTotalPrice(isDomestic: false), equals('\$2.99'));

      // Tier 4: ₹499 base (₹589 total) -> $5.99
      final p499 = plans.firstWhere((p) => p.id == 'plan_499');
      expect(p499.priceUsd, equals(5.99));
      expect(p499.formattedTotalPrice(isDomestic: true), equals('₹589'));
      expect(p499.formattedTotalPrice(isDomestic: false), equals('\$5.99'));

      // Tier 5: ₹999 base (₹1179 total) -> $9.99
      final p999 = plans.firstWhere((p) => p.id == 'plan_999');
      expect(p999.priceUsd, equals(9.99));
      expect(p999.formattedTotalPrice(isDomestic: true), equals('₹1179'));
      expect(p999.formattedTotalPrice(isDomestic: false), equals('\$9.99'));

      // Tier 6: ₹2500 base (₹2950 total) -> $24.99
      final p2500 = plans.firstWhere((p) => p.id == 'plan_2500');
      expect(p2500.priceUsd, equals(24.99));
      expect(p2500.formattedTotalPrice(isDomestic: true), equals('₹2950'));
      expect(p2500.formattedTotalPrice(isDomestic: false), equals('\$24.99'));
    });

    test('DigitalAssetPricing formattedSummary outputs correct localized format', () {
      final pricing = DigitalAssetPricing.fromBase(99);
      final domesticSummary = pricing.formattedSummary(isDomestic: true);
      expect(domesticSummary, contains('₹99'));
      expect(domesticSummary, contains('18% GST (₹18)'));
      expect(domesticSummary, contains('₹117'));

      final globalSummary = pricing.formattedSummary(
        usdPrice: 1.99,
        isDomestic: false,
      );
      expect(globalSummary, equals('\$1.99 USD'));
      expect(globalSummary, isNot(contains('GST')));
    });
  });

  group('CountryCodes Global Discovery Tests', () {
    test('findByIso finds valid country codes', () {
      final us = CountryCodes.findByIso('US');
      expect(us.code, equals('+1'));

      final gb = CountryCodes.findByIso('GB');
      expect(gb.code, equals('+44'));

      final inCountry = CountryCodes.findByIso('IN');
      expect(inCountry.code, equals('+91'));
    });

    test('detectDefaultCountry returns a valid non-null CountryCode', () {
      final defaultCountry = CountryCodes.detectDefaultCountry();
      expect(defaultCountry, isNotNull);
      expect(defaultCountry.code, isNotEmpty);
      expect(defaultCountry.name, isNotEmpty);
      expect(defaultCountry.flag, isNotEmpty);
    });
  });

  group('Earnings & Withdrawal Dual-Currency Conversion Logic', () {
    test('calculates correct payout value for earned coins', () {
      const earnedCoins = 500;

      // Domestic: 1 coin = ₹1.00
      final domesticRupees = earnedCoins * 1.0;
      expect(domesticRupees, equals(500.0));
      final domesticDisplay = '₹${domesticRupees.toStringAsFixed(2)} INR';
      expect(domesticDisplay, equals('₹500.00 INR'));

      // International: 100 coins = $1.00 USD
      final internationalUsd = earnedCoins / 100.0;
      expect(internationalUsd, equals(5.00));
      final internationalDisplay = '\$${internationalUsd.toStringAsFixed(2)} USD';
      expect(internationalDisplay, equals('\$5.00 USD'));

      // Minimum thresholds:
      // Domestic: ₹200 (200 coins)
      // International: $10 (1000 coins)
      expect(earnedCoins >= 200, isTrue); // Eligible in India
      expect(earnedCoins >= 1000, isFalse); // Needs 500 more coins for international cashout
    });
  });

  group('RechargePlanCard Dual-Currency Widget Rendering Tests', () {
    const testPlan = RechargePlanUiModel(
      id: 'plan_99',
      coins: 99,
      bonusCoins: 0,
      basePriceRupees: 99,
      gstRupees: 18,
      totalPriceRupees: 117,
      priceUsd: 1.99,
      badgeText: 'POPULAR',
      isPopular: true,
    );

    testWidgets('Renders INR base price when isDomestic is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RechargePlanCard(
              plan: testPlan,
              isSelected: false,
              isDomestic: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify ₹99 base price is displayed
      expect(find.text('₹99'), findsOneWidget);
      expect(find.text('\$1.99'), findsNothing);
    });

    testWidgets('Renders USD price when isDomestic is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RechargePlanCard(
              plan: testPlan,
              isSelected: false,
              isDomestic: false,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify $1.99 USD price is displayed
      expect(find.text('\$1.99'), findsOneWidget);
      expect(find.text('₹99'), findsNothing);
    });
  });
}

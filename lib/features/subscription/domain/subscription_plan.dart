import 'package:flutter/foundation.dart';

@immutable
class SubscriptionPlan {
  final String id;
  final int durationDays;
  final int basePriceRupees;
  final int gstRupees;
  final int totalPriceRupees;
  final String title;
  final String description;
  final String? badge;

  const SubscriptionPlan({
    required this.id,
    required this.durationDays,
    required this.basePriceRupees,
    required this.gstRupees,
    required this.totalPriceRupees,
    required this.title,
    required this.description,
    this.badge,
  });

  /// The total customer-facing amount charged via Google Play (inclusive of 18% GST)
  int get priceRupees => totalPriceRupees;

  static const List<SubscriptionPlan> defaultPlans = [
    SubscriptionPlan(
      id: '1_month',
      durationDays: 30,
      basePriceRupees: 199,
      gstRupees: 36,
      totalPriceRupees: 235,
      title: '1 Month Membership',
      description: '30 days unlimited voice & video calls',
      badge: 'POPULAR',
    ),
    SubscriptionPlan(
      id: '6_months',
      durationDays: 180,
      basePriceRupees: 399,
      gstRupees: 72,
      totalPriceRupees: 471,
      title: '6 Months Membership',
      description: '180 days full access — Great value for regular members',
      badge: 'BEST VALUE',
    ),
    SubscriptionPlan(
      id: '1_year',
      durationDays: 365,
      basePriceRupees: 699,
      gstRupees: 126,
      totalPriceRupees: 825,
      title: '1 Year Membership',
      description: '365 days full access — Maximum savings',
      badge: 'MAX SAVINGS',
    ),
  ];
}

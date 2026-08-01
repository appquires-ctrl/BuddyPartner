import 'package:flutter/foundation.dart';

@immutable
class SubscriptionPlan {
  final String id;
  final int durationDays;
  final int priceRupees;
  final String title;
  final String description;
  final String? badge;

  const SubscriptionPlan({
    required this.id,
    required this.durationDays,
    required this.priceRupees,
    required this.title,
    required this.description,
    this.badge,
  });

  static const List<SubscriptionPlan> defaultPlans = [
    SubscriptionPlan(
      id: '1_day',
      durationDays: 1,
      priceRupees: 9,
      title: '1 Day Pass',
      description: '24-hour unlimited access to all features',
      badge: 'Quick Trial',
    ),
    SubscriptionPlan(
      id: '4_days',
      durationDays: 4,
      priceRupees: 30,
      title: '4 Days Pass',
      description: '4 days of full access',
    ),
    SubscriptionPlan(
      id: '7_days',
      durationDays: 7,
      priceRupees: 50,
      title: '1 Week Pass',
      description: '7 days full access — Save 20%',
      badge: 'POPULAR',
    ),
    SubscriptionPlan(
      id: '1_month',
      durationDays: 30,
      priceRupees: 250,
      title: '1 Month Pass',
      description: '30 days full access — Best for daily users',
      badge: 'BEST VALUE',
    ),
    SubscriptionPlan(
      id: '1_year',
      durationDays: 365,
      priceRupees: 2500,
      title: '1 Year VIP',
      description: '365 days full access — Maximum savings',
      badge: 'VIP ACCESS',
    ),
  ];
}

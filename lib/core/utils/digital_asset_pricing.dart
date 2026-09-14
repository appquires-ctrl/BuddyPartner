import 'package:flutter/foundation.dart';

/// Centralized Indian GST and pricing model for all digital assets in the app
/// (Coin packs, Membership subscriptions, VIP features, Gifts, etc.).
///
/// Follows the Option B "Customer pays 18% extra" model:
/// - Base Price: Shown initially in browsing UI.
/// - 18% GST: Calculated as `(basePrice * 0.18).round()`.
/// - Total Price: Customer-facing checkout amount configured in Google Play Console.
@immutable
class DigitalAssetPricing {
  static const double gstRate = 0.18;

  final int basePriceRupees;
  final int gstRupees;
  final int totalPriceRupees;

  const DigitalAssetPricing({
    required this.basePriceRupees,
    required this.gstRupees,
    required this.totalPriceRupees,
  });

  /// Factory that computes GST and total price from a base INR price
  factory DigitalAssetPricing.fromBase(int basePrice) {
    final gst = (basePrice * gstRate).round();
    return DigitalAssetPricing(
      basePriceRupees: basePrice,
      gstRupees: gst,
      totalPriceRupees: basePrice + gst,
    );
  }

  /// Factory for predefined/fixed values
  factory DigitalAssetPricing.withFixedValues({
    required int basePrice,
    required int gst,
    required int total,
  }) {
    return DigitalAssetPricing(
      basePriceRupees: basePrice,
      gstRupees: gst,
      totalPriceRupees: total,
    );
  }

  /// Breakdown summary text e.g. "₹99 + 18% GST (₹18) = ₹117"
  String get breakdownSummary =>
      '₹$basePriceRupees + 18% GST (₹$gstRupees) = ₹$totalPriceRupees';
}

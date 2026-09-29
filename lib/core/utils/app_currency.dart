import 'dart:ui';
import 'package:flutter/foundation.dart';

/// Centralized Dual-Currency & Localization Helper (INR for India, USD for Rest of World).
class AppCurrency {
  AppCurrency._();

  /// Determines if the current context / user is located in India.
  /// Checks country name, ISO code, or phone number prefix (+91).
  /// If unauthenticated or unspecified, falls back to device locale.
  static bool isDomestic({
    String? country,
    String? phoneNumber,
    String? countryCode,
  }) {
    if (country != null && country.trim().isNotEmpty) {
      final c = country.trim().toLowerCase();
      if (c == 'india' || c == 'in' || c == '+91' || c == '91') {
        return true;
      }
    }

    if (countryCode != null && countryCode.trim().isNotEmpty) {
      final code = countryCode.trim().replaceAll('+', '');
      if (code == '91' || code.toLowerCase() == 'in') {
        return true;
      }
    }

    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      final p = phoneNumber.trim().replaceAll(' ', '').replaceAll('-', '');
      if (p.startsWith('+91') || p.startsWith('91')) {
        return true;
      }
    }

    // Fallback: Check device locale
    try {
      final localeIso = PlatformDispatcher.instance.locale.countryCode;
      if (localeIso != null && localeIso.toUpperCase() == 'IN') {
        return true;
      }
      if (localeIso != null && localeIso.isNotEmpty) {
        return false;
      }
    } catch (_) {}

    // Default to true (domestic) if completely undetermined
    return true;
  }

  /// Currency symbol: '₹' for India, '$' for Rest of World
  static String symbol({bool isDomestic = true}) => isDomestic ? '₹' : '\$';

  /// Currency 3-letter ISO code: 'INR' or 'USD'
  static String code({bool isDomestic = true}) => isDomestic ? 'INR' : 'USD';

  /// Format an amount into a customer-facing string:
  /// e.g. format(inr: 199, usd: 2.99, isDomestic: true) -> '₹199'
  ///      format(inr: 199, usd: 2.99, isDomestic: false) -> '$2.99'
  static String format({
    required num inr,
    required num usd,
    bool isDomestic = true,
    bool showDecimalsForInr = false,
  }) {
    if (isDomestic) {
      final val = showDecimalsForInr
          ? inr.toStringAsFixed(2)
          : (inr is int || inr == inr.roundToDouble()
              ? inr.toInt().toString()
              : inr.toStringAsFixed(2));
      return '₹$val';
    } else {
      return '\$${usd.toStringAsFixed(2)}';
    }
  }

  /// Tax label e.g. "Goods & Services Tax (18% GST)" vs "Local Taxes & VAT"
  static String taxLabel({bool isDomestic = true}) {
    return isDomestic
        ? 'Goods & Services Tax (18% GST)'
        : 'Applicable Store Taxes & VAT';
  }

  /// Disclaimer for checkout
  static String checkoutDisclaimer({
    required String inrBreakdown,
    required String usdTotal,
    bool isDomestic = true,
  }) {
    if (isDomestic) {
      return '$inrBreakdown. Billed securely through Google Play.';
    } else {
      return '$usdTotal USD. Billed securely through Google Play. (Local taxes calculated at checkout).';
    }
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';

/// Centralized Dual-Currency & Localization Helper (INR for India, USD for Rest of World).
class AppCurrency {
  AppCurrency._();

  static String? activeUserCountry;
  static String? activeUserPhone;
  static String? activeUserCountryCode;

  /// Sets or clears active user country attributes for app-wide currency detection.
  static void setActiveUser({
    String? country,
    String? phoneNumber,
    String? countryCode,
  }) {
    activeUserCountry = country;
    activeUserPhone = phoneNumber;
    activeUserCountryCode = countryCode;
  }

  /// Determines if the current context / user is located in India.
  /// Checks country name, ISO code, or phone number prefix (+91).
  /// If unauthenticated or unspecified, falls back to device locale.
  static bool isDomestic({
    String? country,
    String? phoneNumber,
    String? countryCode,
  }) {
    final effectiveCountry = (country != null && country.trim().isNotEmpty)
        ? country
        : activeUserCountry;
    final effectiveCountryCode = (countryCode != null && countryCode.trim().isNotEmpty)
        ? countryCode
        : activeUserCountryCode;
    final effectivePhone = (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        ? phoneNumber
        : activeUserPhone;

    if (effectiveCountry != null && effectiveCountry.trim().isNotEmpty) {
      final c = effectiveCountry.trim().toLowerCase();
      if (c == 'india' || c == 'in' || c == '+91' || c == '91') {
        return true;
      }
      return false;
    }

    if (effectiveCountryCode != null && effectiveCountryCode.trim().isNotEmpty) {
      final code = effectiveCountryCode.trim().replaceAll('+', '');
      if (code == '91' || code.toLowerCase() == 'in') {
        return true;
      }
      return false;
    }

    if (effectivePhone != null && effectivePhone.trim().isNotEmpty) {
      final p = effectivePhone.trim().replaceAll(' ', '').replaceAll('-', '');
      if (p.startsWith('+91') || p.startsWith('91')) {
        return true;
      }
      if (p.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(p)) {
        return true;
      }
      return false;
    }

    // Check device timezone: Indian Standard Time (+05:30, 330 minutes)
    try {
      if (DateTime.now().timeZoneOffset.inMinutes == 330) {
        return true;
      }
    } catch (_) {}

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

  /// Coin internal icon: Rupee (₹) for India, Dollar ($) for Rest of World
  static IconData coinIcon({bool? isDomestic}) {
    final domestic = isDomestic ?? AppCurrency.isDomestic();
    return domestic ? Icons.currency_rupee_rounded : Icons.attach_money_rounded;
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

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';

/// Compile-time flag for development sandbox verification (strictly false by default)
const bool kEnableSandboxVerify = bool.fromEnvironment(
  'ENABLE_SANDBOX_VERIFY',
  defaultValue: false,
);

/// Product IDs for Google Play Consumable Coin Packs
const Set<String> kGooglePlayCoinProductIds = {
  'plan_49',
  'plan_99',
  'plan_199',
  'plan_499',
  'plan_999',
  'plan_2500',
  'plan_20',
  'plan_50',
  'plan_100',
  'plan_200',
  'plan_500',
  'plan_1000',
  'plan_2000',
};

/// Product IDs for Google Play Subscriptions & Membership Passes
const Set<String> kGooglePlaySubscriptionProductIds = {
  'membership_1_month',
  'membership_6_months',
  'membership_1_year',
  'pass_1_month',
  'pass_6_months',
  'pass_1_year',
  '1_month',
  '6_months',
  '1_year',
  'pass_1_day',
  'pass_7_days',
  '1_day',
  '7_days',
};

enum GooglePlayPurchaseStatus {
  idle,
  loading,
  purchasing,
  verifying,
  success,
  error,
  canceled,
}

class GooglePlayState {
  final bool isAvailable;
  final GooglePlayPurchaseStatus status;
  final String? errorMessage;
  final String? successMessage;
  final Map<String, ProductDetails> products;

  const GooglePlayState({
    this.isAvailable = false,
    this.status = GooglePlayPurchaseStatus.idle,
    this.errorMessage,
    this.successMessage,
    this.products = const {},
  });

  GooglePlayState copyWith({
    bool? isAvailable,
    GooglePlayPurchaseStatus? status,
    String? errorMessage,
    String? successMessage,
    Map<String, ProductDetails>? products,
  }) {
    return GooglePlayState(
      isAvailable: isAvailable ?? this.isAvailable,
      status: status ?? this.status,
      errorMessage: errorMessage,
      successMessage: successMessage,
      products: products ?? this.products,
    );
  }
}

class GooglePlayPurchaseNotifier extends StateNotifier<GooglePlayState> {
  final Ref _ref;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  GooglePlayPurchaseNotifier(this._ref) : super(const GooglePlayState()) {
    _init();
  }

  void _init() {
    final purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdated,
      onDone: () => _subscription?.cancel(),
      onError: (error) {
        debugPrint('❌ [Google Play Stream Error]: $error');
        state = state.copyWith(
          status: GooglePlayPurchaseStatus.error,
          errorMessage: 'Purchase stream error: $error',
        );
      },
    );

    loadProducts();
  }

  /// Query available Google Play in-app and subscription products
  Future<void> loadProducts() async {
    try {
      final isAvailable = await _iap.isAvailable();
      if (!isAvailable) {
        debugPrint(
          '⚠️ [Google Play] In-App Billing is not available on this device.',
        );
        state = state.copyWith(isAvailable: false);
        return;
      }

      final allIds = {
        ...kGooglePlayCoinProductIds,
        ...kGooglePlaySubscriptionProductIds,
      };
      final ProductDetailsResponse response = await _iap.queryProductDetails(
        allIds,
      );

      if (response.error != null) {
        debugPrint('❌ [Google Play Query Error]: ${response.error?.message}');
      }

      final productMap = <String, ProductDetails>{};
      for (final p in response.productDetails) {
        productMap[p.id] = p;
        debugPrint(
          '🛍️ [Google Play Product Found]: ${p.id} - ${p.title} (${p.price})',
        );
      }

      state = state.copyWith(isAvailable: true, products: productMap);
    } catch (e) {
      debugPrint('❌ [Google Play Init Exception]: $e');
      state = state.copyWith(isAvailable: false);
    }
  }

  /// Initiate purchase for a specific product ID (Coin pack or Subscription pass)
  Future<bool> buyProduct(String productId, {bool isConsumable = true}) async {
    AppLogger.button(
      'Buy Google Play Product: $productId',
      screen: 'GooglePlayPurchaseService',
    );

    // 1. Try to find product details from Google Play Store query
    ProductDetails? product = state.products[productId];

    // If product details not cached, re-query Google Play
    if (product == null) {
      final res = await _iap.queryProductDetails({productId});
      if (res.productDetails.isNotEmpty) {
        product = res.productDetails.first;
        state = state.copyWith(
          products: {...state.products, product.id: product},
        );
      }
    }

    if (product == null) {
      debugPrint(
        '❌ [Google Play] Product $productId not found in Google Play Console.',
      );
      state = state.copyWith(
        status: GooglePlayPurchaseStatus.error,
        errorMessage:
            'This product is currently unavailable on Google Play Store.',
      );
      return false;
    }

    state = state.copyWith(status: GooglePlayPurchaseStatus.purchasing);

    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );
      if (isConsumable) {
        return await _iap.buyConsumable(purchaseParam: purchaseParam);
      } else {
        return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      }
    } catch (e) {
      debugPrint('❌ [Google Play Launch Error]: $e');
      state = state.copyWith(
        status: GooglePlayPurchaseStatus.error,
        errorMessage: 'Unable to initiate Google Play purchase: $e',
      );
      return false;
    }
  }

  /// Listen for purchase state updates from Google Play Billing
  Future<void> _onPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          debugPrint(
            '⏳ [Google Play] Purchase Pending for ${purchase.productID}...',
          );
          state = state.copyWith(status: GooglePlayPurchaseStatus.purchasing);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          debugPrint(
            '✅ [Google Play] Purchase Success for ${purchase.productID}. Verifying on backend...',
          );
          state = state.copyWith(status: GooglePlayPurchaseStatus.verifying);
          await _verifyPurchaseWithBackend(purchase);
          break;

        case PurchaseStatus.error:
          debugPrint(
            '❌ [Google Play] Purchase Error: ${purchase.error?.message}',
          );
          state = state.copyWith(
            status: GooglePlayPurchaseStatus.error,
            errorMessage:
                purchase.error?.message ?? 'Payment failed or was declined.',
          );
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.canceled:
          debugPrint('ℹ️ [Google Play] Purchase Canceled by user.');
          state = state.copyWith(status: GooglePlayPurchaseStatus.canceled);
          break;
      }
    }
  }

  /// Send authentic Google Play purchase token and receipt to backend for verification
  Future<void> _verifyPurchaseWithBackend(PurchaseDetails purchase) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final purchaseToken = purchase.verificationData.serverVerificationData
          .trim();
      final productId = purchase.productID;
      final orderId = purchase.purchaseID;

      if (purchaseToken.isEmpty) {
        debugPrint(
          '❌ [Google Play Security] Empty serverVerificationData in purchase receipt.',
        );
        state = state.copyWith(
          status: GooglePlayPurchaseStatus.error,
          errorMessage: 'Purchase token missing from Google Play receipt.',
        );
        return;
      }

      final response = await apiClient.dio.post(
        '/api/payments/google-play/verify',
        data: {
          'productId': productId,
          'purchaseToken': purchaseToken,
          'orderId': orderId,
          'signature': purchase.verificationData.localVerificationData,
          'rawDetails': {
            'productID': purchase.productID,
            'purchaseID': purchase.purchaseID,
            'transactionDate': purchase.transactionDate,
            'status': purchase.status.name,
          },
        },
      );

      if (response.statusCode == 200 && response.data?['success'] == true) {
        final data = response.data as Map<String, dynamic>;
        debugPrint(' [Google Play Server Verified]: $data');

        // Complete purchase with Google Play to acknowledge & consume
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }

        // Invalidate and refresh wallet & subscription providers
        _ref.invalidate(walletBalanceProvider);
        _ref.invalidate(dualWalletProvider);
        _ref.read(subscriptionStatusProvider.notifier).reload();

        final isCoin = data['purchaseType'] == 'inapp';
        final msg = isCoin
            ? 'Successfully added ${data['coinsCredited']} coins to your wallet!'
            : 'VIP Subscription Pass activated successfully!';

        state = state.copyWith(
          status: GooglePlayPurchaseStatus.success,
          successMessage: msg,
        );
      } else {
        final errorMsg =
            response.data?['message'] ??
            'Failed to verify purchase with server.';
        state = state.copyWith(
          status: GooglePlayPurchaseStatus.error,
          errorMessage: errorMsg.toString(),
        );
      }
    } catch (e) {
      debugPrint('❌ [Google Play Verification Exception]: $e');
      String displayError = e.toString();
      if (e is DioException) {
        final resData = e.response?.data;
        if (resData is Map) {
          displayError =
              resData['message'] ??
              resData['error'] ??
              e.message ??
              'Server verification failed';
        } else if (e.message != null) {
          displayError = e.message!;
        }
      }
      state = state.copyWith(
        status: GooglePlayPurchaseStatus.error,
        errorMessage: displayError,
      );
    }
  }

  void resetStatus() {
    state = state.copyWith(
      status: GooglePlayPurchaseStatus.idle,
      errorMessage: null,
      successMessage: null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final googlePlayPurchaseProvider =
    StateNotifierProvider<GooglePlayPurchaseNotifier, GooglePlayState>((ref) {
      return GooglePlayPurchaseNotifier(ref);
    });

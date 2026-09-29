import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/initiator_otp_modal.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/buddy/data/buddy_group_service.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/home/presentation/widgets/vip_live_activity_ticker.dart';
import 'package:buddypartner/core/services/geo_service.dart';
import 'package:buddypartner/core/constants/country_codes.dart';


/// Bottom sheet to customize and broadcast a new Buddy Request.
class CreateBuddyRequestSheet extends ConsumerStatefulWidget {
  final BuddyType buddyType;
  final String? campaignId;
  final String? customTitle;
  final String? customSubtitle;
  final String? customIconUrl;
  final int? customCoinCost;
  final Color? customAccentColor;

  const CreateBuddyRequestSheet({
    super.key,
    required this.buddyType,
    this.campaignId,
    this.customTitle,
    this.customSubtitle,
    this.customIconUrl,
    this.customCoinCost,
    this.customAccentColor,
  });

  static Future<void> show(
    BuildContext context,
    BuddyType buddyType, {
    String? campaignId,
    String? customTitle,
    String? customSubtitle,
    String? customIconUrl,
    int? customCoinCost,
    Color? customAccentColor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateBuddyRequestSheet(
        buddyType: buddyType,
        campaignId: campaignId,
        customTitle: customTitle,
        customSubtitle: customSubtitle,
        customIconUrl: customIconUrl,
        customCoinCost: customCoinCost,
        customAccentColor: customAccentColor,
      ),
    );
  }

  @override
  ConsumerState<CreateBuddyRequestSheet> createState() => _CreateBuddyRequestSheetState();
}

class _CreateBuddyRequestSheetState extends ConsumerState<CreateBuddyRequestSheet> {
  late String _selectedCity;
  String _selectedState = '';
  BuddyTargetGender _selectedGender = BuddyTargetGender.all;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    final authUser = ref.read(authStateProvider).value;
    final defaultCity = profile?.city ?? authUser?.city;
    final defaultState = profile?.state ?? authUser?.state;
    _selectedCity = (defaultCity != null && defaultCity.trim().isNotEmpty)
        ? defaultCity.trim()
        : 'Mumbai';
    _selectedState = defaultState?.trim() ?? '';
  }

  void _openCityPicker() {
    // Determine user's registered country ISO for scoping the city search
    final authUser = ref.read(authStateProvider).value;
    final countryIso = authUser?.country ?? 'IN';
    CityPickerSheet.show(
      context,
      currentCity: _selectedCity,
      currentState: _selectedState,
      countryIso: countryIso,
    ).then((result) {
      if (result != null) {
        setState(() {
          _selectedCity = result.city;
          _selectedState = result.state;
        });
      }
    });
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;

    final requiredCoins = widget.customCoinCost ?? widget.buddyType.coinCost;
    int currentCoins = ref.read(walletBalanceProvider).value ?? -1;
    if (currentCoins < requiredCoins) {
      try {
        currentCoins = await ref.read(walletBalanceProvider.notifier).fetchBalance(force: true);
      } catch (_) {
        currentCoins = currentCoins == -1 ? 0 : currentCoins;
      }
    }

    if (currentCoins < requiredCoins) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close create sheet
      openRechargeForDeficit(
        context: context,
        ref: ref,
        requiredCoins: requiredCoins,
        currentBalance: currentCoins,
        featureName: widget.customTitle ?? widget.buddyType.title,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.buddyType.isGroup) {
        // Multi-member Buddy Group Broadcast (Garba: 6, Cricket: 11) - 0 OTP
        final isCricket = widget.buddyType == BuddyType.cricket;
        final defaultTitle = isCricket ? 'Cricket Buddy Group' : 'Dandiya Buddy Group';
        final newGroup = await ref.read(buddyGroupServiceProvider).createGroupBroadcast(
          city: _selectedCity,
          state: _selectedState,
          targetGender: _selectedGender.id,
          title: widget.customTitle ?? defaultTitle,
          buddyType: widget.buddyType.id,
        );

        if (!mounted) return;
        Navigator.of(context).pop(); // Close create sheet

        final joinersCount = widget.buddyType.maxGroupMembers - 1;
        AppSnackBar.showSuccess(
          context,
          isCricket
              ? 'Cricket Team broadcast is live! $joinersCount other players can now join.'
              : 'Garba Group broadcast is live! $joinersCount other members can now join.',
        );

        // Invalidate wallet balance and groups list to refresh UI immediately
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(myBuddyGroupsProvider);

        // Redirect host directly to the Group Chat screen!
        context.push(
          RouteNames.buddyGroupChat,
          extra: {
            'groupId': newGroup.id,
            'title': newGroup.title,
            'memberCount': 1,
          },
        );
        return;
      }

      final newReq = await ref.read(buddyControllerProvider.notifier).createBuddyRequest(
        type: widget.buddyType,
        city: _selectedCity,
        targetState: _selectedState,
        targetGender: _selectedGender,
        campaignId: widget.campaignId,
        customTitle: widget.customTitle,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close create sheet

      final displayTitle = widget.customTitle ?? widget.buddyType.title;
      final locationLabel = _selectedState.isNotEmpty ? '$_selectedCity, $_selectedState' : _selectedCity;
      AppSnackBar.showSuccess(
        context,
        '$displayTitle broadcast is live in $locationLabel!',
      );

      // Open waiting modal for the initiator
      if (mounted) {
        InitiatorOtpModal.show(context, request: newReq);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final type = widget.buddyType;
    final displayTitle = widget.customTitle ?? type.title;
    final displaySubtitle = type.isGroup
        ? (type == BuddyType.cricket ? 'Start an 11-person Cricket team chat' : 'Start a 6-person Garba group chat')
        : (widget.customSubtitle ?? type.subtitle);
    final effectiveCoins = widget.customCoinCost ?? type.coinCost;
    final effectiveAccent = widget.customAccentColor ?? type.accentColor;
    final effectiveGradients = widget.customAccentColor != null
        ? [widget.customAccentColor!, widget.customAccentColor!.withValues(alpha: 0.8)]
        : type.gradientColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header with Sticker & Title
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: effectiveGradients,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: widget.customIconUrl != null && widget.customIconUrl!.isNotEmpty
                      ? (widget.customIconUrl!.startsWith('http')
                          ? Image.network(
                              widget.customIconUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Image.asset(type.stickerAsset, fit: BoxFit.cover),
                            )
                          : Image.asset(
                              widget.customIconUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Image.asset(type.stickerAsset, fit: BoxFit.cover),
                            ))
                      : Image.asset(
                          type.stickerAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stack) => const Icon(
                            Icons.local_activity_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displaySubtitle,
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Live Activity Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: const VipLiveActivityTicker(
              isCompact: true,
              textStyle: TextStyle(
                color: Color(0xFF047857),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 1. City Selector
          Text(
            'BROADCAST LOCATION',
            style: typography.bodySmall.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _openCityPicker,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: type.accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: type.accentColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedCity,
                          style: typography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Tap to change target city',
                          style: typography.bodySmall.copyWith(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 2. Target Gender Selector
          Text(
            'LOOKING FOR',
            style: typography.bodySmall.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: BuddyTargetGender.values.map((g) {
              final isSelected = _selectedGender == g;
              final icon = g == BuddyTargetGender.female
                  ? Icons.female_rounded
                  : (g == BuddyTargetGender.male ? Icons.male_rounded : Icons.people_alt_rounded);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: InkWell(
                    onTap: () => setState(() => _selectedGender = g),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? effectiveAccent.withValues(alpha: 0.12)
                            : colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? effectiveAccent : colors.cardBorder,
                          width: isSelected ? 1.6 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: isSelected ? effectiveAccent : colors.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            g.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? effectiveAccent : colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // 3. Pricing & Info Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppCoinIcon(size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Cost: $effectiveCoins Coin${effectiveCoins == 1 ? '' : 's'}',
                      style: typography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Charged on Submit',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  type.isGroup
                      ? '• Creates a ${type.maxGroupMembers}-member ${type == BuddyType.cricket ? "Cricket team" : "Garba group"}. Up to ${type.maxGroupMembers - 1} people in $_selectedCity can join for FREE.\n'
                        '• Group chat unlocks immediately for everyone with ZERO verification OTP.'
                      : '• The first person in $_selectedCity to accept will unlock chat with you immediately.\n'
                        '• When you meet in person, share your 6-digit verification code with your buddy.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF78350F),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Submit CTA Button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: effectiveAccent,
                elevation: 3,
                shadowColor: effectiveAccent.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSubmitting
                  ? const AppLoadingIndicator(size: 22, color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const AppCoinIcon(size: 18),
                        const SizedBox(width: 8),
                        Text(
                          type.isGroup
                              ? 'Broadcast Group ($effectiveCoins Coins)'
                              : 'Broadcast Request ($effectiveCoins Coin${effectiveCoins == 1 ? '' : 's'})',
                          style: typography.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}

/// API-backed city picker sheet.
/// Searches cities scoped to [countryIso] via GET /api/geo/cities.
/// Shows "city, state" for disambiguation (e.g. "Aurangabad, Maharashtra").
/// Falls back to a free-text `Use typed city` option when no match is found.
class CityPickerSheet extends ConsumerStatefulWidget {
  final String currentCity;
  final String currentState;
  final String countryIso;

  const CityPickerSheet({
    super.key,
    required this.currentCity,
    required this.currentState,
    required this.countryIso,
  });

  static Future<CityResult?> show(
    BuildContext context, {
    required String currentCity,
    required String currentState,
    required String countryIso,
  }) {
    return showModalBottomSheet<CityResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CityPickerSheet(
        currentCity: currentCity,
        currentState: currentState,
        countryIso: countryIso,
      ),
    );
  }

  @override
  ConsumerState<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends ConsumerState<CityPickerSheet> {
  late TextEditingController _searchController;
  List<CityResult> _results = [];
  bool _isLoading = false;
  String _activeCountryIso = '';
  String _countryFlag = '';
  String _countryName = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _activeCountryIso = widget.countryIso.toUpperCase();
    _resolveCountryLabel();
    // Load popular cities immediately on open
    _search('');
  }

  void _resolveCountryLabel() {
    try {
      final cc = CountryCodes.allCountries.firstWhere(
        (c) => c.iso == _activeCountryIso,
        orElse: () => CountryCodes.defaultCountry,
      );
      _countryFlag = cc.flag;
      _countryName = cc.name;
    } catch (_) {
      _countryFlag = '🌍';
      _countryName = _activeCountryIso;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    try {
      final results = await ref.read(geoServiceProvider).searchCities(
            countryIso: _activeCountryIso,
            q: query.trim(),
            limit: 25,
          );
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    // Debounce: cancel previous timer by re-calling after 350ms
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_searchController.text == value) {
        _search(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final query = _searchController.text.trim();
    // Show free-text option only when typed city is not already in results
    final showCustom = query.isNotEmpty &&
        !_results.any((r) => r.city.toLowerCase() == query.toLowerCase());
    final itemCount = _results.length + (showCustom ? 1 : 0);

    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 8),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title + Country scope chip
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select City',
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  // Country scope indicator — tap to change
                  GestureDetector(
                    onTap: _changeCountry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_countryFlag, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 5),
                          Text(
                            _countryName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: colors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search field
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search city in $_countryName...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  filled: true,
                  fillColor: colors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Results list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : itemCount == 0
                        ? Center(
                            child: Text(
                              'No cities found.\nTry a different spelling.',
                              textAlign: TextAlign.center,
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: itemCount,
                            separatorBuilder: (_, i) =>
                                Divider(height: 1, color: colors.border.withValues(alpha: 0.4)),
                            itemBuilder: (context, index) {
                              // Custom free-text option at end
                              if (index == _results.length && showCustom) {
                                return ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  leading: Icon(Icons.add_location_alt_rounded,
                                      color: colors.primary),
                                  title: Text(
                                    'Use "$query"',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Custom city not in the list',
                                    style:
                                        TextStyle(fontSize: 11, color: colors.textSecondary),
                                  ),
                                  onTap: () => Navigator.of(context)
                                      .pop(CityResult(city: query, state: '')),
                                );
                              }

                              // Regular city result
                              final result = _results[index];
                              final isSelected =
                                  result.city.toLowerCase() ==
                                          widget.currentCity.toLowerCase() &&
                                      result.state.toLowerCase() ==
                                          widget.currentState.toLowerCase();

                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                title: Text(
                                  result.city,
                                  style: TextStyle(
                                    fontWeight:
                                        isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? colors.primary : colors.textPrimary,
                                  ),
                                ),
                                // State shown as disambiguation subtitle
                                subtitle: result.state.isNotEmpty
                                    ? Text(
                                        result.state,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colors.textSecondary,
                                        ),
                                      )
                                    : null,
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded, color: colors.primary)
                                    : null,
                                onTap: () => Navigator.of(context).pop(result),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  /// Lets travelers override the scoped country
  void _changeCountry() {
    showModalBottomSheet<CountryCode>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountrySelectSheet(selectedIso: _activeCountryIso),
    ).then((cc) {
      if (cc != null && mounted) {
        setState(() {
          _activeCountryIso = cc.iso;
          _countryFlag = cc.flag;
          _countryName = cc.name;
          _results = [];
          _searchController.clear();
        });
        _search('');
      }
    });
  }
}

/// Mini country picker shown when the user taps "Change Country" inside CityPickerSheet.
class _CountrySelectSheet extends StatefulWidget {
  final String selectedIso;
  const _CountrySelectSheet({required this.selectedIso});

  @override
  State<_CountrySelectSheet> createState() => _CountrySelectSheetState();
}

class _CountrySelectSheetState extends State<_CountrySelectSheet> {
  late List<CountryCode> _filtered;
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = List.from(CountryCodes.allCountries);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final query = q.toLowerCase().trim();
    setState(() {
      _filtered = query.isEmpty
          ? List.from(CountryCodes.allCountries)
          : CountryCodes.allCountries
              .where((c) => c.searchKey.contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 8),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select Country',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ctrl,
                onChanged: _filter,
                decoration: InputDecoration(
                  hintText: 'Search country...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: colors.surfaceMuted,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final cc = _filtered[i];
                    final isSelected = cc.iso == widget.selectedIso;
                    return ListTile(
                      leading: Text(cc.flag, style: const TextStyle(fontSize: 20)),
                      title: Text(
                        cc.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? colors.primary : colors.textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: colors.primary)
                          : null,
                      onTap: () => Navigator.of(context).pop(cc),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}


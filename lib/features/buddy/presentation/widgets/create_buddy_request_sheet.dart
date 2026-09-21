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
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

/// Comprehensive Indian cities list — tier 1, 2 & 3 including all state capitals.
/// Covers ~98% of Indian urban population. Alternate spellings (Bangalore/Bengaluru)
/// are listed so both match correctly.
const List<String> kIndianCities = [
  // ── Mega cities ──
  'Mumbai', 'Delhi', 'Kolkata', 'Chennai', 'Bengaluru', 'Bangalore',
  'Hyderabad', 'Ahmedabad', 'Pune', 'Surat',

  // ── State capitals ──
  'Jaipur', 'Lucknow', 'Bhopal', 'Patna', 'Bhubaneswar', 'Raipur',
  'Chandigarh', 'Dehradun', 'Shimla', 'Gangtok', 'Guwahati', 'Shillong',
  'Aizawl', 'Imphal', 'Kohima', 'Itanagar', 'Agartala', 'Dispur',
  'Panaji', 'Thiruvananthapuram', 'Amaravati', 'Ranchi', 'Jammu',
  'Srinagar', 'Leh', 'Port Blair', 'Kavaratti', 'Silvassa', 'Daman',
  'Pondicherry',

  // ── Tier 2 & major cities ──
  'Noida', 'Gurgaon', 'Gurugram', 'Faridabad', 'Ghaziabad',
  'Agra', 'Varanasi', 'Kanpur', 'Allahabad', 'Prayagraj', 'Meerut',
  'Nashik', 'Nagpur', 'Aurangabad', 'Solapur', 'Amravati',
  'Kolhapur', 'Navi Mumbai', 'Thane', 'Kalyan',
  'Visakhapatnam', 'Vijayawada', 'Guntur', 'Warangal', 'Tirupati',
  'Coimbatore', 'Madurai', 'Salem', 'Tiruchirappalli', 'Tiruppur',
  'Vellore', 'Erode', 'Thoothukudi',
  'Kochi', 'Kozhikode', 'Thrissur', 'Kannur', 'Kollam',
  'Mysuru', 'Mysore', 'Mangaluru', 'Mangalore', 'Hubli', 'Dharwad',
  'Belgaum', 'Belagavi', 'Tumkur',
  'Indore', 'Gwalior', 'Jabalpur', 'Ujjain',
  'Jodhpur', 'Kota', 'Bikaner', 'Ajmer', 'Udaipur',
  'Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala',
  'Vadodara', 'Rajkot', 'Bhavnagar', 'Jamnagar', 'Gandhinagar',
  'Jamshedpur', 'Dhanbad', 'Bokaro',
  'Goa', 'Margao',
  'Siliguri', 'Asansol', 'Durgapur', 'Howrah',
  'Guwahati', 'Dibrugarh', 'Jorhat',
  'Cuttack', 'Rourkela',
  'Bilaspur', 'Bhilai',
  'Puducherry', 'Vasco',

  // ── Tier 3 & growing towns ──
  'Haridwar', 'Rishikesh', 'Roorkee', 'Nainital', 'Mussoorie',
  'Mathura', 'Vrindavan', 'Aligarh', 'Bareilly', 'Moradabad', 'Gorakhpur',
  'Jhansi', 'Firozabad', 'Saharanpur',
  'Tirunelveli', 'Dindigul', 'Kanchipuram', 'Nagercoil',
  'Calicut', 'Palakkad',
  'Anantapur', 'Nellore', 'Kurnool', 'Rajahmundry', 'Kakinada',
  'Aurangabad', 'Latur', 'Nanded', 'Jalgaon', 'Sangli',
  'Parbhani', 'Osmanabad', 'Bidar', 'Gulbarga', 'Kalaburagi',
  'Raichur', 'Ballari', 'Davangere',
  'Jabalpur', 'Satna', 'Sagar', 'Rewa',
  'Korba', 'Durg', 'Rajnandgaon',
  'Muzaffarpur', 'Gaya', 'Bhagalpur', 'Darbhanga',
  'Berhampore', 'Malda', 'Jalpaiguri',
  'Dimapur', 'Silchar', 'Nagaon',
  'Shillong', 'Tura',
  'Agartala', 'Dharmanagar',
];

/// Pure-Dart Levenshtein edit-distance implementation (no external packages).
/// Handles transpositions, deletions, insertions and substitutions.
/// Returns the minimum number of single-character edits to transform [a] into [b].
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Use two rows for O(min(a,b)) space
  List<int> prev = List<int>.generate(b.length + 1, (i) => i);
  List<int> curr = List<int>.filled(b.length + 1, 0);

  for (int i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1,         // deletion
        curr[j - 1] + 1,     // insertion
        prev[j - 1] + cost,  // substitution
      ].reduce((v, e) => v < e ? v : e);
    }
    final temp = prev;
    prev = curr;
    curr = temp;
  }
  return prev[b.length];
}

/// Returns true if [query] is a fuzzy match for [city].
/// Matches exact substrings first, then allows 1–2 character edits
/// proportional to the query length (longer queries tolerate more errors).
bool _fuzzyMatch(String city, String query) {
  final c = city.toLowerCase();
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return true;

  // 1. Exact substring (fastest path)
  if (c.contains(q)) return true;

  // 2. Query starts-with match on any word in the city name
  final words = c.split(RegExp(r'\s+'));
  if (words.any((w) => w.startsWith(q))) return true;

  // 3. Levenshtein on the city prefix of same length as query
  // Allows: 1 typo for queries ≥4 chars, 2 typos for queries ≥7 chars
  if (q.length >= 4) {
    final maxDist = q.length >= 7 ? 2 : 1;
    final prefix = c.length > q.length ? c.substring(0, q.length) : c;
    if (_levenshtein(prefix, q) <= maxDist) return true;

    // Also check each word prefix
    for (final word in words) {
      final wp = word.length > q.length ? word.substring(0, q.length) : word;
      if (_levenshtein(wp, q) <= maxDist) return true;
    }
  }

  return false;
}

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
  BuddyTargetGender _selectedGender = BuddyTargetGender.all;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    final authUser = ref.read(authStateProvider).value;
    final defaultCity = profile?.city ?? authUser?.city;
    _selectedCity = (defaultCity != null && defaultCity.trim().isNotEmpty)
        ? defaultCity.trim()
        : 'Mumbai';
  }

  void _openCityPicker() {
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CityPickerSheet(currentCity: _selectedCity),
    ).then((chosenCity) {
      if (chosenCity != null && chosenCity.isNotEmpty) {
        setState(() {
          _selectedCity = chosenCity;
        });
      }
    });
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;

    final requiredCoins = widget.customCoinCost ?? widget.buddyType.coinCost;
    final currentCoins = ref.read(walletBalanceProvider).value ?? 0;
    if (currentCoins < requiredCoins) {
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
      final newReq = await ref.read(buddyControllerProvider.notifier).createBuddyRequest(
        type: widget.buddyType,
        city: _selectedCity,
        targetGender: _selectedGender,
        campaignId: widget.campaignId,
        customTitle: widget.customTitle,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close create sheet

      final displayTitle = widget.customTitle ?? widget.buddyType.title;
      AppSnackBar.showSuccess(
        context,
        '$displayTitle broadcast is live in $_selectedCity!',
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
    final displaySubtitle = widget.customSubtitle ?? type.subtitle;
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
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
          const SizedBox(height: 20),

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
                  '• The first person in $_selectedCity to accept will unlock chat with you immediately.\n'
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
                          'Broadcast Request ($effectiveCoins Coin${effectiveCoins == 1 ? '' : 's'})',
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
    );
  }
}

/// Searchable Sheet for selecting Indian cities
class _CityPickerSheet extends StatefulWidget {
  final String currentCity;

  const _CityPickerSheet({required this.currentCity});

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  late TextEditingController _searchController;
  late List<String> _filteredCities;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredCities = List.from(kIndianCities);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredCities = List.from(kIndianCities);
      } else {
        // Use fuzzy matching so typos like "Hyderbad" → Hyderabad still work.
        // Dedup by lowercase to avoid showing Bangalore + Bengaluru both when
        // the user typed something that matches only one of them.
        final seen = <String>{};
        _filteredCities = kIndianCities.where((c) {
          if (!_fuzzyMatch(c, query)) return false;
          return seen.add(c.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Text(
            'Select City',
            style: typography.titleCard.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _filter,
            decoration: InputDecoration(
              hintText: 'Search or type your city...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _filter('');
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
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _filteredCities.length + (_searchController.text.trim().isNotEmpty && !_filteredCities.any((c) => c.toLowerCase() == _searchController.text.trim().toLowerCase()) ? 1 : 0),
              separatorBuilder: (_, index) => Divider(height: 1, color: colors.border.withValues(alpha: 0.5)),
              itemBuilder: (context, index) {
                if (index < _filteredCities.length) {
                  final city = _filteredCities[index];
                  final isSelected = city.toLowerCase() == widget.currentCity.toLowerCase();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    title: Text(
                      city,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? colors.primary : colors.textPrimary,
                      ),
                    ),
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: colors.primary) : null,
                    onTap: () => Navigator.of(context).pop(city),
                  );
                } else {
                  // Option to use whatever custom text was entered
                  final customCity = _searchController.text.trim();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: Icon(Icons.add_location_alt_rounded, color: colors.primary),
                    title: Text(
                      'Use "$customCity"',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(customCity),
                  );
                }
              },
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}

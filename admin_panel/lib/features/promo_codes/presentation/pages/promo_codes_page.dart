import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../services/api_service.dart';
import '../../../../theme/admin_colors.dart';
import '../../data/promo_code_model.dart';

class PromoCodesPage extends StatefulWidget {
  const PromoCodesPage({super.key});

  @override
  State<PromoCodesPage> createState() => _PromoCodesPageState();
}

class _PromoCodesPageState extends State<PromoCodesPage> {
  List<PromoCode> _promos = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPromoCodes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPromoCodes() async {
    setState(() => _isLoading = true);
    try {
      final query = _searchQuery.isNotEmpty ? {'search': _searchQuery} : null;
      final res = await ApiService.get('/promo-codes', queryParams: query);
      if (res['success'] == true && res['promoCodes'] is List) {
        final list = (res['promoCodes'] as List)
            .map((item) => PromoCode.fromJson(item))
            .toList();
        if (mounted) {
          setState(() {
            _promos = list;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load promo codes: $e'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleStatus(PromoCode promo) async {
    try {
      final updatedStatus = !promo.isActive;
      final res = await ApiService.patch(
        '/promo-codes/${promo.id}',
        body: {'isActive': updatedStatus},
      );
      if (res['success'] == true) {
        setState(() {
          final index = _promos.indexWhere((p) => p.id == promo.id);
          if (index != -1) {
            _promos[index] = PromoCode.fromJson(res['promo']);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Promo code "${promo.code}" is now ${updatedStatus ? "Active" : "Inactive"}',
              ),
              backgroundColor: AdminColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: AdminColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _deletePromo(PromoCode promo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        title: const Text('Delete Promo Code', style: TextStyle(color: AdminColors.textPrimary)),
        content: Text(
          'Are you sure you want to permanently delete code "${promo.code}"?',
          style: const TextStyle(color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final res = await ApiService.delete('/promo-codes/${promo.id}');
        if (res['success'] == true) {
          setState(() {
            _promos.removeWhere((p) => p.id == promo.id);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Promo code deleted successfully'),
                backgroundColor: AdminColors.success,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: AdminColors.danger,
            ),
          );
        }
      }
    }
  }

  void _openCreateOrEditDialog([PromoCode? existing]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromoCodeFormDialog(
        existingPromo: existing,
        onSaved: () => _fetchPromoCodes(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _promos.where((p) => p.isActive).length;
    final totalRedemptions = _promos.fold<int>(0, (sum, p) => sum + p.timesRedeemed);
    final iapOffersCount = _promos.where((p) => p.rewardType == 'GOOGLE_PLAY_OFFER').length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Promo Codes & Discounts',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Manage Google Play subscription offers, coin giveaways & campaign codes',
                    style: TextStyle(
                      fontSize: 14,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openCreateOrEditDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  'Create Promo Code',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stat Cards Row
          Row(
            children: [
              _buildStatCard('Active Codes', '$activeCount', Icons.local_offer_rounded, AdminColors.primary),
              const SizedBox(width: 16),
              _buildStatCard('Total Claims', '$totalRedemptions', Icons.celebration_rounded, AdminColors.success),
              const SizedBox(width: 16),
              _buildStatCard('Google Play Offers', '$iapOffersCount', Icons.shopping_bag_rounded, const Color(0xFF3B82F6)),
            ],
          ),
          const SizedBox(height: 24),

          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AdminColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search promo code or campaign title...',
                      hintStyle: const TextStyle(color: AdminColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.textSecondary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AdminColors.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                _fetchPromoCodes();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AdminColors.surfaceMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (val) {
                      setState(() => _searchQuery = val.trim());
                      _fetchPromoCodes();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _fetchPromoCodes,
                  icon: const Icon(Icons.refresh_rounded, color: AdminColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Promo Codes Table Container
          Container(
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
            ),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : _promos.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(48.0),
                        child: Center(
                          child: Column(
                            children: const [
                              Icon(Icons.discount_outlined, size: 48, color: AdminColors.textSecondary),
                              SizedBox(height: 12),
                              Text(
                                'No promo codes found',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Create your first promo code above.',
                                style: TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(AdminColors.surfaceMuted),
                            columnSpacing: 24,
                            columns: const [
                              DataColumn(label: Text('CODE', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('CAMPAIGN / TITLE', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('TYPE', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('OFFER / BENEFIT', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('REDEMPTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('EXPIRES', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                              DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textSecondary))),
                            ],
                            rows: _promos.map((promo) {
                              final isExpired = promo.expiresAt.isBefore(DateTime.now());
                              return DataRow(
                                cells: [
                                  // Code
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AdminColors.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AdminColors.primary.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            promo.code,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AdminColors.primary,
                                              letterSpacing: 0.5,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 16, color: AdminColors.textSecondary),
                                          tooltip: 'Copy Code',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: promo.code));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Copied "${promo.code}" to clipboard!')),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Campaign
                                  DataCell(
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          promo.title,
                                          style: const TextStyle(fontWeight: FontWeight.w600, color: AdminColors.textPrimary, fontSize: 13),
                                        ),
                                        if (promo.description != null && promo.description!.isNotEmpty)
                                          Text(
                                            promo.description!,
                                            style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Type
                                  DataCell(_buildTypeBadge(promo.rewardType)),
                                  // Benefit
                                  DataCell(_buildBenefitLabel(promo)),
                                  // Redemptions
                                  DataCell(
                                    Text(
                                      promo.maxUsesTotal != null
                                          ? '${promo.timesRedeemed} / ${promo.maxUsesTotal}'
                                          : '${promo.timesRedeemed} (unlimited)',
                                      style: const TextStyle(fontWeight: FontWeight.w500, color: AdminColors.textPrimary),
                                    ),
                                  ),
                                  // Expiry
                                  DataCell(
                                    Text(
                                      DateFormat('dd MMM yyyy').format(promo.expiresAt),
                                      style: TextStyle(
                                        color: isExpired ? AdminColors.danger : AdminColors.textSecondary,
                                        fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  // Status Toggle
                                  DataCell(
                                    Switch(
                                      value: promo.isActive && !isExpired,
                                      activeThumbColor: AdminColors.success,
                                      onChanged: isExpired ? null : (_) => _toggleStatus(promo),
                                    ),
                                  ),
                                  // Actions
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_rounded, size: 18, color: AdminColors.primary),
                                          tooltip: 'Edit',
                                          onPressed: () => _openCreateOrEditDialog(promo),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AdminColors.danger),
                                          tooltip: 'Delete',
                                          onPressed: () => _deletePromo(promo),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color bg;
    Color fg;
    String label;

    switch (type) {
      case 'GOOGLE_PLAY_OFFER':
        bg = const Color(0xFF3B82F6).withValues(alpha: 0.15);
        fg = const Color(0xFF3B82F6);
        label = 'Play Offer';
        break;
      case 'FREE_COINS':
        bg = Colors.amber.withValues(alpha: 0.15);
        fg = Colors.amber.shade800;
        label = 'Free Coins';
        break;
      case 'FREE_VIP':
        bg = Colors.purple.withValues(alpha: 0.15);
        fg = Colors.purple.shade700;
        label = 'Free VIP';
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade700;
        label = type;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildBenefitLabel(PromoCode promo) {
    if (promo.rewardType == 'GOOGLE_PLAY_OFFER') {
      return Text(
        '₹${promo.discountAmount.toStringAsFixed(0)} OFF (${promo.googlePlayOfferId ?? "offer"})',
        style: const TextStyle(fontWeight: FontWeight.w600, color: AdminColors.textPrimary, fontSize: 13),
      );
    } else if (promo.rewardType == 'FREE_COINS') {
      return Text(
        '+${promo.coinsReward} Coins',
        style: const TextStyle(fontWeight: FontWeight.w600, color: AdminColors.textPrimary, fontSize: 13),
      );
    } else if (promo.rewardType == 'FREE_VIP') {
      return Text(
        '+${promo.vipDaysReward} Days VIP',
        style: const TextStyle(fontWeight: FontWeight.w600, color: AdminColors.textPrimary, fontSize: 13),
      );
    }
    return const Text('—');
  }
}

// ── Dialog: Create / Edit Promo Code ─────────────────────────────────────────

class _PromoCodeFormDialog extends StatefulWidget {
  final PromoCode? existingPromo;
  final VoidCallback onSaved;

  const _PromoCodeFormDialog({
    this.existingPromo,
    required this.onSaved,
  });

  @override
  State<_PromoCodeFormDialog> createState() => _PromoCodeFormDialogState();
}

class _PromoCodeFormDialogState extends State<_PromoCodeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _offerIdCtrl;
  late TextEditingController _discountAmountCtrl;
  late TextEditingController _coinsRewardCtrl;
  late TextEditingController _vipDaysCtrl;
  late TextEditingController _maxUsesTotalCtrl;
  late TextEditingController _maxUsesPerUserCtrl;

  String _rewardType = 'GOOGLE_PLAY_OFFER';
  String _targetProductId = 'pass_1_month';
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 30));
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPromo;
    _codeCtrl = TextEditingController(text: p?.code ?? '');
    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _offerIdCtrl = TextEditingController(text: p?.googlePlayOfferId ?? '50-off');
    _discountAmountCtrl = TextEditingController(text: p?.discountAmount.toStringAsFixed(0) ?? '50');
    _coinsRewardCtrl = TextEditingController(text: p?.coinsReward.toString() ?? '50');
    _vipDaysCtrl = TextEditingController(text: p?.vipDaysReward.toString() ?? '7');
    _maxUsesTotalCtrl = TextEditingController(text: p?.maxUsesTotal?.toString() ?? '');
    _maxUsesPerUserCtrl = TextEditingController(text: p?.maxUsesPerUser.toString() ?? '1');

    if (p != null) {
      _rewardType = p.rewardType;
      _targetProductId = p.targetProductId ?? 'pass_1_month';
      _expiresAt = p.expiresAt;
      _isActive = p.isActive;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _offerIdCtrl.dispose();
    _discountAmountCtrl.dispose();
    _coinsRewardCtrl.dispose();
    _vipDaysCtrl.dispose();
    _maxUsesTotalCtrl.dispose();
    _maxUsesPerUserCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final payload = {
      'code': _codeCtrl.text.trim().toUpperCase(),
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'rewardType': _rewardType,
      'targetProductId': _rewardType == 'GOOGLE_PLAY_OFFER' ? _targetProductId : null,
      'googlePlayOfferId': _rewardType == 'GOOGLE_PLAY_OFFER' ? _offerIdCtrl.text.trim() : null,
      'discountAmount': _rewardType == 'GOOGLE_PLAY_OFFER' ? double.tryParse(_discountAmountCtrl.text) ?? 50 : 0,
      'coinsReward': _rewardType == 'FREE_COINS' ? int.tryParse(_coinsRewardCtrl.text) ?? 0 : 0,
      'vipDaysReward': _rewardType == 'FREE_VIP' ? int.tryParse(_vipDaysCtrl.text) ?? 0 : 0,
      'maxUsesTotal': _maxUsesTotalCtrl.text.isNotEmpty ? int.tryParse(_maxUsesTotalCtrl.text) : null,
      'maxUsesPerUser': int.tryParse(_maxUsesPerUserCtrl.text) ?? 1,
      'expiresAt': _expiresAt.toIso8601String(),
      'isActive': _isActive,
    };

    try {
      if (widget.existingPromo == null) {
        final res = await ApiService.post('/promo-codes', body: payload);
        if (res['success'] == true) {
          if (!mounted) return;
          Navigator.of(context).pop();
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Promo code created successfully!'), backgroundColor: AdminColors.success),
          );
        }
      } else {
        final res = await ApiService.patch('/promo-codes/${widget.existingPromo!.id}', body: payload);
        if (res['success'] == true) {
          if (!mounted) return;
          Navigator.of(context).pop();
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Promo code updated successfully!'), backgroundColor: AdminColors.success),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving promo: $e'), backgroundColor: AdminColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingPromo != null;

    return Dialog(
      backgroundColor: AdminColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Edit Promo Code' : 'Create New Promo Code',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AdminColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Scrollable Form Body
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Code Input
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _codeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AdminColors.primary),
                              decoration: InputDecoration(
                                labelText: 'Promo Code *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Code required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _titleCtrl,
                              style: const TextStyle(color: AdminColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Campaign Title *',
                                hintText: 'e.g. Flat ₹50 OFF on 1 Month Pass',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Title required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descCtrl,
                        style: const TextStyle(color: AdminColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Internal note or user badge details',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reward Type Selection
                      DropdownButtonFormField<String>(
                        initialValue: _rewardType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Promo Reward Type *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        dropdownColor: AdminColors.surface,
                        items: const [
                          DropdownMenuItem(
                            value: 'GOOGLE_PLAY_OFFER',
                            child: Text('Google Play Subscription Offer (₹ Discount)', overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'FREE_COINS',
                            child: Text('Free Spendable Coins (Added to Wallet)', overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'FREE_VIP',
                            child: Text('Free VIP Membership Pass (Days)', overflow: TextOverflow.ellipsis),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _rewardType = val);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Dynamic Fields based on Type
                      if (_rewardType == 'GOOGLE_PLAY_OFFER') ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _targetProductId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Target Plan / Coin Pack',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                dropdownColor: AdminColors.surface,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'plan_99',
                                    child: Text('99 Coins Pack (plan_99)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'plan_49',
                                    child: Text('49 Coins Pack (plan_49)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'plan_199',
                                    child: Text('199 Coins Pack (plan_199)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'plan_499',
                                    child: Text('549 Coins Pack (plan_499)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'plan_999',
                                    child: Text('1099 Coins Pack (plan_999)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'plan_2500',
                                    child: Text('2750 Coins Pack (plan_2500)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pass_1_month',
                                    child: Text('1 Month Pass (pass_1_month)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pass_6_months',
                                    child: Text('6 Months Pass (pass_6_months)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pass_1_year',
                                    child: Text('1 Year Pass (pass_1_year)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Plans & Packs (all)', overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _targetProductId = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _offerIdCtrl,
                                style: const TextStyle(color: AdminColors.textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Google Play Offer ID *',
                                  hintText: 'e.g. 50-off',
                                  helperText: 'Matches Offer ID in Play Console',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                validator: (val) => val == null || val.trim().isEmpty ? 'Offer ID required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _discountAmountCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AdminColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Discount Amount (₹) *',
                            hintText: '50',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ] else if (_rewardType == 'FREE_COINS') ...[
                        TextFormField(
                          controller: _coinsRewardCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AdminColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Free Coins Amount *',
                            hintText: 'e.g. 50',
                            helperText: 'Strictly credited to spendable_balance (non-withdrawable)',
                            prefixIcon: const Icon(Icons.monetization_on_rounded, color: Colors.amber),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ] else if (_rewardType == 'FREE_VIP') ...[
                        TextFormField(
                          controller: _vipDaysCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AdminColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Free VIP Days *',
                            hintText: 'e.g. 7',
                            helperText: 'Unlocks unlimited calling access for X days',
                            prefixIcon: const Icon(Icons.workspace_premium_rounded, color: Colors.purple),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Limits & Expiry
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _maxUsesTotalCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AdminColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Total Max Claims (Optional)',
                                hintText: 'Leave empty for unlimited',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _maxUsesPerUserCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: AdminColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Claims Per User',
                                hintText: '1',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Expiry Picker Row
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.calendar_today_rounded, size: 18),
                              label: Text('Expires: ${DateFormat("dd MMM yyyy").format(_expiresAt)}'),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _expiresAt,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Row(
                            children: [
                              const Text('Active:', style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textPrimary)),
                              Switch(
                                value: _isActive,
                                activeThumbColor: AdminColors.success,
                                onChanged: (val) => setState(() => _isActive = val),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Pinned Actions
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isEdit ? 'Save Changes' : 'Create Code'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

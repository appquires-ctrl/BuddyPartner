import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme/admin_colors.dart';
import '../../theme/admin_theme.dart';
import '../../providers/admin_providers.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(usersProvider);
    final usersNotifier = ref.read(usersProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'User Management',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Search users, manage coin balances, grant 1-year VIP subscriptions, and handle moderation',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => usersNotifier.fetchUsers(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.surface,
                  foregroundColor: AdminColors.primary,
                  side: const BorderSide(color: AdminColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filters Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Search Input Field
                SizedBox(
                  width: 260,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      hintStyle: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AdminColors.textSecondary),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                usersNotifier.setSearch('');
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: AdminColors.surfaceMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onSubmitted: (val) {
                      usersNotifier.setSearch(val.trim());
                      setState(() {});
                    },
                  ),
                ),

                // Gender Filter Dropdown
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Gender: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AdminColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: usersState.gender,
                          style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Genders')),
                            DropdownMenuItem(value: 'male', child: Text('Male')),
                            DropdownMenuItem(value: 'female', child: Text('Female')),
                          ],
                          onChanged: (val) {
                            if (val != null) usersNotifier.setGender(val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                // Status Filter Dropdown
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Status: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AdminColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: usersState.isBanned,
                          style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                            DropdownMenuItem(value: 'false', child: Text('Active Only')),
                            DropdownMenuItem(value: 'true', child: Text('Banned Only')),
                          ],
                          onChanged: (val) {
                            if (val != null) usersNotifier.setIsBanned(val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                // Total Count
                Text(
                  'Total Users: ${usersState.total}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Users Full-Width Table Container
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: usersState.isLoading
                ? const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : usersState.users.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(48),
                        alignment: Alignment.center,
                        child: Column(
                          children: const [
                            Icon(Icons.person_search_rounded, size: 48, color: AdminColors.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'No users match the criteria',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth > 1150 ? constraints.maxWidth : 1150.0;
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: width,
                                  child: Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(2.6), // USER
                                      1: FlexColumnWidth(1.2), // GENDER
                                      2: FlexColumnWidth(2.0), // PHONE / EMAIL
                                      3: FlexColumnWidth(1.8), // COINS
                                      4: FlexColumnWidth(1.6), // MEMBERSHIP
                                      5: FlexColumnWidth(1.2), // STATUS
                                      6: FlexColumnWidth(3.4), // ACTIONS
                                    },
                                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                    children: [
                                      // Table Header
                                      TableRow(
                                        decoration: const BoxDecoration(
                                          color: AdminColors.surfaceMuted,
                                        ),
                                        children: [
                                          _buildHeaderCell('USER'),
                                          _buildHeaderCell('GENDER'),
                                          _buildHeaderCell('PHONE / EMAIL'),
                                          _buildHeaderCell('COINS (S / E)'),
                                          _buildHeaderCell('MEMBERSHIP'),
                                          _buildHeaderCell('STATUS'),
                                          _buildHeaderCell('ACTIONS'),
                                        ],
                                      ),

                                      // Data Rows
                                      ...usersState.users.map((user) {
                                        final isBanned = user['is_banned'] == true;
                                        final name = user['name'] ?? 'Unknown User';
                                        final phone = user['phone'] ?? user['email'] ?? 'N/A';
                                        final gender = (user['gender'] ?? 'N/A').toString().toUpperCase();
                                        final coinBalance = user['coin_balance'] ?? 0;
                                        final spendableBalance = user['spendable_balance'] ?? 0;
                                        final earnedBalance = user['earned_balance'] ?? 0;
                                        final isSubscribed = user['is_subscribed'] == true;
                                        final expiresAtStr = user['subscription_expires_at'] as String?;
                                        String? expiryFormatted;
                                        if (expiresAtStr != null) {
                                          try {
                                            expiryFormatted = DateFormat('MMM dd, yyyy').format(DateTime.parse(expiresAtStr));
                                          } catch (_) {}
                                        }

                                        return TableRow(
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: AdminColors.border, width: 1)),
                                          ),
                                          children: [
                                            // USER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 15,
                                                    backgroundColor: AdminColors.activePillBg,
                                                    child: Text(
                                                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AdminColors.primary, fontSize: 12),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // GENDER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: gender == 'FEMALE' ? const Color(0xFFFCE7F3) : const Color(0xFFEFF6FF),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    gender,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: gender == 'FEMALE' ? const Color(0xFFDB2777) : const Color(0xFF2563EB),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // PHONE / EMAIL
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(
                                                phone,
                                                style: AdminTheme.tabularNumeralStyle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),

                                            // COINS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.monetization_on_rounded, size: 16, color: Color(0xFFF59E0B)),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '$coinBalance',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                          color: AdminColors.textPrimary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${spendableBalance}s • ${earnedBalance}e',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: AdminColors.textSecondary,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // MEMBERSHIP
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: isSubscribed
                                                    ? Tooltip(
                                                        message: expiryFormatted != null ? 'VIP valid until $expiryFormatted' : 'VIP Active',
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            gradient: const LinearGradient(
                                                              colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                                                            ),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: const [
                                                              Icon(Icons.workspace_premium_rounded, size: 13, color: Colors.white),
                                                              SizedBox(width: 4),
                                                              Text(
                                                                '1-YR VIP',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Colors.white,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      )
                                                    : Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: AdminColors.surfaceMuted,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: const Text(
                                                          'Free',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: AdminColors.textSecondary,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ),

                                            // STATUS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isBanned ? AdminColors.dangerBg : AdminColors.successBg,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    isBanned ? 'BANNED' : 'ACTIVE',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isBanned ? AdminColors.danger : AdminColors.success,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // ACTIONS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  // Give Coins Button
                                                  OutlinedButton.icon(
                                                    onPressed: () => _showGiveCoinsDialog(context, ref, user),
                                                    icon: const Icon(Icons.add_circle_outline_rounded, size: 14, color: Color(0xFFD97706)),
                                                    label: const Text('Coins', style: TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                                                    style: OutlinedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      side: const BorderSide(color: Color(0xFFFCD34D)),
                                                      backgroundColor: const Color(0xFFFFFBEB),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                  ),
                                                  // Give 1-Year Sub Button
                                                  OutlinedButton.icon(
                                                    onPressed: () => _showGiveSubscriptionDialog(context, ref, user),
                                                    icon: const Icon(Icons.star_rounded, size: 14, color: Color(0xFF7C3AED)),
                                                    label: const Text('1-Yr VIP', style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
                                                    style: OutlinedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      side: const BorderSide(color: Color(0xFFDDD6FE)),
                                                      backgroundColor: const Color(0xFFF5F3FF),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                  ),
                                                  // Detail Button
                                                  OutlinedButton(
                                                    onPressed: () => _showUserDetailDialog(context, ref, user),
                                                    style: OutlinedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      side: const BorderSide(color: AdminColors.border),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    child: const Text('Detail', style: TextStyle(fontSize: 11)),
                                                  ),
                                                  // Ban / Unban Button
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      final success = await usersNotifier.toggleBan(user['id'], isBanned);
                                                      if (context.mounted && success) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text(isBanned ? 'User unbanned' : 'User banned'),
                                                            backgroundColor: isBanned ? AdminColors.success : AdminColors.danger,
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: isBanned ? AdminColors.success : AdminColors.danger,
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                      elevation: 0,
                                                    ),
                                                    child: Text(isBanned ? 'Unban' : 'Ban', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          // Pagination Controls
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Page ${usersState.page} of ${usersState.totalPages}',
                                  style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left_rounded),
                                      onPressed: usersState.page > 1
                                          ? () => usersNotifier.setPage(usersState.page - 1)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right_rounded),
                                      onPressed: usersState.page < usersState.totalPages
                                          ? () => usersNotifier.setPage(usersState.page + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textSecondary),
      ),
    );
  }

  // ── Give Coins Dialog ──────────────────────────────────────────────────────
  void _showGiveCoinsDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> user) {
    final amountController = TextEditingController(text: '100');
    final userId = user['id'] as String;
    final userName = user['name'] ?? 'User';
    final currentCoins = user['coin_balance'] ?? 0;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.monetization_on_rounded, color: Color(0xFFF59E0B), size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Give Coins',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recipient: $userName (Current Balance: $currentCoins coins)',
                      style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                    ),
                    const Divider(height: 24),
                    const Text('Quick Select Amount:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [50, 100, 500, 1000, 5000].map((amt) {
                        final isSelected = amountController.text == amt.toString();
                        return ActionChip(
                          label: Text('+$amt'),
                          backgroundColor: isSelected ? const Color(0xFFFEF3C7) : AdminColors.surfaceMuted,
                          side: BorderSide(
                            color: isSelected ? const Color(0xFFF59E0B) : AdminColors.border,
                          ),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isSelected ? const Color(0xFFB45309) : AdminColors.textPrimary,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              amountController.text = amt.toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Custom Amount:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.add_rounded, size: 18),
                        hintText: 'Enter coins to grant',
                        filled: true,
                        fillColor: AdminColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final amount = int.tryParse(amountController.text.trim());
                                  if (amount == null || amount <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please enter a valid positive number')),
                                    );
                                    return;
                                  }

                                  setDialogState(() => isSubmitting = true);
                                  final success = await ref.read(usersProvider.notifier).giveCoins(userId, amount);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(success ? 'Successfully credited $amount coins to $userName!' : 'Failed to credit coins'),
                                        backgroundColor: success ? AdminColors.success : AdminColors.danger,
                                      ),
                                    );
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(isSubmitting ? 'Granting...' : 'Confirm & Give Coins'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Give 1-Year VIP Subscription Dialog ──────────────────────────────────
  void _showGiveSubscriptionDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> user) {
    final userId = user['id'] as String;
    final userName = user['name'] ?? 'User';
    final isSubscribed = user['is_subscribed'] == true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.workspace_premium_rounded, color: Color(0xFF8B5CF6), size: 26),
                            SizedBox(width: 8),
                            Text(
                              'Grant 1-Year VIP Pass',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Target User: $userName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSubscribed
                          ? 'This user already has an active subscription. Granting 1 year will stack an additional 365 days onto their current expiration date.'
                          : 'This user currently has no active subscription. Granting 1 year will immediately activate VIP membership for 365 days.',
                      style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.verified_rounded, color: Color(0xFF7C3AED), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Duration: 365 Days (1 Year)\nBenefits: Unlimited Audio/Video Connects & VIP Features',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5B21B6)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  setDialogState(() => isSubmitting = true);
                                  final success = await ref.read(usersProvider.notifier).giveSubscription(userId, durationDays: 365);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(success ? 'Successfully granted 1-Year VIP to $userName!' : 'Failed to grant subscription'),
                                        backgroundColor: success ? AdminColors.success : AdminColors.danger,
                                      ),
                                    );
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.star_rounded, size: 16),
                          label: Text(isSubmitting ? 'Granting...' : 'Confirm & Grant 1-Year VIP'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── User Detail Dialog ─────────────────────────────────────────────────────
  void _showUserDetailDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> userSummary) {
    final userId = userSummary['id'] as String;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 540,
            padding: const EdgeInsets.all(24),
            child: Consumer(
              builder: (context, ref, child) {
                final detailAsync = ref.watch(userDetailProvider(userId));
                return detailAsync.when(
                  data: (user) {
                    if (user == null) return const Text('User not found');
                    final reports = user['reports'] as List<dynamic>? ?? [];
                    final callStats = user['callStats'] as Map<String, dynamic>? ?? {};
                    final coinBal = user['coinBalance'] ?? userSummary['coin_balance'] ?? 0;
                    final activeSub = user['activeSubscription'] as Map<String, dynamic>?;
                    final isSub = activeSub != null;
                    String subExpiry = 'N/A';
                    if (activeSub != null && activeSub['expires_at'] != null) {
                      try {
                        subExpiry = DateFormat('MMM dd, yyyy').format(DateTime.parse(activeSub['expires_at']));
                      } catch (_) {}
                    }

                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                user['name'] ?? 'User Details',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                          const Divider(),
                          const SizedBox(height: 8),

                          // Basic Info
                          Text('Phone: ${user['phone'] ?? 'N/A'}', style: AdminTheme.tabularNumeralStyle),
                          const SizedBox(height: 4),
                          Text('Gender: ${user['gender'] ?? 'N/A'}'),
                          const SizedBox(height: 4),
                          Text('Status: ${user['is_banned'] == true ? 'BANNED' : 'ACTIVE'}'),
                          const SizedBox(height: 16),

                          // Wallet & Subscription Card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AdminColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AdminColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Wallet & Membership',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textPrimary),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.monetization_on_rounded, size: 18, color: Color(0xFFF59E0B)),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Balance: $coinBal coins',
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFBFDBFE)),
                                              ),
                                              child: Text(
                                                'Spendable: ${user['spendableBalance'] ?? userSummary['spendable_balance'] ?? 0}',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFECFDF5),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFA7F3D0)),
                                              ),
                                              child: Text(
                                                'Earned: ${user['earnedBalance'] ?? userSummary['earned_balance'] ?? 0}',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _showGiveCoinsDialog(context, ref, {...userSummary, 'coin_balance': coinBal});
                                      },
                                      icon: const Icon(Icons.add_rounded, size: 14),
                                      label: const Text('+ Give Coins', style: TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFF59E0B),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.workspace_premium_rounded,
                                          size: 18,
                                          color: isSub ? const Color(0xFF7C3AED) : AdminColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isSub ? 'VIP Active (Exp: $subExpiry)' : 'Subscription: Free',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: isSub ? const Color(0xFF7C3AED) : AdminColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _showGiveSubscriptionDialog(context, ref, {...userSummary, 'is_subscribed': isSub});
                                      },
                                      icon: const Icon(Icons.star_rounded, size: 14),
                                      label: const Text('Grant 1-Yr VIP', style: TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF7C3AED),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Text('Call Statistics:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Total Calls: ${callStats['total_calls'] ?? 0}'),
                          Text('Total Call Duration: ${callStats['total_duration'] ?? 0}s'),
                          const SizedBox(height: 16),
                          const Text('Report History Against User:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          reports.isEmpty
                              ? const Text('No reports filed against this user.', style: TextStyle(color: AdminColors.textMuted))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: reports.length,
                                  itemBuilder: (context, i) {
                                    final r = reports[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(r['reason'] ?? 'Report', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('By: ${r['reporter_name'] ?? 'Anonymous'} • ${r['description'] ?? ''}'),
                                    );
                                  },
                                ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  error: (e, s) => Text('Error loading user detail: $e'),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

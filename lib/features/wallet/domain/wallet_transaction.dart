class WalletTransaction {
  final String id;
  final int amount;
  final String type; // 'credit' | 'debit'
  final String reason;
  final String reasonLabel;
  final String? referenceId;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.reason,
    required this.reasonLabel,
    this.referenceId,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final rawReason = json['reason'] as String? ?? 'transaction';
    final rawLabel = json['reasonLabel'] as String? ?? rawReason;

    return WalletTransaction(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'credit',
      reason: rawReason,
      reasonLabel: _formatReasonLabel(rawLabel),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)?.toLocal() ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'] as String)?.toLocal() ?? DateTime.now()
              : DateTime.now()),
    );
  }

  static String _formatReasonLabel(String label) {
    final normalized = label.replaceAll('_', ' ').toLowerCase().trim();
    if (normalized.contains('refund')) {
      return 'Call Refund';
    }
    if (normalized.contains('escrow') || normalized.contains('instant call') || normalized.contains('instant connect')) {
      return 'VIP Call';
    }
    if (normalized.contains('recharge') || normalized.contains('purchase') || normalized.contains('buy')) {
      return 'Coins Added';
    }
    if (normalized.contains('bonus')) {
      return 'Daily Bonus';
    }
    if (normalized.contains('scratch')) {
      return 'Scratch Reward';
    }
    if (normalized.contains('withdraw')) {
      return 'Withdrawal';
    }

    // Capitalize simple word
    return label.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  bool get isCredit => type.toLowerCase() == 'credit';
  bool get isDebit => type.toLowerCase() == 'debit';
}

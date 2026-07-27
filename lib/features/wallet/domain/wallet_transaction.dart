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
    return WalletTransaction(
      id: json['id'] as String,
      amount: (json['amount'] as num).toInt(),
      type: json['type'] as String,
      reason: json['reason'] as String? ?? 'transaction',
      reasonLabel: json['reasonLabel'] as String? ?? json['reason'] as String? ?? 'Transaction',
      referenceId: json['referenceId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

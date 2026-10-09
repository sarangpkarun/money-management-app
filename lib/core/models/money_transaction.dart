import 'package:cloud_firestore/cloud_firestore.dart';

import '../money/money.dart';
import '../status/transaction_status.dart';

enum TransactionType { lent, borrowed, emi, instalment }

enum InterestType { none, simple, compound }

class MoneyTransaction {
  const MoneyTransaction({
    this.id = '',
    required this.type,
    required this.personId,
    required this.personName,
    required this.title,
    required this.totalAmount,
    this.paidTotal = Money.zero,
    this.status = TransactionStatus.pending,
    this.dueDate,
    this.interestType = InterestType.none,
    this.interestRate,
    required this.createdAt,
    this.settledAt,
  });

  final String id;
  final TransactionType type;
  final String personId;
  final String personName;
  final String title;
  final Money totalAmount;
  final Money paidTotal;
  final TransactionStatus status;
  final DateTime? dueDate;
  final InterestType interestType;
  final double? interestRate;
  final DateTime createdAt;
  final DateTime? settledAt;

  Money get balance => totalAmount - paidTotal;

  /// `lent` money is owed to the user; everything else is owed by the user.
  bool get isReceivable => type == TransactionType.lent;

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'personId': personId,
    'personName': personName,
    'title': title,
    'totalAmount': totalAmount.paise,
    'paidTotal': paidTotal.paise,
    'balance': balance.paise,
    'status': status.name,
    'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
    'interestType': interestType.name,
    'interestRate': interestRate,
    'createdAt': Timestamp.fromDate(createdAt),
    'settledAt': settledAt == null ? null : Timestamp.fromDate(settledAt!),
  };

  factory MoneyTransaction.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(String k) => (m[k] as Timestamp?)?.toDate();
    return MoneyTransaction(
      id: id,
      type: TransactionType.values.byName(m['type'] as String),
      personId: m['personId'] as String,
      personName: m['personName'] as String,
      title: m['title'] as String,
      totalAmount: Money(m['totalAmount'] as int),
      paidTotal: Money(m['paidTotal'] as int),
      status: TransactionStatus.values.byName(m['status'] as String),
      dueDate: ts('dueDate'),
      interestType: InterestType.values.byName(m['interestType'] as String),
      interestRate: (m['interestRate'] as num?)?.toDouble(),
      createdAt: ts('createdAt')!,
      settledAt: ts('settledAt'),
    );
  }
}

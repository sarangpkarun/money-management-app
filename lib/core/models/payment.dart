import 'package:cloud_firestore/cloud_firestore.dart';

import '../money/money.dart';

enum PaymentMode { cash, upi, bank, card }

class Payment {
  const Payment({
    this.id = '',
    required this.amount,
    required this.date,
    this.mode = PaymentMode.cash,
    this.note,
    this.screenshotUrl,
    this.createdAt,
  });

  final String id;
  final Money amount;
  final DateTime date;
  final PaymentMode mode;
  final String? note;
  final String? screenshotUrl;

  /// When the payment was recorded (separate from the day it was made).
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
    'amount': amount.paise,
    'date': Timestamp.fromDate(date),
    'mode': mode.name,
    'note': note,
    'screenshotUrl': screenshotUrl,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
  };

  factory Payment.fromMap(String id, Map<String, dynamic> m) => Payment(
    id: id,
    amount: Money(m['amount'] as int),
    date: (m['date'] as Timestamp).toDate(),
    mode: PaymentMode.values.byName(m['mode'] as String),
    note: m['note'] as String?,
    screenshotUrl: m['screenshotUrl'] as String?,
    createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
  );
}

/// The most recent payment: latest payment date, then the one recorded last.
/// Null when there are none.
Payment? latestPayment(List<Payment> payments) {
  if (payments.isEmpty) return null;
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final sorted = [...payments]
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byCreated = (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  return sorted.last;
}

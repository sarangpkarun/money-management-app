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
  });

  final String id;
  final Money amount;
  final DateTime date;
  final PaymentMode mode;
  final String? note;
  final String? screenshotUrl;

  Map<String, dynamic> toMap() => {
    'amount': amount.paise,
    'date': Timestamp.fromDate(date),
    'mode': mode.name,
    'note': note,
    'screenshotUrl': screenshotUrl,
  };

  factory Payment.fromMap(String id, Map<String, dynamic> m) => Payment(
    id: id,
    amount: Money(m['amount'] as int),
    date: (m['date'] as Timestamp).toDate(),
    mode: PaymentMode.values.byName(m['mode'] as String),
    note: m['note'] as String?,
    screenshotUrl: m['screenshotUrl'] as String?,
  );
}

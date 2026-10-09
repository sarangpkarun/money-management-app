import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/money_transaction.dart';
import '../core/models/payment.dart';

final transactionProvider = StreamProvider.family<MoneyTransaction?, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).watchOne(id),
);

final paymentsProvider = StreamProvider.family<List<Payment>, String>(
  (ref, id) => ref.watch(paymentRepositoryProvider).watch(id),
);

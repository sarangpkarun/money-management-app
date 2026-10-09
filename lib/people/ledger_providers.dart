import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transactions/transaction_providers.dart';
import 'ledger.dart';
import 'people_providers.dart';

/// A person's ledger, built from their transactions and each one's payments.
/// Loading until every stream has delivered its first value.
final personLedgerProvider =
    Provider.family<AsyncValue<List<LedgerEvent>>, String>((ref, personId) {
      final txns = ref.watch(allTransactionsProvider);
      if (txns.hasError) return AsyncError(txns.error!, txns.stackTrace!);
      if (!txns.hasValue) return const AsyncLoading();

      final items = <TransactionWithPayments>[];
      for (final t in txns.requireValue.where((t) => t.personId == personId)) {
        final payments = ref.watch(paymentsProvider(t.id));
        if (payments.hasError) {
          return AsyncError(payments.error!, payments.stackTrace!);
        }
        if (!payments.hasValue) return const AsyncLoading();
        items.add(TransactionWithPayments(t, payments.requireValue));
      }
      return AsyncData(buildLedger(items, now: DateTime.now()));
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/money_transaction.dart';
import '../core/models/person.dart';
import 'person_summary.dart';

final peopleProvider = StreamProvider<List<Person>>(
  (ref) => ref.watch(peopleRepositoryProvider).watch(),
);

final allTransactionsProvider = StreamProvider<List<MoneyTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watch(),
);

/// People joined with their balances, ready for the list and autocomplete.
final personSummariesProvider = Provider<AsyncValue<List<PersonSummary>>>((
  ref,
) {
  final people = ref.watch(peopleProvider);
  final txns = ref.watch(allTransactionsProvider);
  if (people.hasError) return AsyncError(people.error!, people.stackTrace!);
  if (txns.hasError) return AsyncError(txns.error!, txns.stackTrace!);
  if (!people.hasValue || !txns.hasValue) return const AsyncLoading();
  return AsyncData(
    summarize(people.requireValue, txns.requireValue, now: DateTime.now()),
  );
});

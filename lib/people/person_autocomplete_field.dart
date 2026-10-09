import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/person.dart';
import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/ui/initials_avatar.dart';
import 'people_providers.dart';
import 'person_suggestions.dart';
import 'person_summary.dart';

class _Option {
  const _Option.person(PersonSummary this.summary) : newName = null;
  const _Option.addNew(String this.newName) : summary = null;

  final PersonSummary? summary;
  final String? newName;
}

/// Person field for the Add entry screen: shows recent people when focused,
/// matches saved people as you type (with phone and balance), and offers
/// "Add 'Name' as new person" when nothing matches exactly.
class PersonAutocompleteField extends ConsumerWidget {
  const PersonAutocompleteField({
    super.key,
    required this.onSelected,
    this.label = 'Person',
  });

  /// Called with the chosen person; a newly added person already has its id.
  final ValueChanged<Person> onSelected;
  final String label;

  Iterable<_Option> _options(WidgetRef ref, String text) {
    final all = ref.read(personSummariesProvider).value ?? const [];
    final result = suggestPeople(all, text);
    return [
      for (final m in result.matches) _Option.person(m),
      if (result.showAddNew) _Option.addNew(text.trim()),
    ];
  }

  Future<void> _select(WidgetRef ref, _Option option) async {
    final existing = option.summary;
    if (existing != null) {
      onSelected(existing.person);
      return;
    }
    final draft = Person(name: option.newName!, createdAt: DateTime.now());
    final id = await ref.read(peopleRepositoryProvider).add(draft);
    onSelected(Person(id: id, name: draft.name, createdAt: draft.createdAt));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the people data loaded and live so suggestions are ready on focus.
    ref.watch(personSummariesProvider);
    return Autocomplete<_Option>(
      displayStringForOption: (o) => o.summary?.person.name ?? o.newName!,
      optionsBuilder: (value) => _options(ref, value.text),
      onSelected: (o) => _select(ref, o),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
        );
      },
      optionsViewBuilder: (context, onSelect, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 400),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    _OptionTile(option: o, onTap: () => onSelect(o)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.onTap});

  final _Option option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = option.summary;
    if (s == null) {
      return ListTile(
        leading: const Icon(Icons.person_add_alt_1),
        title: Text("Add '${option.newName}' as new person"),
        onTap: onTap,
      );
    }
    final net = s.net;
    return ListTile(
      leading: InitialsAvatar(name: s.person.name, radius: 16),
      title: Text(s.person.name),
      subtitle: s.person.phone == null ? null : Text(s.person.phone!),
      trailing: net.isZero
          ? null
          : Text(
              Money(net.paise.abs()).format(),
              style: TextStyle(
                color: net.isNegative
                    ? AppColors.pay(context)
                    : AppColors.receive(context),
                fontWeight: FontWeight.w600,
              ),
            ),
      onTap: onTap,
    );
  }
}

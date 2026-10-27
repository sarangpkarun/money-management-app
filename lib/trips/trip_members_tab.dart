import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/person.dart';
import '../core/models/trip.dart';
import '../core/ui/initials_avatar.dart';
import '../people/people_providers.dart';
import '../people/person_form_screen.dart';
import 'trip_providers.dart';

/// Who is on the trip. The owner adds people from their People list (only
/// people with an email), picks Editor or Viewer, and can change or remove
/// them later.
class TripMembersTab extends ConsumerWidget {
  const TripMembersTab({super.key, required this.trip, required this.isOwner});

  final Trip trip;
  final bool isOwner;

  Future<void> _save(WidgetRef ref, List<TripMember> members) => ref
      .read(tripRepositoryProvider)
      .saveMembers(trip.copyWith(members: members));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(emailProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final m in trip.members)
          ListTile(
            leading: InitialsAvatar(name: m.name, radius: 18),
            title: Text(
              m.email.toLowerCase() == me ? '${m.name} (you)' : m.name,
            ),
            subtitle: Text(
              m.pending ? '${m.email} · Invited' : m.email,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: m.role == TripRole.owner || !isOwner
                ? Text(tripRoleLabel(m.role))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<TripRole>(
                        value: m.role,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: TripRole.editor,
                            child: Text('Editor'),
                          ),
                          DropdownMenuItem(
                            value: TripRole.viewer,
                            child: Text('Viewer'),
                          ),
                        ],
                        onChanged: (r) async {
                          if (r == null || r == m.role) return;
                          await _save(ref, [
                            for (final x in trip.members)
                              x == m ? _withRole(x, r) : x,
                          ]);
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () => _remove(context, ref, m),
                      ),
                    ],
                  ),
          ),
        if (isOwner)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _AddMemberSheet(trip: trip),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add people'),
            ),
          ),
        if (!isOwner)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Only the owner can add or remove people.'),
          ),
      ],
    );
  }

  /// Changing a role keeps the member's uid; `copyWith` cannot change a role
  /// and keep a null uid, so build it directly.
  TripMember _withRole(TripMember m, TripRole r) =>
      TripMember(email: m.email, name: m.name, role: r, uid: m.uid);

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    TripMember m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        content: const Text(
          'They lose access to the trip. Expenses they paid or share in '
          'stay, so balances still add up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(ref, [
      for (final x in trip.members)
        if (x != m) x,
    ]);
  }
}

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.trip});

  final Trip trip;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  TripRole _role = TripRole.editor;

  Future<void> _add(Person p) async {
    final trip = ref.read(tripProvider2(widget.trip.id)) ?? widget.trip;
    await ref
        .read(tripRepositoryProvider)
        .saveMembers(
          trip.copyWith(
            members: [
              ...trip.members,
              TripMember(email: p.email!, name: p.name, role: _role),
            ],
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).value ?? const [];
    // Re-read the live trip so people added a moment ago show as added.
    final trip = ref.watch(tripProvider2(widget.trip.id)) ?? widget.trip;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text('Add as'),
                  const SizedBox(width: 12),
                  SegmentedButton<TripRole>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: TripRole.editor,
                        label: Text('Editor'),
                      ),
                      ButtonSegment(
                        value: TripRole.viewer,
                        label: Text('Viewer'),
                      ),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Only people with an email can be added. They see the trip '
                  'when they log in with that email.',
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in people) _tile(context, p, trip),
                  if (people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Add people in the People tab first.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Person p, Trip trip) {
    final email = p.email;
    if (email == null) {
      return ListTile(
        enabled: true,
        leading: InitialsAvatar(name: p.name, radius: 16),
        title: Text(p.name),
        subtitle: const Text('No email'),
        trailing: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PersonFormScreen(person: p),
            ),
          ),
          child: const Text('Add email'),
        ),
      );
    }
    final added = trip.memberByEmail(email) != null;
    return ListTile(
      leading: InitialsAvatar(name: p.name, radius: 16),
      title: Text(p.name),
      subtitle: Text(email),
      trailing: added ? const Icon(Icons.check) : const Icon(Icons.add),
      onTap: added ? null : () => _add(p),
    );
  }
}

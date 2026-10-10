import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// One thing a row can do when swiped.
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTrigger,
  });

  final String label;
  final IconData icon;

  /// The colour behind the swipe. The text on it picks black or white to stay
  /// readable.
  final Color color;
  final Future<void> Function() onTrigger;
}

/// Lets a row be swiped right ([right], from the start edge) and/or left
/// ([left]). The action runs and the row springs back: it leaves the list when
/// the data behind the list changes, so a list built from a live stream never
/// ends up with a dismissed row still on screen.
///
/// Every action is also offered to screen readers as a custom action on the row,
/// so nothing needs the gesture.
class SwipeActions extends StatelessWidget {
  const SwipeActions({super.key, required this.child, this.right, this.left})
    : assert(right != null || left != null);

  final Widget child;
  final SwipeAction? right;
  final SwipeAction? left;

  Widget _background(SwipeAction a, Alignment alignment) {
    final foreground = a.color.computeLuminance() > 0.4
        ? Colors.black87
        : Colors.white;
    return Container(
      color: a.color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(a.icon, color: foreground),
          const SizedBox(width: 8),
          Text(
            a.label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = right;
    final l = left;
    final direction = r != null && l != null
        ? DismissDirection.horizontal
        : (r != null
              ? DismissDirection.startToEnd
              : DismissDirection.endToStart);
    return Dismissible(
      key: key ?? UniqueKey(),
      direction: direction,
      background: r == null ? null : _background(r, Alignment.centerLeft),
      secondaryBackground: l == null
          ? null
          : _background(l, Alignment.centerRight),
      confirmDismiss: (dir) async {
        final action = dir == DismissDirection.startToEnd ? r : l;
        await action?.onTrigger();
        return false;
      },
      child: Semantics(
        customSemanticsActions: {
          if (r != null) CustomSemanticsAction(label: r.label): r.onTrigger,
          if (l != null) CustomSemanticsAction(label: l.label): l.onTrigger,
        },
        child: child,
      ),
    );
  }
}

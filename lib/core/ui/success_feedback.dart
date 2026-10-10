import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A short check-mark burst over the whole screen, for when something good
/// happened (a payment saved, a reminder done). It never takes taps and removes
/// itself. [big] is for the moment an entry is fully settled.
///
/// The message is always announced to screen readers. When the phone has
/// animations turned off, only the announcement happens.
void showSuccess(BuildContext context, String message, {bool big = false}) {
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SuccessBurst(
      message: message,
      big: big,
      onDone: () {
        if (entry.mounted) entry.remove();
        entry.dispose();
      },
    ),
  );
  overlay.insert(entry);
}

/// How long a burst stays up.
Duration burstDuration({required bool big}) =>
    Duration(milliseconds: big ? 1400 : 900);

class _SuccessBurst extends StatefulWidget {
  const _SuccessBurst({
    required this.message,
    required this.big,
    required this.onDone,
  });

  final String message;
  final bool big;
  final VoidCallback onDone;

  @override
  State<_SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<_SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: burstDuration(big: widget.big),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Grow in during the first 35%, hold, fade out over the last 30%.
    final scale = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.35, curve: Curves.elasticOut),
    );
    final fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 30),
    ]).animate(_c);
    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: Container(
              key: const ValueKey('success-burst'),
              padding: EdgeInsets.symmetric(
                horizontal: widget.big ? 32 : 24,
                vertical: widget.big ? 28 : 20,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(blurRadius: 24, color: Color(0x33000000)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: widget.big ? 96 : 64,
                    color: color,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.message,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

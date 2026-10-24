import 'package:flutter/material.dart';

/// "Swipe to confirm" button: drag the thumb left → right past ~85% to fire
/// [onSwipe]; releasing early springs it back. Used for clock in/out and
/// break start/end so a stray tap can't punch the clock.
class SwipeActionButton extends StatefulWidget {
  const SwipeActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onSwipe,
    this.enabled = true,
    this.height = 48,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Future<void> Function() onSwipe;
  final bool enabled;
  final double height;

  @override
  State<SwipeActionButton> createState() => _SwipeActionButtonState();
}

class _SwipeActionButtonState extends State<SwipeActionButton> with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _busy = false;
  late final AnimationController _reset =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  @override
  void dispose() {
    _reset.dispose();
    super.dispose();
  }

  double _from = 0;

  @override
  void initState() {
    super.initState();
    _reset.addListener(
        () => setState(() => _dx = _from * (1 - Curves.easeOut.transform(_reset.value))));
  }

  void _springBack() {
    _from = _dx;
    _reset.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final thumb = h - 8;
    final active = widget.enabled && !_busy;
    final color = widget.enabled ? widget.color : Colors.grey;

    return LayoutBuilder(builder: (context, c) {
      final maxDx = (c.maxWidth - thumb - 8).clamp(1.0, double.infinity);
      final progress = (_dx / maxDx).clamp(0.0, 1.0);

      return Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Fill trailing the thumb.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _dx + thumb + 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(h / 2),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: 1 - progress * 0.9,
                  child: Padding(
                    padding: EdgeInsets.only(left: thumb * 0.6),
                    child: Text(
                      'Swipe to ${widget.label.toLowerCase()}  ›››',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 4 + _dx,
                child: GestureDetector(
                  onHorizontalDragUpdate: active
                      ? (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx))
                      : null,
                  onHorizontalDragEnd: active
                      ? (_) async {
                          if (_dx >= maxDx * 0.85) {
                            setState(() {
                              _dx = maxDx;
                              _busy = true;
                            });
                            try {
                              await widget.onSwipe();
                            } finally {
                              if (mounted) {
                                setState(() => _busy = false);
                                _springBack();
                              }
                            }
                          } else {
                            _springBack();
                          }
                        }
                      : null,
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(widget.icon, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

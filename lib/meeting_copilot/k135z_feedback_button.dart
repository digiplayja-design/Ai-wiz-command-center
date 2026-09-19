import 'dart:async';
import 'package:flutter/material.dart';

// A tap is acknowledged immediately; selected is supplied by confirmed state.
class K135zFeedbackButton extends StatefulWidget {
  const K135zFeedbackButton.elevated({super.key, this.buttonKey, required this.onPressed,
    this.child, this.icon, this.label, this.selected = false,
    this.pendingLabel = 'Working…', this.activeColor = const Color(0xFF22D8FF)})
      : kind = 0;
  const K135zFeedbackButton.outlined({super.key, this.buttonKey, required this.onPressed,
    this.child, this.icon, this.label, this.selected = false,
    this.pendingLabel = 'Working…', this.activeColor = const Color(0xFF22D8FF)})
      : kind = 1;
  const K135zFeedbackButton.filled({super.key, this.buttonKey, required this.onPressed,
    this.child, this.icon, this.label, this.selected = false,
    this.pendingLabel = 'Working…', this.activeColor = const Color(0xFF22D8FF)})
      : kind = 2;

  final Key? buttonKey;
  final int kind;
  final FutureOr<void> Function()? onPressed;
  final Widget? child, icon, label;
  final bool selected;
  final String pendingLabel;
  final Color activeColor;

  @override
  State<K135zFeedbackButton> createState() => _K135zFeedbackButtonState();
}

class _K135zFeedbackButtonState extends State<K135zFeedbackButton> {
  bool _waiting = false, _flash = false;
  Timer? _timer;

  Future<void> _activate() async {
    if (_waiting || widget.onPressed == null) return;
    _timer?.cancel();
    setState(() { _waiting = true; _flash = true; });
    _timer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flash = false);
    });
    try {
      // Invoke synchronously so authorization popups retain user activation.
      await Future<void>.sync(widget.onPressed!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text(
          'Action could not be completed. Refresh the session before trying again.')));
      }
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF22D8FF), amber = Color(0xFFFFCC66);
    final lit = _waiting || _flash || widget.selected;
    final color = _waiting ? amber : widget.selected ? widget.activeColor : cyan;
    final enabled = !_waiting && widget.onPressed != null;
    final style = ButtonStyle(
      splashFactory: InkRipple.splashFactory,
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
        lit || states.contains(WidgetState.pressed) ? color.withValues(alpha: .22) : const Color(0xFF0A223A)),
      foregroundColor: WidgetStatePropertyAll(lit ? color : enabled ? cyan : const Color(0xFF708494)),
      overlayColor: WidgetStatePropertyAll(cyan.withValues(alpha: .28)),
      side: WidgetStatePropertyAll(BorderSide(color: lit ? color : enabled ? const Color(0xFF397086) : const Color(0xFF294252), width: lit ? 2 : 1)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    );
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      if (_waiting) SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color))
      else if (widget.selected) Icon(Icons.check_circle, size: 18, color: color)
      else if (widget.icon != null) widget.icon!,
      if (_waiting || widget.selected || widget.icon != null) const SizedBox(width: 8),
      Flexible(child: _waiting ? Text(widget.pendingLabel) : widget.child ?? widget.label ?? const SizedBox.shrink()),
    ]);
    final press = enabled ? _activate : null;
    final button = switch (widget.kind) {
      0 => ElevatedButton(key: widget.buttonKey, onPressed: press, style: style, child: content),
      2 => FilledButton(key: widget.buttonKey, onPressed: press, style: style, child: content),
      _ => OutlinedButton(key: widget.buttonKey, onPressed: press, style: style, child: content),
    };
    return Semantics(selected: widget.selected, liveRegion: _waiting,
      child: AnimatedContainer(duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(32),
          boxShadow: lit ? [BoxShadow(color: color.withValues(alpha: .32), blurRadius: 14, spreadRadius: 1)] : []),
        child: button));
  }
}

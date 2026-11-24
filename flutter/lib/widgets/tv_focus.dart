import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    required this.onPressed,
    this.onFocused,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.08,
    this.borderRadius = 10,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onFocused;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final double borderRadius;
  final bool enabled;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  FocusNode? _owned;
  var _focused = false;

  FocusNode get _node => widget.focusNode ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _owned = FocusNode(debugLabel: 'TvFocus');
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _onKey,
      onFocusChange: (hasFocus) {
        if (hasFocus == _focused) return;
        setState(() => _focused = hasFocus);
        widget.onFocused?.call(hasFocus);
      },
      child: GestureDetector(
        onTap: widget.enabled
            ? () {
                _node.requestFocus();
                widget.onPressed();
              }
            : null,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _focused ? themeFocus : Colors.transparent,
                width: _focused ? 3 : 0,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius - 1),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.filled = true,
    this.icon,
    this.focusNode,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool filled;
  final IconData? icon;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      scale: 1.04,
      borderRadius: 8,
      child: ColoredBox(
        color: filled ? themeAccent : const Color(0x33FFFFFF),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: themeText),
                const SizedBox(width: 10),
              ],
              Text(label, style: bodyStyle(size: 18, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

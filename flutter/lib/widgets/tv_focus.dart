import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    required this.onPressed,
    this.onFocused,
    this.onKeyEvent,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.08,
    this.borderRadius = 10,
    this.enabled = true,
    /// Flat list row (Netflix-style): white focus ring, no lift shadow.
    this.listItem = false,
    /// True circle focus ring / clip (player transport buttons).
    this.circle = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onFocused;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final double borderRadius;
  final bool enabled;
  final bool listItem;
  final bool circle;

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
    final custom = widget.onKeyEvent?.call(node, event);
    if (custom != null && custom != KeyEventResult.ignored) return custom;
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
    // Actions+ActivateIntent so TV Select/OK works even when HardwareKeyboard
    // or Shortcuts deliver activation instead of raw KeyDown on Focus.
    return Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (widget.enabled) widget.onPressed();
            return null;
          },
        ),
      },
      child: Focus(
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
            scale: widget.listItem ? 1 : (_focused ? widget.scale : 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: widget.circle ? null : BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: _focused ? themeFocus : Colors.transparent,
                  width: _focused ? (widget.listItem ? 2.5 : 3) : 0,
                ),
                color: widget.listItem && _focused ? const Color(0x22FFFFFF) : null,
                boxShadow: (!widget.listItem && _focused)
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ]
                    : const [],
              ),
              child: widget.circle
                  ? ClipOval(child: widget.child)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(
                        (widget.borderRadius - 1).clamp(0, 100).toDouble(),
                      ),
                      child: widget.child,
                    ),
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
    this.iconOnly = false,
    /// Compact chip (TH/EN) — same height as full buttons.
    this.compact = false,
    this.focusNode,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool filled;
  final IconData? icon;
  final bool iconOnly;
  final bool compact;
  final FocusNode? focusNode;

  /// Shared bar control height (กลับ / ภาษา / คลัง / จัดการ).
  static const barHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    assert(!iconOnly || icon != null, 'iconOnly requires an icon');
    final Widget inner;
    if (iconOnly) {
      inner = SizedBox(
        width: barHeight,
        height: barHeight,
        child: Center(child: Icon(icon, size: 22, color: themeText)),
      );
    } else if (compact) {
      inner = SizedBox(
        height: barHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Text(label, style: bodyStyle(size: 13, weight: FontWeight.w700)),
          ),
        ),
      );
    } else {
      inner = SizedBox(
        height: barHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: themeText),
                const SizedBox(width: 8),
              ],
              Text(label, style: bodyStyle(size: 15, weight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return TvFocus(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      scale: 1.04,
      borderRadius: 8,
      child: ColoredBox(
        color: filled ? themeAccent : const Color(0x33FFFFFF),
        child: inner,
      ),
    );
  }
}

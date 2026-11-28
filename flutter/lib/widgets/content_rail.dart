import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class ContentRail extends StatelessWidget {
  const ContentRail({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 40),
  });

  final String title;
  final List<Widget> children;
  final EdgeInsets padding;

  KeyEventResult _leaveHorizontally(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final focus = FocusManager.instance.primaryFocus ?? node;
    // Horizontal ListView traps D-pad — force vertical focus out to next/prev rail.
    if (key == LogicalKeyboardKey.arrowDown) {
      final moved = focus.focusInDirection(TraversalDirection.down);
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final moved = focus.focusInDirection(TraversalDirection.up);
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 6),
          child: Text(title, style: bodyStyle(size: 15, weight: FontWeight.w700)),
        ),
        SizedBox(
          height: 228,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _leaveHorizontally,
            child: ListView.separated(
              padding: padding,
              scrollDirection: Axis.horizontal,
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, index) => children[index],
            ),
          ),
        ),
      ],
    );
  }
}
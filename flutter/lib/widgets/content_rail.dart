import 'package:flutter/material.dart';

import '../theme.dart';

class ContentRail extends StatelessWidget {
  const ContentRail({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 56),
  });

  final String title;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 14),
          child: Text(title, style: bodyStyle(size: 22, weight: FontWeight.w700)),
        ),
        SizedBox(
          height: 310,
          child: ListView.separated(
            padding: padding,
            scrollDirection: Axis.horizontal,
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, index) => children[index],
          ),
        ),
      ],
    );
  }
}

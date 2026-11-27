import 'package:flutter/material.dart';

import '../theme.dart';

/// Vertical poster/folder gallery for library + folder browsing (not side rails).
class ContentGallery extends StatelessWidget {
  const ContentGallery({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.maxCrossAxisExtent = 156,
    // โปสเตอร์ ~2:3 + ช่องว่าง + ชื่อ/subtitle — ให้สูงพอไม่ล้นเศษพิกเซล
    this.childAspectRatio = 0.52,
    this.padding = const EdgeInsets.fromLTRB(48, 0, 48, 8),
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final double childAspectRatio;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 10, padding.right, 10),
          child: Text(title, style: bodyStyle(size: 18, weight: FontWeight.w700)),
        ),
        Padding(
          padding: padding,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCrossAxisExtent,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
            ),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

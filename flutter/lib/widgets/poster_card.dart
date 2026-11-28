import 'package:flutter/material.dart';

import '../theme.dart';
import 'remote_art.dart';
import 'tv_focus.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.seed,
    required this.onPressed,
    this.imageUrl,
    this.subtitle,
    this.width = 112,
    this.height = 168,
    this.expand = false,
    this.imageAspectRatio = 2 / 3,
    this.autofocus = false,
    this.onFocused,
    this.focusNode,
  });

  final String title;
  final String seed;
  final String? imageUrl;
  final String? subtitle;
  final double width;
  final double height;
  /// Fill parent width (gallery grid cells).
  final bool expand;
  final double imageAspectRatio;
  final VoidCallback onPressed;
  final bool autofocus;
  final ValueChanged<bool>? onFocused;
  final FocusNode? focusNode;

  Widget _art({double? w, double? h}) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _Fallback(title: title, seed: seed);
    }
    return RemoteArt(
      url: imageUrl!,
      fit: BoxFit.cover,
      width: w,
      height: h,
      fallback: _Fallback(title: title, seed: seed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(size: 13, weight: FontWeight.w600),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(size: 11, color: themeMuted),
          ),
      ],
    );

    if (expand) {
      // รูปกินพื้นที่ที่เหลือในช่องกริด — ไม่ล้นจาก AspectRatio + ข้อความ
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TvFocus(
              autofocus: autofocus,
              focusNode: focusNode,
              onPressed: onPressed,
              onFocused: onFocused,
              borderRadius: 10,
              child: SizedBox.expand(child: _art()),
            ),
          ),
          const SizedBox(height: 8),
          labels,
        ],
      );
    }

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TvFocus(
            autofocus: autofocus,
            focusNode: focusNode,
            onPressed: onPressed,
            onFocused: onFocused,
            borderRadius: 10,
            child: SizedBox(width: width, height: height, child: _art(w: width, h: height)),
          ),
          const SizedBox(height: 10),
          labels,
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.title, required this.seed});

  final String title;
  final String seed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [posterColor(seed), const Color(0xFF07070A)],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(size: 16, weight: FontWeight.w700, height: 1.2),
          ),
        ),
      ),
    );
  }
}

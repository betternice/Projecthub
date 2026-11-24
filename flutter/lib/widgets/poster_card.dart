import 'package:flutter/material.dart';

import '../theme.dart';
import 'tv_focus.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.seed,
    required this.onPressed,
    this.imageUrl,
    this.subtitle,
    this.width = 168,
    this.height = 252,
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
  final VoidCallback onPressed;
  final bool autofocus;
  final ValueChanged<bool>? onFocused;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvFocus(
            autofocus: autofocus,
            focusNode: focusNode,
            onPressed: onPressed,
            onFocused: onFocused,
            borderRadius: 10,
            child: SizedBox(
              width: width,
              height: height,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? _Fallback(title: title, seed: seed)
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      width: width,
                      height: height,
                      errorBuilder: (_, __, ___) => _Fallback(title: title, seed: seed),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(size: 15, weight: FontWeight.w600),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle(size: 13, color: themeMuted),
            ),
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

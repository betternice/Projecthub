import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Network image with disk cache — suited for Android TV restarts.
class RemoteArt extends StatelessWidget {
  const RemoteArt({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.fallback,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => fallback ?? const ColoredBox(color: themeRaised),
      errorWidget: (_, __, ___) => fallback ?? const ColoredBox(color: themeRaised),
    );
  }
}

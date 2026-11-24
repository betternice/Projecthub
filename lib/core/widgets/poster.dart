import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// ปกหนัง ถ้าไม่มีรูปหรือโหลดรูปไม่ได้จะแสดงชื่อเรื่องบนพื้นไล่สีแทน
class Poster extends StatelessWidget {
  const Poster({super.key, required this.url, required this.title, required this.seed, this.radius = 6});

  final String? url;
  final String title;
  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    final fallback = _Fallback(title: title, seed: seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: AppColors.raised,
        child: imageUrl == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, _, _) => fallback,
              ),
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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.poster(seed), const Color(0xFF12110E)],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppText.semibold(size: 13, height: 1.25),
          ),
        ),
      ),
    );
  }
}

class NetworkArtwork extends StatelessWidget {
  const NetworkArtwork({super.key, required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    const empty = ColoredBox(color: AppColors.sheet, child: SizedBox.expand());
    if (imageUrl == null) return empty;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorWidget: (_, _, _) => empty,
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/poster.dart';
import '../../domain/entities/drive_item.dart';
import '../cubit/library_state.dart';

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({super.key, required this.movie, required this.onTap});

  final LibraryMovie movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final year = movie.year;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 236,
          height: 132,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetworkArtwork(url: movie.match?.backdropUrl),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.4, 1],
                    colors: [Colors.transparent, Color(0xE0000000)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.semibold(size: 16)),
                    if (year != null)
                      Text(year, style: AppText.body(size: 12, color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.folder, required this.onTap});

  final DriveItem folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.folder_outlined, color: AppColors.muted, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.medium(size: 16)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class MovieCard extends StatelessWidget {
  const MovieCard({super.key, required this.movie, required this.onTap});

  final LibraryMovie movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Poster(url: movie.posterUrl, title: movie.title, seed: movie.item.id),
          ),
          const SizedBox(height: 6),
          Text(
            movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.medium(size: 12, height: 1.25),
          ),
          Text(movie.year ?? '', style: AppText.body(size: 11, color: AppColors.faint)),
        ],
      ),
    );
  }
}

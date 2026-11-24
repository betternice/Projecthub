import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/media_title.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/poster.dart';
import '../../../library/domain/entities/drive_item.dart';
import '../../../metadata/domain/entities/media.dart';
import '../../../player/presentation/pages/player_page.dart';
import '../cubit/movie_detail_cubit.dart';

class MovieDetailArgs {
  const MovieDetailArgs({required this.item, required this.match});

  final DriveItem item;
  final MediaMatch? match;
}

class MovieDetailPage extends StatelessWidget {
  const MovieDetailPage({super.key});

  Future<void> _play(BuildContext context, String title) async {
    final url = await context.read<MovieDetailCubit>().preparePlayback();
    if (url == null || !context.mounted) return;
    context.push(AppRoutes.player, extra: PlayerArgs(title: title, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final item = context.read<MovieDetailCubit>().item;
    final parsed = parseMediaTitle(item.name);
    final width = MediaQuery.sizeOf(context).width;
    final insets = MediaQuery.paddingOf(context);

    return BlocBuilder<MovieDetailCubit, MovieDetailState>(
      builder: (context, state) {
        final detail = state.detail;
        final match = detail?.match;
        final title = match?.title.isNotEmpty == true ? match!.title : parsed.title;
        final facts = [
          match?.year ?? parsed.year,
          formatRuntime(detail?.runtimeMinutes) ?? formatClock(item.durationMs),
          detail?.director,
          if (match?.rating case final rating?) '★ ${rating.toStringAsFixed(1)}',
          ...?detail?.genres,
        ].whereType<String>().toList();
        final poster = match?.posterUrl ?? item.thumbnailUrl;
        final overview = match?.overview;
        final cast = detail?.cast ?? const <CastMember>[];

        return Scaffold(
          body: ListView(
            padding: EdgeInsets.only(bottom: insets.bottom + 36),
            children: [
              SizedBox(
                height: width * 0.72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkArtwork(url: match?.backdropUrl ?? poster),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.42, 1],
                          colors: [Color(0x47000000), Color(0x14000000), AppColors.bg],
                        ),
                      ),
                    ),
                    Positioned(
                      top: insets.top + 4,
                      left: 8,
                      child: IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 104,
                        height: 156,
                        child: Poster(url: poster, title: title, seed: item.id),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: AppText.semibold(size: 28, height: 1.15)),
                              if (facts.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    facts.join('   ·   '),
                                    style: AppText.medium(size: 13, color: Colors.white.withValues(alpha: 0.78)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -54),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PrimaryButton(
                            label: '▶   เล่น',
                            height: 50,
                            radius: 12,
                            busy: state.preparingPlayback,
                            onPressed: () => _play(context, title),
                          ),
                          if (state.playbackError case final message?)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(message, style: AppText.medium(size: 14, color: AppColors.danger)),
                            ),
                          if (overview != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text(
                                overview,
                                style: AppText.body(size: 15, color: AppColors.overview, height: 1.55),
                              ),
                            ),
                          if (cast.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _SectionTitle('นักแสดง'),
                            SizedBox(
                              height: 120,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: cast.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 14),
                                itemBuilder: (_, index) => _CastCard(person: cast[index]),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _SectionTitle('ไฟล์'),
                          Text(item.name, style: AppText.medium(size: 14, height: 1.4)),
                          const SizedBox(height: 4),
                          Text(
                            formatBytes(item.size) ?? 'OneDrive',
                            style: AppText.body(size: 13, color: AppColors.faint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: AppText.medium(size: 13, color: AppColors.muted)),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.person});

  final CastMember person;

  @override
  Widget build(BuildContext context) {
    final profile = person.profileUrl;
    return SizedBox(
      width: 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.raised,
            backgroundImage: profile == null ? null : CachedNetworkImageProvider(profile),
          ),
          const SizedBox(height: 8),
          Text(
            person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.medium(size: 12, height: 1.3),
          ),
        ],
      ),
    );
  }
}

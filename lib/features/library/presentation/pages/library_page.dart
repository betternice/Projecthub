import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../movie_detail/presentation/pages/movie_detail_page.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';
import '../widgets/library_widgets.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  void _openMovie(BuildContext context, LibraryMovie movie) {
    context.push(AppRoutes.movie, extra: MovieDetailArgs(item: movie.item, match: movie.match));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LibraryCubit>();
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final movies = state.movies;
        final featured = state.featured;
        final parent = state.parent;
        final width = MediaQuery.sizeOf(context).width;
        const padding = 16.0;
        const gap = 8.0;
        final columns = math.max(3, (width / 150).floor());
        final cardWidth = (width - padding * 2 - gap * (columns - 1)) / columns;
        final textScale = MediaQuery.textScalerOf(context).scale(1);

        return PopScope(
          // ปุ่มย้อนกลับของ Android ขึ้นโฟลเดอร์แม่ก่อน ถึงโฟลเดอร์บนสุดแล้วค่อยออกจากแอป
          canPop: parent == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.goUp();
          },
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: cubit.refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(padding, 8, padding, 14),
                      sliver: SliverList.list(
                        children: [
                          if (parent != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: cubit.goUp,
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppColors.muted),
                                icon: const Icon(Icons.chevron_left),
                                label: Text(parent.name, style: AppText.medium(size: 16, color: AppColors.muted)),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  state.screenTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.semibold(size: 34, height: 1.12),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _showSettings(context),
                                icon: const Icon(Icons.more_horiz, color: AppColors.text),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          BlocSelector<SessionCubit, SessionState, String?>(
                            selector: (state) => state.session?.displayName,
                            builder: (context, name) => Text(
                              [?name, if (movies.isNotEmpty) '${movies.length} เรื่อง'].join('  ·  '),
                              style: AppText.body(size: 13, color: AppColors.muted),
                            ),
                          ),
                          if (state.errorMessage case final message?)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(message, style: AppText.medium(size: 14, color: AppColors.danger)),
                            ),
                          if (featured.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: SizedBox(
                                height: 132,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: featured.length,
                                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                                  itemBuilder: (context, index) => FeaturedCard(
                                    movie: featured[index],
                                    onTap: () => _openMovie(context, featured[index]),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          for (final folder in state.folders)
                            FolderTile(folder: folder, onTap: () => cubit.openFolder(folder)),
                        ],
                      ),
                    ),
                    if (movies.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(padding, 0, padding, MediaQuery.paddingOf(context).bottom + 28),
                        sliver: SliverGrid.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: gap,
                            mainAxisSpacing: 12,
                            mainAxisExtent: cardWidth * 1.5 + 6 + 52 * textScale,
                          ),
                          itemCount: movies.length,
                          itemBuilder: (context, index) =>
                              MovieCard(movie: movies[index], onTap: () => _openMovie(context, movies[index])),
                        ),
                      )
                    else
                      SliverToBoxAdapter(child: _EmptyState(state: state)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    final cubit = context.read<LibraryCubit>();
    final session = context.read<SessionCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _SettingsSheet(
        initialTmdbKey: cubit.state.tmdbApiKey ?? '',
        onSave: cubit.updateTmdbApiKey,
        onSignOut: session.signOut,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Padding(padding: EdgeInsets.only(top: 36), child: Center(child: CircularProgressIndicator()));
    }
    if (state.errorMessage != null || state.folders.isNotEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text('ยังไม่มีไฟล์วิดีโอในโฟลเดอร์นี้', style: AppText.body(color: AppColors.muted, height: 1.45)),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.initialTmdbKey, required this.onSave, required this.onSignOut});

  final String initialTmdbKey;
  final Future<void> Function(String value) onSave;
  final Future<void> Function() onSignOut;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _tmdbKey = TextEditingController(text: widget.initialTmdbKey);

  @override
  void dispose() {
    _tmdbKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ปกและรายละเอียด', style: AppText.semibold(size: 22)),
            const SizedBox(height: 12),
            Text(
              'แอปดึงปกและเรื่องย่อให้อยู่แล้ว ใส่ API key จาก themoviedb.org เมื่ออยากได้รูปนักแสดงเพิ่ม',
              style: AppText.body(size: 14, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tmdbKey,
              autocorrect: false,
              enableSuggestions: false,
              style: AppText.body(),
              decoration: const InputDecoration(hintText: 'TMDB API key'),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'บันทึก',
              height: 50,
              radius: 12,
              onPressed: () {
                widget.onSave(_tmdbKey.text);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSignOut();
              },
              child: Text('ออกจากระบบ', style: AppText.medium(color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
  }
}

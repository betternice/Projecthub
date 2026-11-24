import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/di/injection.dart';
import '../features/auth/presentation/cubit/session_cubit.dart';
import '../features/auth/presentation/cubit/sign_in_cubit.dart';
import '../features/auth/presentation/pages/sign_in_page.dart';
import '../features/library/presentation/cubit/library_cubit.dart';
import '../features/library/presentation/pages/library_page.dart';
import '../features/movie_detail/presentation/cubit/movie_detail_cubit.dart';
import '../features/movie_detail/presentation/pages/movie_detail_page.dart';
import '../features/player/presentation/pages/player_page.dart';
import 'routes.dart';
import 'theme.dart';

GoRouter buildRouter(SessionCubit session) {
  return GoRouter(
    initialLocation: AppRoutes.library,
    refreshListenable: _StreamListenable(session.stream),
    redirect: (context, state) {
      final location = state.matchedLocation;
      return switch (session.state.status) {
        SessionStatus.unknown => location == AppRoutes.splash ? null : AppRoutes.splash,
        SessionStatus.unauthenticated => location == AppRoutes.signIn ? null : AppRoutes.signIn,
        SessionStatus.authenticated =>
          location == AppRoutes.splash || location == AppRoutes.signIn ? AppRoutes.library : null,
      };
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const _SplashPage()),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (_, _) => BlocProvider(create: (_) => sl<SignInCubit>()..load(), child: const SignInPage()),
      ),
      GoRoute(
        path: AppRoutes.library,
        builder: (_, _) => BlocProvider(create: (_) => sl<LibraryCubit>()..start(), child: const LibraryPage()),
        routes: [
          GoRoute(
            path: 'movie',
            // extra หายเมื่อแอปถูก restore จาก deep link หรือ hot restart จึงพากลับหน้าคลังแทนการ crash
            redirect: (_, state) => state.extra is MovieDetailArgs ? null : AppRoutes.library,
            builder: (_, state) => BlocProvider(
              create: (_) => sl<MovieDetailCubit>(param1: state.extra! as MovieDetailArgs)..load(),
              child: const MovieDetailPage(),
            ),
            routes: [
              GoRoute(
                path: 'play',
                redirect: (_, state) => state.extra is PlayerArgs ? null : AppRoutes.library,
                builder: (_, state) => PlayerPage(args: state.extra! as PlayerArgs),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Movie Collection', style: AppText.display())));
  }
}

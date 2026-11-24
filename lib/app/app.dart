import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/config/flavor.dart';
import '../core/di/injection.dart';
import '../features/auth/presentation/cubit/session_cubit.dart';
import 'router.dart';
import 'theme.dart';

class MovieCollectionApp extends StatefulWidget {
  const MovieCollectionApp({super.key});

  @override
  State<MovieCollectionApp> createState() => _MovieCollectionAppState();
}

class _MovieCollectionAppState extends State<MovieCollectionApp> {
  final _flavor = Flavor.current;
  final _session = sl<SessionCubit>()..restore();
  late final GoRouter _router = buildRouter(_session);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _session,
      child: MaterialApp.router(
        title: _flavor.title,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
        builder: (context, child) {
          final label = _flavor.bannerLabel;
          final content = child ?? const SizedBox.shrink();
          if (label == null) return content;
          return Banner(
            message: label,
            location: BannerLocation.topEnd,
            color: _flavor == Flavor.dev ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00),
            child: content,
          );
        },
      ),
    );
  }
}

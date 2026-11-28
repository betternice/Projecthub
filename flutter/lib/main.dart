import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const NiceApp());
}

class NiceApp extends StatefulWidget {
  const NiceApp({super.key});

  @override
  State<NiceApp> createState() => _NiceAppState();
}

class _NiceAppState extends State<NiceApp> {
  final _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.boot();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          return MaterialApp(
            title: 'Niceflix',
            debugShowCheckedModeBanner: false,
            theme: buildNiceTheme(),
            locale: Locale(_state.lang.code),
            supportedLocales: const [Locale('th'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // Shrink whole UI on TV: boxes often report density that makes fixed
            // dp sizes (posters, type, padding) look oversized on a living-room screen.
            builder: (context, child) => densifyUi(context, child),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

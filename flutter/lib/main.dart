import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      child: MaterialApp(
        title: 'NICE',
        debugShowCheckedModeBanner: false,
        theme: buildNiceTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}

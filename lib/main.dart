import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'services/settings.dart';
import 'ui/home_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppSettings.init();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Phoenicx Stream',
        size: Size(1280, 760),
        minimumSize: Size(720, 480),
        center: true,
        backgroundColor: PX.bg,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(const PhoenicxApp());
}

class PhoenicxApp extends StatelessWidget {
  const PhoenicxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      // TV remotes: OK / centre button and game-pad A act like a tap.
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: MaterialApp(
        title: 'Phoenicx Stream',
        debugShowCheckedModeBanner: false,
        theme: PX.theme(),
        darkTheme: PX.theme(),
        themeMode: ThemeMode.dark,
        home: const _Gate(),
      ),
    );
  }
}

/// Shows setup until both API keys are saved.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  @override
  Widget build(BuildContext context) {
    if (!AppSettings.hasKeys) {
      return SettingsScreen(firstRun: true, onDone: () => setState(() {}));
    }
    return const HomeScreen();
  }
}

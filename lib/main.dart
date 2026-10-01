import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/pixeltools_app.dart';
import 'core/settings/app_settings.dart';
import 'splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Launch Flutter immediately so the animated splash screen and loading UI
  // render in the very first frame without any native black screen delay.
  runApp(
    const ProviderScope(
      child: AppEntry(),
    ),
  );
}

class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key});

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // Warm up settings notifier immediately upon app startup in parallel with splash animation
    ref.read(appSettingsProvider.notifier);
  }

  void _onSplashComplete() {
    if (mounted) {
      setState(() {
        _showSplash = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F172A),
        ),
        home: SplashScreen(onSplashComplete: _onSplashComplete),
      );
    }
    return const PixelToolsApp();
  }
}

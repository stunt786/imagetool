import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/pixeltools_app.dart';
import 'core/services/app_info_service.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
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
    // Warm up settings and app version info immediately upon startup
    ref.read(appSettingsProvider.notifier);
    AppInfoService.instance.getAppInfo();
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
      final themeMode =
          ref.watch(appSettingsProvider.select((s) => s.themeMode));
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: SplashScreen(onSplashComplete: _onSplashComplete),
      );
    }
    return const PixelToolsApp();
  }
}

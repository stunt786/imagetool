import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/pixeltools_app.dart';
import 'core/services/ad_service.dart';
import 'core/services/permission_service.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await AdService.instance.initialize();
  }

  if (!kIsWeb) {
    await const AppPermissionService().requestAllPermissions();
  }

  runApp(const ProviderScope(child: AppEntry()));
}

class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key});

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry> {
  bool _showSplash = true;

  void _onSplashComplete() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(onSplashComplete: _onSplashComplete),
      );
    }
    return const PixelToolsApp();
  }
}

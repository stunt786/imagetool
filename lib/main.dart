import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/pixeltools_app.dart';
import 'core/services/ad_service.dart';
import 'core/services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Google AdMob SDK
  await AdService.instance.initialize();

  await const AppPermissionService().requestAllPermissions();

  runApp(const ProviderScope(child: PixelToolsApp()));
}


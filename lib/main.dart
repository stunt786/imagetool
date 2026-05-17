import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/pixeltools_app.dart';
import 'core/services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await const AppPermissionService().requestAllPermissions();
  
  runApp(const ProviderScope(child: PixelToolsApp()));
}


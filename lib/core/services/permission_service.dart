import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  const AppPermissionService();

  Future<void> requestAllPermissions() async {
    await _requestPermission(Permission.photos);
    await _requestPermission(Permission.storage);
    await _requestPermission(Permission.camera);
  }

  Future<bool> _requestPermission(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    if (status.isDenied || status.isRestricted) {
      final result = await permission.request();
      return result.isGranted;
    }
    return status.isGranted;
  }

  Future<bool> hasStoragePermission() async {
    final status = await Permission.photos.status;
    if (status.isGranted) return true;
    return (await Permission.storage.status).isGranted;
  }

  Future<bool> hasCameraPermission() async {
    return (await Permission.camera.status).isGranted;
  }

  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}

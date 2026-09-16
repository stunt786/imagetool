import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class AppPermissionService {
  const AppPermissionService();

  Future<void> requestAllPermissions() async {
    if (kIsWeb) return;
    await _requestPermission(ph.Permission.photos);
    await _requestPermission(ph.Permission.storage);
    await _requestPermission(ph.Permission.camera);
    try {
      final manageStatus = await ph.Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted && !manageStatus.isPermanentlyDenied) {
        await ph.Permission.manageExternalStorage.request();
      }
    } catch (_) {}
  }

  Future<bool> _requestPermission(ph.Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    if (status.isDenied || status.isRestricted) {
      final result = await permission.request();
      return result.isGranted;
    }
    return status.isGranted;
  }

  Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true;
    final photosStatus = await ph.Permission.photos.status;
    if (photosStatus.isGranted) return true;
    final storageStatus = await ph.Permission.storage.status;
    if (storageStatus.isGranted) return true;
    final manageStatus = await ph.Permission.manageExternalStorage.status;
    return manageStatus.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;

    final photosGranted = await _requestPermission(ph.Permission.photos);
    final storageGranted = await _requestPermission(ph.Permission.storage);
    if (photosGranted || storageGranted) return true;

    try {
      final manageStatus = await ph.Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;
      if (manageStatus.isDenied || manageStatus.isRestricted) {
        return (await ph.Permission.manageExternalStorage.request()).isGranted;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> isStoragePermissionPermanentlyDenied() async {
    if (kIsWeb) return false;
    final photosStatus = await ph.Permission.photos.status;
    final storageStatus = await ph.Permission.storage.status;
    final manageStatus = await ph.Permission.manageExternalStorage.status;
    return photosStatus.isPermanentlyDenied &&
        storageStatus.isPermanentlyDenied &&
        manageStatus.isPermanentlyDenied;
  }

  Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    return (await ph.Permission.camera.status).isGranted;
  }

  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    await ph.openAppSettings();
  }
}

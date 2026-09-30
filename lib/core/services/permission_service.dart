import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Runtime permissions for the flows that actually need them:
///
/// * the gallery picker reads photos (`READ_MEDIA_IMAGES` on Android 13+,
///   including Android 14's **partial** "selected photos" access),
/// * the camera is requested when the camera screen opens,
/// * saving no longer needs any permission on Android 10+ (MediaStore) and
///   only falls back to the legacy storage permission on Android 6-9.
///
/// `MANAGE_EXTERNAL_STORAGE` (All files access) is intentionally gone: Play
/// reserves it for file managers, and MediaStore/SAF cover every save path.
/// How much of the photo library the app may read.
enum PhotoAccess {
  /// No access — imports need a permission prompt first.
  none,

  /// Android 14+ / iOS partial access: only user-selected photos.
  limited,

  /// Full access.
  full,
}

class AppPermissionService {
  const AppPermissionService();

  static bool _isUsable(ph.PermissionStatus status) =>
      status.isGranted || status.isLimited;

  Future<bool> _requestPermission(ph.Permission permission) async {
    final status = await permission.status;
    if (_isUsable(status)) return true;
    if (status == ph.PermissionStatus.denied ||
        status == ph.PermissionStatus.restricted) {
      return _isUsable(await permission.request());
    }
    return false;
  }

  /// Current photo-library access. `limited` means the user granted only some
  /// photos (Android 14+ / iOS partial access), which is enough to import.
  Future<PhotoAccess> photoAccessLevel() async {
    if (kIsWeb) return PhotoAccess.full;
    final status = await ph.Permission.photos.status;
    if (status.isLimited) return PhotoAccess.limited;
    if (status.isGranted) return PhotoAccess.full;
    return PhotoAccess.none;
  }

  /// Whether images can be imported from the gallery right now.
  Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true;
    if (_isUsable(await ph.Permission.photos.status)) return true;
    return (await ph.Permission.storage.status).isGranted;
  }

  /// Requests photo access (and, on Android 6-9 only, the legacy storage
  /// permission used for pre-10 writes). Returns true when importing works —
  /// full or partial ("selected photos") access both count.
  Future<bool> requestStoragePermission() async {
    if (kIsWeb) return true;
    if (await _requestPermission(ph.Permission.photos)) return true;
    return _requestPermission(ph.Permission.storage);
  }

  Future<bool> isStoragePermissionPermanentlyDenied() async {
    if (kIsWeb) return false;
    if ((await ph.Permission.photos.status).isPermanentlyDenied) return true;
    return (await ph.Permission.storage.status).isPermanentlyDenied;
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

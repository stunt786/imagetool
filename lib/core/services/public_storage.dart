import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'permission_service.dart';

/// Where a finished file belongs in shared storage.
enum PublicFileKind {
  /// Gallery images (MediaStore `Pictures/PixelTools`).
  image,

  /// Documents such as PDFs (MediaStore `Download/PixelTools`).
  document,
}

/// Publishes finished files into public storage the way current Android
/// policy requires:
///
/// * images land in `Pictures/PixelTools` through **MediaStore** (permission
///   free on Android 10+),
/// * documents land in `Download/PixelTools` through **MediaStore.Downloads**,
/// * when the user picked a folder in Settings → Storage, everything goes to
///   that folder through a **persisted SAF tree grant**.
///
/// Raw writes into `/storage/emulated/0/...` are gone: they only worked with
/// `MANAGE_EXTERNAL_STORAGE`, which Play policy reserves for file managers.
abstract final class PublicStorage {
  static const MethodChannel _channel =
      MethodChannel('com.bnbkio.pixeltools/storage');

  static const String treeUriKey = 'custom_save_tree_uri';
  static const String treeLabelKey = 'custom_save_tree_label';

  /// The native pipeline exists for Android only; on iOS/desktop files stay in
  /// the app's own directories, which are already writable without policy
  /// constraints.
  static bool get supportsNativeStorage => !kIsWeb && Platform.isAndroid;

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ── Save folder (SAF tree) ─────────────────────────────────────────────

  static Future<String?> loadTreeUri() async =>
      (await _prefs).getString(treeUriKey);

  static Future<String?> loadTreeLabel() async =>
      (await _prefs).getString(treeLabelKey);

  static Future<void> setSaveTree({
    required String uri,
    required String label,
  }) async {
    final oldUri = await loadTreeUri();
    if (oldUri != null && oldUri != uri) {
      await _releaseTree(oldUri);
    }
    final prefs = await _prefs;
    await prefs.setString(treeUriKey, uri);
    await prefs.setString(treeLabelKey, label);
  }

  /// Reverts to the default destinations (Pictures / Download).
  static Future<void> clearSaveTree() async {
    final prefs = await _prefs;
    final uri = prefs.getString(treeUriKey);
    if (uri != null) {
      await _releaseTree(uri);
    }
    await prefs.remove(treeUriKey);
    await prefs.remove(treeLabelKey);
  }

  /// Opens the system folder picker. The returned grant is persistable but
  /// **not** stored in preferences — the caller decides whether it becomes the
  /// save location or is released again after a one-off export.
  static Future<({String uri, String label})?> pickFolder() async {
    if (!supportsNativeStorage) return null;
    final uri = await _invoke<String>('pickTree');
    if (uri == null || uri.isEmpty) return null;
    final label = await _invoke<String>('describeTree', {'uri': uri}) ?? uri;
    return (uri: uri, label: label);
  }

  static Future<void> releaseTree(String uri) => _releaseTree(uri);

  static Future<void> _releaseTree(String uri) async {
    if (!supportsNativeStorage) return;
    try {
      await _channel.invokeMethod('releaseTree', {'uri': uri});
    } catch (_) {
      // Best effort: an unreleased grant is dropped on reboot anyway.
    }
  }

  // ── Publishing ─────────────────────────────────────────────────────────

  /// Writes [bytes] into public storage and returns a human-readable
  /// destination path (for example `/storage/emulated/0/Download/PixelTools`).
  ///
  /// Throws [StateError] / [PlatformException] when the file could not be
  /// saved. On legacy devices (Android 6-9) the required storage permission is
  /// requested in context and the write is retried once.
  static Future<String> publishBytes({
    required Uint8List bytes,
    required String fileName,
    required PublicFileKind kind,
    String? treeUriOverride,
  }) async {
    final treeUri = treeUriOverride ?? await loadTreeUri();
    if (!supportsNativeStorage) {
      return _fallbackLocalPath(fileName, bytes: bytes);
    }
    return _invokeSave('saveBytes', {
      'bytes': bytes,
      'displayName': fileName,
      'kind': kind.name,
      'treeUri': treeUri,
    });
  }

  /// Copies an existing local file into public storage and returns the
  /// destination path. Off Android the file already lives in an app-managed
  /// directory, so the source path is returned unchanged.
  static Future<String> publishFile({
    required String sourcePath,
    required String fileName,
    required PublicFileKind kind,
    String? treeUriOverride,
  }) async {
    if (!supportsNativeStorage) return sourcePath;
    final treeUri = treeUriOverride ?? await loadTreeUri();
    return _invokeSave('saveFile', {
      'sourcePath': sourcePath,
      'displayName': fileName,
      'kind': kind.name,
      'treeUri': treeUri,
    });
  }

  /// Picks the public destination for [fileName] without writing anything.
  static PublicFileKind kindForFileName(String fileName) {
    final ext = path
        .extension(fileName)
        .toLowerCase()
        .replaceAll('.', '');
    const imageExtensions = {
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'avif',
    };
    return imageExtensions.contains(ext)
        ? PublicFileKind.image
        : PublicFileKind.document;
  }

  static Future<String> _invokeSave(
    String method,
    Map<String, dynamic> args,
  ) async {
    try {
      final saved = await _invoke<String>(method, args);
      if (saved == null || saved.isEmpty) {
        throw StateError('The file could not be saved.');
      }
      return saved;
    } on PlatformException catch (e) {
      if (e.code != 'PERMISSION_REQUIRED') rethrow;
      // Android 6-9 still gate shared-storage writes on the legacy permission.
      // Ask for it where the save is happening, then retry exactly once.
      final granted =
          await const AppPermissionService().requestStoragePermission();
      if (!granted) {
        throw StateError(
          'Saving to shared storage was denied. Allow storage access in '
          'Settings and try again.',
        );
      }
      final saved = await _invoke<String>(method, args);
      if (saved == null || saved.isEmpty) {
        throw StateError('The file could not be saved.');
      }
      return saved;
    }
  }

  static Future<T?> _invoke<T>(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // Host-side unit tests / unsupported platforms.
      return null;
    }
  }

  static Future<String> _fallbackLocalPath(
    String fileName, {
    Uint8List? bytes,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(base.path, 'PixelTools'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(path.join(dir.path, fileName));
    if (bytes != null) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'image_isolate_service.dart';
import 'pdf_service.dart';

/// Generates and caches the small previews used by Files, History and the
/// folder-content screens.
///
/// Thumbnails are keyed by file path + modified time, so editing a file
/// invalidates its cached preview automatically and an entire PDF is never
/// re-rendered just to show a list row.
class ThumbnailService {
  ThumbnailService({Future<Directory> Function()? cacheDirectoryProvider})
      : _cacheDirectoryProvider =
            cacheDirectoryProvider ?? _defaultCacheDirectory;

  /// Shared instance used by the UI layer.
  static final ThumbnailService instance = ThumbnailService();

  /// Test hook: when set, previews come from this callback instead of the
  /// platform pipeline (isolates + path_provider).
  @visibleForTesting
  static Future<String?> Function(String path)? debugOverride;

  final Future<Directory> Function() _cacheDirectoryProvider;

  /// De-duplicates concurrent requests for the same thumbnail.
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};

  /// Returns the cached thumbnail path for [filePath], generating it on first
  /// use. Returns null when no preview can be produced.
  Future<String?> thumbnailFor(
    String filePath, {
    int maxSide = 360,
    bool? isPdf,
  }) {
    final override = debugOverride;
    if (override != null) return override(filePath);

    return _inFlight.putIfAbsent(
      '$filePath|$maxSide',
      () => _generate(filePath, maxSide: maxSide, isPdf: isPdf),
    ).whenComplete(() {
      _inFlight.remove('$filePath|$maxSide');
    });
  }

  Future<String?> _generate(
    String filePath, {
    required int maxSide,
    bool? isPdf,
  }) async {
    final source = File(filePath);
    if (!await source.exists()) return null;

    final looksLikePdf = isPdf ?? filePath.toLowerCase().endsWith('.pdf');
    if (looksLikePdf) {
      // PdfService already caches by file modified time.
      try {
        return await PdfService.instance.renderPdfThumbnail(filePath);
      } catch (_) {
        return null;
      }
    }

    try {
      final stat = await source.stat();
      final cacheDirectory = await _cacheDirectoryProvider();
      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }

      final base = path.basenameWithoutExtension(filePath);
      final key = '${_sanitize(base)}_${stat.modified.millisecondsSinceEpoch}'
          '_$maxSide.jpg';
      final cached = File(path.join(cacheDirectory.path, key));
      if (await cached.exists() && await cached.length() > 0) {
        return cached.path;
      }

      final bytes = await source.readAsBytes();
      final thumbnail = await ImageIsolateService.thumbnail(
        bytes,
        maxSide: maxSide,
      );
      if (thumbnail == null || thumbnail.isEmpty) return null;

      await cached.writeAsBytes(thumbnail, flush: true);
      return cached.path;
    } catch (_) {
      return null;
    }
  }

  /// Deletes every cached thumbnail. Safe to call at any time; previews are
  /// rebuilt on demand.
  Future<void> clearCache() async {
    try {
      final directory = await _cacheDirectoryProvider();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Cache cleanup is best effort.
    }
  }

  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  static Future<Directory> _defaultCacheDirectory() async {
    final temp = await getTemporaryDirectory();
    return Directory(path.join(temp.path, 'pixeltools_thumbnails'));
  }
}

import 'dart:async';
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
  /// Upper bound for the on-disk preview cache.
  ///
  /// Previews are written once per file/modified-time/size combination, so a
  /// heavy browsing session used to grow `pixeltools_thumbnails` without
  /// limit. Evicting the least-recently-used entries keeps it predictable.
  static const int _maxCacheBytes = 64 * 1024 * 1024;

  /// Minimum spacing between full directory scans.
  static const Duration _trimInterval = Duration(minutes: 5);

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

  DateTime? _lastTrim;
  bool _trimming = false;

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

    final looksLikePdf = (isPdf ?? false) || filePath.toLowerCase().endsWith('.pdf');
    if (looksLikePdf) {
      // PdfService already caches by file modified time.
      try {
        final thumb = await PdfService.instance.renderPdfThumbnail(filePath);
        if (thumb != null) return thumb;
      } catch (_) {
        // If PDF thumbnailing fails, return null
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
        // Refresh access time so eviction below stays least-recently-used.
        try {
          await cached.setLastAccessed(DateTime.now());
        } catch (_) {
          // Some filesystems disallow atime updates; FIFO eviction still works.
        }
        return cached.path;
      }

      final bytes = await source.readAsBytes();
      final thumbnail = await ImageIsolateService.thumbnail(
        bytes,
        maxSide: maxSide,
      );
      if (thumbnail == null || thumbnail.isEmpty) return null;

      await cached.writeAsBytes(thumbnail, flush: true);
      unawaited(_maybeTrim(cacheDirectory));
      return cached.path;
    } catch (_) {
      return null;
    }
  }

  /// Schedules a size-bounded eviction of the cache directory.
  ///
  /// Throttled and debounced so the directory is not scanned once per
  /// generated thumbnail.
  Future<void> _maybeTrim(Directory cacheDirectory) async {
    final last = _lastTrim;
    if (_trimming) return;
    if (last != null && DateTime.now().difference(last) < _trimInterval) return;
    _trimming = true;
    _lastTrim = DateTime.now();
    try {
      await _trim(cacheDirectory);
    } catch (_) {
      // Eviction is best effort.
    } finally {
      _trimming = false;
    }
  }

  /// Deletes least-recently-used previews until the directory fits the cap.
  Future<void> _trim(Directory directory) async {
    if (!await directory.exists()) return;

    final entries = <_CacheEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        entries.add(_CacheEntry(entity, stat.size, stat.accessed));
      } catch (_) {
        // Skip files that vanished mid-scan.
      }
    }
    if (entries.isEmpty) return;

    var total = entries.fold<int>(0, (sum, e) => sum + e.size);
    if (total <= _maxCacheBytes) return;

    entries.sort((a, b) => a.accessed.compareTo(b.accessed));
    for (final entry in entries) {
      if (total <= _maxCacheBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {
        // Ignore files we cannot remove.
      }
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

class _CacheEntry {
  const _CacheEntry(this.file, this.size, this.accessed);

  final File file;
  final int size;
  final DateTime accessed;
}

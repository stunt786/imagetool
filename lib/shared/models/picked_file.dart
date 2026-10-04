import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class PickedFile {
  const PickedFile({
    required this.name,
    required this.sizeBytes,
    required this.extension,
    required this.path,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? extension;
  final String? path;

  /// The file bytes only when they could not be deferred to [path].
  ///
  /// The picker avoids holding every selected asset in RAM at once: when a
  /// native path is available the bytes are read on demand instead. Callers
  /// that need the payload must await [resolveBytes] rather than reading this
  /// field directly.
  final Uint8List? bytes;

  String get debugId => path ?? name;

  bool get hasReadablePath => (path ?? '').isNotEmpty;

  /// Returns the payload, reading it from [path] when it was not preloaded.
  Future<Uint8List?> resolveBytes() async {
    final cached = bytes;
    if (cached != null && cached.isNotEmpty) return cached;
    if (!hasReadablePath) return null;
    try {
      final file = File(path!);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}


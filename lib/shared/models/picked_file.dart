import 'dart:typed_data';

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
  final Uint8List? bytes;

  String get debugId => path ?? name;
}


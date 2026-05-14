import 'package:flutter/foundation.dart';

@immutable
class PickedFile {
  const PickedFile({
    required this.name,
    required this.sizeBytes,
    required this.extension,
    required this.path,
  });

  final String name;
  final int sizeBytes;
  final String? extension;
  final String? path;

  String get debugId => path ?? name;
}


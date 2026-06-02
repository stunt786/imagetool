import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum FilterType { none, magicColor, binarization, shadowRemoval }

@immutable
class ScannedPage {
  const ScannedPage({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.imageBytes,
    this.filteredBytes,
    this.filterType = FilterType.none,
    this.correctionCorners,
    this.width,
    this.height,
    this.isCorrectionApplied = false,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final Uint8List? imageBytes;
  final Uint8List? filteredBytes;
  final FilterType filterType;
  final List<Offset>? correctionCorners;
  final int? width;
  final int? height;
  final bool isCorrectionApplied;

  bool get isLoaded => imageBytes != null;
  Uint8List get displayBytes =>
      filteredBytes ?? imageBytes ?? Uint8List(0);

  ScannedPage copyWith({
    String? path,
    String? name,
    int? sizeBytes,
    Uint8List? imageBytes,
    Uint8List? filteredBytes,
    FilterType? filterType,
    List<Offset>? correctionCorners,
    int? width,
    int? height,
    bool? isCorrectionApplied,
    bool clearFilter = false,
    bool clearCorrection = false,
  }) {
    return ScannedPage(
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      imageBytes: imageBytes ?? this.imageBytes,
      filteredBytes: clearFilter ? null : (filteredBytes ?? this.filteredBytes),
      filterType: clearFilter ? FilterType.none : (filterType ?? this.filterType),
      correctionCorners:
          clearCorrection ? null : (correctionCorners ?? this.correctionCorners),
      width: width ?? this.width,
      height: height ?? this.height,
      isCorrectionApplied:
          clearCorrection ? false : (isCorrectionApplied ?? this.isCorrectionApplied),
    );
  }
}

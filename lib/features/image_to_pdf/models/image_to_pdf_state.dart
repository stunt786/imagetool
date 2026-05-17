import 'package:flutter/foundation.dart';

enum PdfPageSize { a4, a3, usLetter, usLegal, matchImage }

enum PdfOrientation { portrait, landscape, auto }

enum ImageFitMode { fit, fill, center, stretch }

enum PdfQuality { optimized, highQuality }

@immutable
class PdfPageSettings {
  const PdfPageSettings({
    required this.pageSize,
    required this.orientation,
    required this.fitMode,
    required this.quality,
    required this.marginMm,
  });

  final PdfPageSize pageSize;
  final PdfOrientation orientation;
  final ImageFitMode fitMode;
  final PdfQuality quality;
  final double marginMm;

  PdfPageSettings copyWith({
    PdfPageSize? pageSize,
    PdfOrientation? orientation,
    ImageFitMode? fitMode,
    PdfQuality? quality,
    double? marginMm,
  }) {
    return PdfPageSettings(
      pageSize: pageSize ?? this.pageSize,
      orientation: orientation ?? this.orientation,
      fitMode: fitMode ?? this.fitMode,
      quality: quality ?? this.quality,
      marginMm: marginMm ?? this.marginMm,
    );
  }

  static const PdfPageSettings defaults = PdfPageSettings(
    pageSize: PdfPageSize.a4,
    orientation: PdfOrientation.portrait,
    fitMode: ImageFitMode.fit,
    quality: PdfQuality.optimized,
    marginMm: 10.0,
  );
}

@immutable
class ImageToPdfItem {
  const ImageToPdfItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.imageBytes,
    this.width,
    this.height,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final Uint8List? imageBytes;
  final int? width;
  final int? height;

  bool get isLoaded => imageBytes != null;
  bool get hasDimensions => width != null && height != null;
  double get aspectRatio => hasDimensions ? width! / height! : 1.0;

  ImageToPdfItem copyWith({
    Uint8List? imageBytes,
    int? width,
    int? height,
  }) {
    return ImageToPdfItem(
      path: path,
      name: name,
      sizeBytes: sizeBytes,
      imageBytes: imageBytes ?? this.imageBytes,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

@immutable
class ImageToPdfState {
  const ImageToPdfState({
    required this.images,
    required this.pageSettings,
    this.isGenerating = false,
    this.progress = 0.0,
    this.errorMessage,
    this.generatedPdfPath,
  });

  final List<ImageToPdfItem> images;
  final PdfPageSettings pageSettings;
  final bool isGenerating;
  final double progress;
  final String? errorMessage;
  final String? generatedPdfPath;

  ImageToPdfState copyWith({
    List<ImageToPdfItem>? images,
    PdfPageSettings? pageSettings,
    bool? isGenerating,
    double? progress,
    String? errorMessage,
    String? generatedPdfPath,
  }) {
    return ImageToPdfState(
      images: images ?? this.images,
      pageSettings: pageSettings ?? this.pageSettings,
      isGenerating: isGenerating ?? this.isGenerating,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      generatedPdfPath: generatedPdfPath ?? this.generatedPdfPath,
    );
  }

  ImageToPdfState reorderImages(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return this;
    final newImages = List<ImageToPdfItem>.from(images);
    final item = newImages.removeAt(oldIndex);
    newImages.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    return copyWith(images: newImages);
  }

  ImageToPdfState removeImage(int index) {
    final newImages = List<ImageToPdfItem>.from(images);
    newImages.removeAt(index);
    return copyWith(images: newImages);
  }

  ImageToPdfState updateImage(int index, ImageToPdfItem item) {
    final newImages = List<ImageToPdfItem>.from(images);
    newImages[index] = item;
    return copyWith(images: newImages);
  }
}

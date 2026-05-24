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
    required this.marginTop,
    required this.marginBottom,
    required this.marginLeft,
    required this.marginRight,
  });

  final PdfPageSize pageSize;
  final PdfOrientation orientation;
  final ImageFitMode fitMode;
  final PdfQuality quality;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;

  PdfPageSettings copyWith({
    PdfPageSize? pageSize,
    PdfOrientation? orientation,
    ImageFitMode? fitMode,
    PdfQuality? quality,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
  }) {
    return PdfPageSettings(
      pageSize: pageSize ?? this.pageSize,
      orientation: orientation ?? this.orientation,
      fitMode: fitMode ?? this.fitMode,
      quality: quality ?? this.quality,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
    );
  }

  static const PdfPageSettings defaults = PdfPageSettings(
    pageSize: PdfPageSize.a4,
    orientation: PdfOrientation.portrait,
    fitMode: ImageFitMode.fit,
    quality: PdfQuality.optimized,
    marginTop: 0.75,
    marginBottom: 0.75,
    marginLeft: 0.75,
    marginRight: 0.75,
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

  ImageToPdfState swapImages(int index1, int index2) {
    if (index1 == index2) return this;
    if (index1 < 0 || index1 >= images.length) return this;
    if (index2 < 0 || index2 >= images.length) return this;
    final newImages = List<ImageToPdfItem>.from(images);
    final temp = newImages[index1];
    newImages[index1] = newImages[index2];
    newImages[index2] = temp;
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

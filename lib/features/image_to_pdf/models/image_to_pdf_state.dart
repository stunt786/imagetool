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
    // A page that matches its source image is the least surprising default:
    // it keeps every pixel visible and does not introduce white borders.
    pageSize: PdfPageSize.matchImage,
    orientation: PdfOrientation.auto,
    fitMode: ImageFitMode.fit,
    quality: PdfQuality.optimized,
    marginTop: 0,
    marginBottom: 0,
    marginLeft: 0,
    marginRight: 0,
  );
}

@immutable
class ImageToPdfItem {
  const ImageToPdfItem({
    required this.id,
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.imageBytes,
    this.previewBytes,
    this.width,
    this.height,
    this.isLoading = false,
    this.errorMessage,
  });

  /// Stable identity used for asynchronous updates while the list is being
  /// reordered or edited.
  final String id;

  final String path;
  final String name;
  final int sizeBytes;

  /// Full source bytes. Only kept in memory when the picker supplied bytes
  /// without a readable path; otherwise the file is read on demand.
  final Uint8List? imageBytes;

  /// Downscaled preview used by the thumbnail grid.
  final Uint8List? previewBytes;

  final int? width;
  final int? height;
  final bool isLoading;
  final String? errorMessage;

  bool get isLoaded => imageBytes != null;

  bool get hasDimensions => width != null && height != null;

  double get aspectRatio => hasDimensions ? width! / height! : 1.0;

  ImageToPdfItem copyWith({
    Uint8List? imageBytes,
    Uint8List? previewBytes,
    int? width,
    int? height,
    int? sizeBytes,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ImageToPdfItem(
      id: id,
      path: path,
      name: name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      imageBytes: imageBytes ?? this.imageBytes,
      previewBytes: previewBytes ?? this.previewBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

@immutable
class ImageToPdfState {
  const ImageToPdfState({
    required this.images,
    required this.pageSettings,
    this.isGenerating = false,
    this.isLoadingImages = false,
    this.progress = 0.0,
    this.loadProgress = 0.0,
    this.loadedCount = 0,
    this.loadTotal = 0,
    this.statusText,
    this.canCancel = false,
    this.errorMessage,
    this.generatedPdfPath,
  });

  final List<ImageToPdfItem> images;
  final PdfPageSettings pageSettings;
  final bool isGenerating;

  /// True while previews and dimensions are being prepared.
  final bool isLoadingImages;

  final double progress;
  final double loadProgress;
  final int loadedCount;
  final int loadTotal;

  /// Human readable step, e.g. `Adding image 7 of 12`.
  final String? statusText;

  final bool canCancel;
  final String? errorMessage;
  final String? generatedPdfPath;

  bool get isEmpty => images.isEmpty;

  int get loadedImages => images.where((i) => i.previewBytes != null).length;

  int get failedImages =>
      images.where((i) => i.errorMessage != null).length;

  ImageToPdfState copyWith({
    List<ImageToPdfItem>? images,
    PdfPageSettings? pageSettings,
    bool? isGenerating,
    bool? isLoadingImages,
    double? progress,
    double? loadProgress,
    int? loadedCount,
    int? loadTotal,
    String? statusText,
    bool? canCancel,
    String? errorMessage,
    bool clearError = false,
    bool clearStatus = false,
    String? generatedPdfPath,
    bool clearGeneratedPath = false,
  }) {
    return ImageToPdfState(
      images: images ?? this.images,
      pageSettings: pageSettings ?? this.pageSettings,
      isGenerating: isGenerating ?? this.isGenerating,
      isLoadingImages: isLoadingImages ?? this.isLoadingImages,
      progress: progress ?? this.progress,
      loadProgress: loadProgress ?? this.loadProgress,
      loadedCount: loadedCount ?? this.loadedCount,
      loadTotal: loadTotal ?? this.loadTotal,
      statusText: clearStatus ? null : (statusText ?? this.statusText),
      canCancel: canCancel ?? this.canCancel,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      generatedPdfPath: clearGeneratedPath
          ? null
          : (generatedPdfPath ?? this.generatedPdfPath),
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

  ImageToPdfState replaceImageById(String id, ImageToPdfItem item) {
    final index = images.indexWhere((i) => i.id == id);
    if (index == -1) return this;
    return updateImage(index, item);
  }
}

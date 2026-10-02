import 'package:flutter/foundation.dart';

/// Compression quality levels for PDF compression.
enum CompressionLevel {
  low('Low', 0.8, 'Minimal compression, best quality'),
  medium('Medium', 0.5, 'Balanced compression and quality'),
  high('High', 0.3, 'Strong compression, good quality'),
  extreme('Extreme', 0.15, 'Maximum compression, reduced quality');

  const CompressionLevel(this.label, this.qualityFactor, this.description);
  final String label;
  final double qualityFactor;
  final String description;
}

/// State for the PDF compress feature.
@immutable
class PdfCompressState {
  const PdfCompressState({
    this.selectedFilePath,
    this.selectedFileName,
    this.selectedFileSize,
    this.compressionLevel = CompressionLevel.medium,
    this.colorImageQuality = 70,
    this.greyImageQuality = 60,
    this.monoImageQuality = 60,
    this.compressStreams = true,
    this.unembedSimpleFonts = false,
    this.unembedComplexFonts = false,
    this.unembedUnusualFonts = false,
    this.flattenLayers = false,
    this.isAdvancedExpanded = false,
    this.isProcessing = false,
    this.progress = 0.0,
    this.errorMessage,
    this.note,
    this.outputPath,
    this.outputFileSize,
    this.publicExportPath,
  });

  final String? selectedFilePath;
  final String? selectedFileName;
  final int? selectedFileSize;
  final CompressionLevel compressionLevel;

  /// Quality (1-100) used for full-color images.
  final int colorImageQuality;

  /// Quality (1-100) used for grayscale images.
  final int greyImageQuality;

  /// Quality (1-100) used for monochrome (1-bit) images.
  final int monoImageQuality;

  /// Whether to DEFLATE uncompressed streams.
  final bool compressStreams;

  /// Whether to unembed standard/simple 1-byte fonts.
  final bool unembedSimpleFonts;

  /// Whether to unembed composite/CID fonts (Type 0).
  final bool unembedComplexFonts;

  /// Whether to unembed Type 3 or uncommon fonts.
  final bool unembedUnusualFonts;

  /// Whether to flatten layers (OCGs) and annotations.
  final bool flattenLayers;

  /// Whether the advanced compression settings panel is expanded.
  final bool isAdvancedExpanded;

  final bool isProcessing;
  final double progress;
  final String? errorMessage;

  /// Optional explanation shown after a run, e.g. why the watermark was
  /// skipped or why no size reduction was possible.
  final String? note;

  final String? outputPath;
  final int? outputFileSize;
  final String? publicExportPath;

  bool get hasFile => selectedFilePath != null;
  double? get compressionRatio {
    if (selectedFileSize == null || outputFileSize == null) return null;
    if (selectedFileSize == 0) return null;
    final ratio = (1 - (outputFileSize! / selectedFileSize!)) * 100;
    return ratio.isFinite ? ratio : null;
  }

  PdfCompressState copyWith({
    String? selectedFilePath,
    String? selectedFileName,
    int? selectedFileSize,
    CompressionLevel? compressionLevel,
    int? colorImageQuality,
    int? greyImageQuality,
    int? monoImageQuality,
    bool? compressStreams,
    bool? unembedSimpleFonts,
    bool? unembedComplexFonts,
    bool? unembedUnusualFonts,
    bool? flattenLayers,
    bool? isAdvancedExpanded,
    bool? isProcessing,
    double? progress,
    String? errorMessage,
    String? note,
    String? outputPath,
    int? outputFileSize,
    String? publicExportPath,
  }) {
    return PdfCompressState(
      selectedFilePath: selectedFilePath ?? this.selectedFilePath,
      selectedFileName: selectedFileName ?? this.selectedFileName,
      selectedFileSize: selectedFileSize ?? this.selectedFileSize,
      compressionLevel: compressionLevel ?? this.compressionLevel,
      colorImageQuality: colorImageQuality ?? this.colorImageQuality,
      greyImageQuality: greyImageQuality ?? this.greyImageQuality,
      monoImageQuality: monoImageQuality ?? this.monoImageQuality,
      compressStreams: compressStreams ?? this.compressStreams,
      unembedSimpleFonts: unembedSimpleFonts ?? this.unembedSimpleFonts,
      unembedComplexFonts: unembedComplexFonts ?? this.unembedComplexFonts,
      unembedUnusualFonts: unembedUnusualFonts ?? this.unembedUnusualFonts,
      flattenLayers: flattenLayers ?? this.flattenLayers,
      isAdvancedExpanded: isAdvancedExpanded ?? this.isAdvancedExpanded,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      note: note,
      outputPath: outputPath ?? this.outputPath,
      outputFileSize: outputFileSize ?? this.outputFileSize,
      publicExportPath: publicExportPath ?? this.publicExportPath,
    );
  }

  PdfCompressState reset() {
    return const PdfCompressState();
  }
}

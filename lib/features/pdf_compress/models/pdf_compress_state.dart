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

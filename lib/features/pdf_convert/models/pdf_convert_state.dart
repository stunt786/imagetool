import 'package:flutter/foundation.dart';

/// Output format for PDF conversion.
enum ConvertFormat {
  jpg('JPG', 'jpg', 'JPEG image format, smaller file size'),
  png('PNG', 'png', 'PNG image format, lossless quality'),
  txt('TXT', 'txt', 'OCR text extraction'),
  docx('DOCX', 'docx', 'OCR with table detection');

  const ConvertFormat(this.label, this.extension, this.description);
  final String label;
  final String extension;
  final String description;
}

/// DPI options for image conversion.
enum ConvertDpi {
  low('Low (72 DPI)', 72),
  medium('Medium (150 DPI)', 150),
  high('High (300 DPI)', 300);

  const ConvertDpi(this.label, this.value);
  final String label;
  final int value;
}

/// State for the PDF convert feature.
@immutable
class PdfConvertState {
  const PdfConvertState({
    this.selectedFilePath,
    this.selectedFileName,
    this.selectedFileSize,
    this.pageCount,
    this.outputFormat = ConvertFormat.jpg,
    this.dpi = ConvertDpi.medium,
    this.isProcessing = false,
    this.progress = 0.0,
    this.errorMessage,
    this.outputPaths = const [],
    this.publicExportPaths = const [],
  });

  final String? selectedFilePath;
  final String? selectedFileName;
  final int? selectedFileSize;
  final int? pageCount;
  final ConvertFormat outputFormat;
  final ConvertDpi dpi;
  final bool isProcessing;
  final double progress;
  final String? errorMessage;
  final List<String> outputPaths;
  final List<String> publicExportPaths;

  bool get hasFile => selectedFilePath != null;
  bool get hasPageInfo => pageCount != null && pageCount! > 0;
  bool get canConvert => hasFile && !isProcessing;

  PdfConvertState copyWith({
    String? selectedFilePath,
    String? selectedFileName,
    int? selectedFileSize,
    int? pageCount,
    ConvertFormat? outputFormat,
    ConvertDpi? dpi,
    bool? isProcessing,
    double? progress,
    String? errorMessage,
    List<String>? outputPaths,
    List<String>? publicExportPaths,
  }) {
    return PdfConvertState(
      selectedFilePath: selectedFilePath ?? this.selectedFilePath,
      selectedFileName: selectedFileName ?? this.selectedFileName,
      selectedFileSize: selectedFileSize ?? this.selectedFileSize,
      pageCount: pageCount ?? this.pageCount,
      outputFormat: outputFormat ?? this.outputFormat,
      dpi: dpi ?? this.dpi,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      outputPaths: outputPaths ?? this.outputPaths,
      publicExportPaths: publicExportPaths ?? this.publicExportPaths,
    );
  }

  PdfConvertState reset() {
    return const PdfConvertState();
  }
}

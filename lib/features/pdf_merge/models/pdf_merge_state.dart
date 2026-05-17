import 'package:flutter/foundation.dart';

/// Represents a PDF file in the merge queue.
@immutable
class MergePdfItem {
  const MergePdfItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.pageCount,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final int? pageCount;

  MergePdfItem copyWith({int? pageCount}) {
    return MergePdfItem(
      path: path,
      name: name,
      sizeBytes: sizeBytes,
      pageCount: pageCount ?? this.pageCount,
    );
  }
}

/// State for the PDF merge feature.
@immutable
class PdfMergeState {
  const PdfMergeState({
    this.files = const [],
    this.isProcessing = false,
    this.progress = 0.0,
    this.errorMessage,
    this.outputPath,
  });

  final List<MergePdfItem> files;
  final bool isProcessing;
  final double progress;
  final String? errorMessage;
  final String? outputPath;

  bool get hasFiles => files.isNotEmpty;
  bool get canMerge => files.length >= 2 && !isProcessing;

  PdfMergeState copyWith({
    List<MergePdfItem>? files,
    bool? isProcessing,
    double? progress,
    String? errorMessage,
    String? outputPath,
  }) {
    return PdfMergeState(
      files: files ?? this.files,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      outputPath: outputPath ?? this.outputPath,
    );
  }

  PdfMergeState reorderFiles(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return this;
    final newFiles = List<MergePdfItem>.from(files);
    final item = newFiles.removeAt(oldIndex);
    newFiles.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    return copyWith(files: newFiles);
  }

  PdfMergeState removeFile(int index) {
    final newFiles = List<MergePdfItem>.from(files);
    newFiles.removeAt(index);
    return copyWith(files: newFiles);
  }

  PdfMergeState updateFile(int index, MergePdfItem item) {
    final newFiles = List<MergePdfItem>.from(files);
    newFiles[index] = item;
    return copyWith(files: newFiles);
  }

  PdfMergeState reset() {
    return const PdfMergeState();
  }
}

import 'package:flutter/foundation.dart';

/// Split mode for PDF splitting.
enum SplitMode {
  allPages('All Pages', 'Split each page into a separate PDF'),
  pageRange('Page Range', 'Extract specific pages into one PDF'),
  byChunks('By Chunks', 'Split into groups of N pages');

  const SplitMode(this.label, this.description);
  final String label;
  final String description;
}

/// State for the PDF split feature.
@immutable
class PdfSplitState {
  const PdfSplitState({
    this.selectedFilePath,
    this.selectedFileName,
    this.selectedFileSize,
    this.pageCount,
    this.splitMode = SplitMode.allPages,
    this.chunkSize = 5,
    this.selectedPages = const {},
    this.isProcessing = false,
    this.progress = 0.0,
    this.errorMessage,
    this.outputPaths = const [],
  });

  final String? selectedFilePath;
  final String? selectedFileName;
  final int? selectedFileSize;
  final int? pageCount;
  final SplitMode splitMode;
  final int chunkSize;
  final Set<int> selectedPages; // 1-indexed page numbers
  final bool isProcessing;
  final double progress;
  final String? errorMessage;
  final List<String> outputPaths;

  bool get hasFile => selectedFilePath != null;
  bool get hasPageInfo => pageCount != null && pageCount! > 0;
  bool get canSplit {
    if (!hasFile || !hasPageInfo) return false;
    switch (splitMode) {
      case SplitMode.allPages:
        return true;
      case SplitMode.pageRange:
        return selectedPages.isNotEmpty;
      case SplitMode.byChunks:
        return chunkSize >= 1 && chunkSize <= (pageCount ?? 0);
    }
  }

  PdfSplitState copyWith({
    String? selectedFilePath,
    String? selectedFileName,
    int? selectedFileSize,
    int? pageCount,
    SplitMode? splitMode,
    int? chunkSize,
    Set<int>? selectedPages,
    bool? isProcessing,
    double? progress,
    String? errorMessage,
    List<String>? outputPaths,
  }) {
    return PdfSplitState(
      selectedFilePath: selectedFilePath ?? this.selectedFilePath,
      selectedFileName: selectedFileName ?? this.selectedFileName,
      selectedFileSize: selectedFileSize ?? this.selectedFileSize,
      pageCount: pageCount ?? this.pageCount,
      splitMode: splitMode ?? this.splitMode,
      chunkSize: chunkSize ?? this.chunkSize,
      selectedPages: selectedPages ?? this.selectedPages,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      errorMessage: errorMessage,
      outputPaths: outputPaths ?? this.outputPaths,
    );
  }

  PdfSplitState togglePage(int pageNumber) {
    final newPages = Set<int>.from(selectedPages);
    if (newPages.contains(pageNumber)) {
      newPages.remove(pageNumber);
    } else {
      newPages.add(pageNumber);
    }
    return copyWith(selectedPages: newPages);
  }

  PdfSplitState selectAllPages() {
    if (pageCount == null) return this;
    return copyWith(
      selectedPages: Set.from(List.generate(pageCount!, (i) => i + 1)),
    );
  }

  PdfSplitState clearPageSelection() {
    return copyWith(selectedPages: {});
  }

  PdfSplitState reset() {
    return const PdfSplitState();
  }
}

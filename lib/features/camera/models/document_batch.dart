import 'package:flutter/foundation.dart';

import 'scanned_page.dart';

@immutable
class DocumentBatch {
  const DocumentBatch({
    required this.id,
    required this.pages,
    this.createdAt,
  });

  final String id;
  final List<ScannedPage> pages;
  final DateTime? createdAt;

  int get pageCount => pages.length;

  DocumentBatch copyWith({
    String? id,
    List<ScannedPage>? pages,
    DateTime? createdAt,
  }) {
    return DocumentBatch(
      id: id ?? this.id,
      pages: pages ?? this.pages,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  DocumentBatch addPage(ScannedPage page) {
    return copyWith(pages: [...pages, page]);
  }

  DocumentBatch removePage(int index) {
    if (index < 0 || index >= pages.length) return this;
    final newPages = List<ScannedPage>.from(pages)..removeAt(index);
    return copyWith(pages: newPages);
  }

  DocumentBatch reorderPages(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return this;
    final newPages = List<ScannedPage>.from(pages);
    final item = newPages.removeAt(oldIndex);
    newPages.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    return copyWith(pages: newPages);
  }

  DocumentBatch updatePage(int index, ScannedPage page) {
    if (index < 0 || index >= pages.length) return this;
    final newPages = List<ScannedPage>.from(pages);
    newPages[index] = page;
    return copyWith(pages: newPages);
  }

  bool get hasPages => pages.isNotEmpty;
}

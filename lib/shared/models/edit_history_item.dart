import 'dart:convert';

import 'package:flutter/material.dart';

/// Represents one recently-edited file shown in the history strip.
class EditHistoryItem {
  const EditHistoryItem({
    required this.fileName,
    required this.toolUsed,
    required this.editedAt,
    this.filePath,
    this.thumbnailPath,
    this.toolIcon = Icons.image_outlined,
    this.compressionLevel,
    this.isGroup = false,
    this.groupCount,
    this.pagePaths,
  });

  final String fileName;
  final String toolUsed;
  final DateTime editedAt;

  /// Actual saved file path on disk (for open/share actions).
  final String? filePath;
  final String? thumbnailPath;
  final IconData toolIcon;
  final String? compressionLevel;

  /// True when this entry represents a batch operation (multiple files).
  final bool isGroup;

  /// Number of files in the batch group.
  final int? groupCount;

  /// Pages retained for a scanner document. Keeping these paths lets Files
  /// reopen the complete scan rather than only its first thumbnail.
  final List<String>? pagePaths;

  /// Friendly relative-time label
  String get timeAgo {
    final diff = DateTime.now().difference(editedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${editedAt.day}/${editedAt.month}/${editedAt.year}';
  }

  EditHistoryItem copyWith({
    String? fileName,
    String? toolUsed,
    DateTime? editedAt,
    String? filePath,
    String? thumbnailPath,
    IconData? toolIcon,
    String? compressionLevel,
    bool? isGroup,
    int? groupCount,
    List<String>? pagePaths,
  }) {
    return EditHistoryItem(
      fileName: fileName ?? this.fileName,
      toolUsed: toolUsed ?? this.toolUsed,
      editedAt: editedAt ?? this.editedAt,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      toolIcon: toolIcon ?? this.toolIcon,
      compressionLevel: compressionLevel ?? this.compressionLevel,
      isGroup: isGroup ?? this.isGroup,
      groupCount: groupCount ?? this.groupCount,
      pagePaths: pagePaths ?? this.pagePaths,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'toolUsed': toolUsed,
      'editedAt': editedAt.toIso8601String(),
      'filePath': filePath,
      'thumbnailPath': thumbnailPath,
      'toolIconCodePoint': toolIcon.codePoint,
      'toolIconFontFamily': toolIcon.fontFamily,
      'compressionLevel': compressionLevel,
      'isGroup': isGroup,
      'groupCount': groupCount,
      'pagePaths': pagePaths,
    };
  }

  /// Every icon a history entry can persist. Icons must be declared as const
  /// literals (not built from a code point at runtime) so the release build
  /// can tree shake the Material icon font.
  static const List<IconData> _knownIcons = [
    Icons.image_outlined,
    Icons.call_split_rounded,
    Icons.dashboard_customize_rounded,
    Icons.photo_size_select_large_rounded,
    Icons.rotate_right_rounded,
    Icons.flip_rounded,
    Icons.compress_rounded,
    Icons.crop_rounded,
    Icons.merge_type_rounded,
    Icons.document_scanner_outlined,
    Icons.picture_as_pdf_outlined,
    Icons.transform_rounded,
    Icons.picture_as_pdf_rounded,
    Icons.swap_horiz_rounded,
  ];

  static IconData _iconForCodePoint(int? codePoint) {
    if (codePoint != null) {
      for (final icon in _knownIcons) {
        if (icon.codePoint == codePoint) return icon;
      }
    }
    return Icons.image_outlined;
  }

  factory EditHistoryItem.fromJson(Map<String, dynamic> json) {
    final codePoint = json['toolIconCodePoint'] as int?;
    return EditHistoryItem(
      fileName: json['fileName'] as String? ?? '',
      toolUsed: json['toolUsed'] as String? ?? '',
      editedAt: DateTime.tryParse(json['editedAt'] as String? ?? '') ??
          DateTime.now(),
      filePath: json['filePath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      toolIcon: _iconForCodePoint(codePoint),
      compressionLevel: json['compressionLevel'] as String?,
      isGroup: json['isGroup'] as bool? ?? false,
      groupCount: json['groupCount'] as int?,
      pagePaths:
          (json['pagePaths'] as List<dynamic>?)?.whereType<String>().toList(),
    );
  }

  static String encodeList(List<EditHistoryItem> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }

  static List<EditHistoryItem> decodeList(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(EditHistoryItem.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

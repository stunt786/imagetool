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

  /// Friendly relative-time label
  String get timeAgo {
    final diff = DateTime.now().difference(editedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${editedAt.day}/${editedAt.month}/${editedAt.year}';
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
    };
  }

  factory EditHistoryItem.fromJson(Map<String, dynamic> json) {
    final codePoint = json['toolIconCodePoint'] as int? ?? Icons.image_outlined.codePoint;
    final fontFamily = json['toolIconFontFamily'] as String? ?? 'MaterialIcons';
    return EditHistoryItem(
      fileName: json['fileName'] as String? ?? '',
      toolUsed: json['toolUsed'] as String? ?? '',
      editedAt: DateTime.tryParse(json['editedAt'] as String? ?? '') ?? DateTime.now(),
      filePath: json['filePath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      toolIcon: IconData(codePoint, fontFamily: fontFamily),
      compressionLevel: json['compressionLevel'] as String?,
      isGroup: json['isGroup'] as bool? ?? false,
      groupCount: json['groupCount'] as int?,
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

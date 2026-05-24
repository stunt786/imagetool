import 'package:flutter/material.dart';

/// Represents one recently-edited file shown in the history strip.
class EditHistoryItem {
  const EditHistoryItem({
    required this.fileName,
    required this.toolUsed,
    required this.editedAt,
    this.thumbnailPath,
    this.toolIcon = Icons.image_outlined,
    this.compressionLevel,
  });

  final String fileName;
  final String toolUsed;
  final DateTime editedAt;
  final String? thumbnailPath;
  final IconData toolIcon;
  final String? compressionLevel;

  /// Friendly relative-time label (e.g. "2 min ago", "Yesterday").
  String get timeAgo {
    final diff = DateTime.now().difference(editedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${editedAt.day}/${editedAt.month}/${editedAt.year}';
  }
}

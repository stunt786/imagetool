import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/edit_history_item.dart';

/// Maximum number of history items to retain.
const _maxHistoryItems = 20;

/// Provides the list of recently-edited files, newest first.
final editHistoryProvider =
    StateNotifierProvider<EditHistoryNotifier, List<EditHistoryItem>>((ref) {
  return EditHistoryNotifier();
});

class EditHistoryNotifier extends StateNotifier<List<EditHistoryItem>> {
  EditHistoryNotifier() : super(_demoData);

  /// Adds a new entry at the top of the list.
  void addEntry(EditHistoryItem item) {
    state = [item, ...state].take(_maxHistoryItems).toList();
  }

  /// Clears all history.
  void clear() => state = [];

  // ── Sample data so the UI is populated on first launch ──────────────

  static final _now = DateTime.now();

  static final List<EditHistoryItem> _demoData = [
    EditHistoryItem(
      fileName: 'vacation_photo.jpg',
      toolUsed: 'Image Resizer',
      editedAt: _now.subtract(const Duration(minutes: 3)),
      toolIcon: Icons.photo_size_select_large,
    ),
    EditHistoryItem(
      fileName: 'family_collage.png',
      toolUsed: 'Collage Builder',
      editedAt: _now.subtract(const Duration(minutes: 25)),
      toolIcon: Icons.grid_view_rounded,
    ),
    EditHistoryItem(
      fileName: 'report_2026.pdf',
      toolUsed: 'PDF Compressor',
      editedAt: _now.subtract(const Duration(hours: 1)),
      toolIcon: Icons.compress,
    ),
    EditHistoryItem(
      fileName: 'sunset_panorama.jpg',
      toolUsed: 'Format Converter',
      editedAt: _now.subtract(const Duration(hours: 3)),
      toolIcon: Icons.transform,
    ),
    EditHistoryItem(
      fileName: 'invoice_scan.pdf',
      toolUsed: 'Image to PDF',
      editedAt: _now.subtract(const Duration(hours: 8)),
      toolIcon: Icons.picture_as_pdf,
    ),
    EditHistoryItem(
      fileName: 'profile_pic.webp',
      toolUsed: 'Image Resizer',
      editedAt: _now.subtract(const Duration(days: 1)),
      toolIcon: Icons.photo_size_select_large,
    ),
  ];
}

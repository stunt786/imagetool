import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/edit_history_item.dart';

const _maxHistoryItems = 20;
const _historyKey = 'edit_history_v1';

/// Provides the list of recently-edited files, newest first.
/// History is persisted across app restarts via SharedPreferences.
final editHistoryProvider =
    StateNotifierProvider<EditHistoryNotifier, List<EditHistoryItem>>((ref) {
  return EditHistoryNotifier();
});

class EditHistoryNotifier extends StateNotifier<List<EditHistoryItem>> {
  EditHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_historyKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final loaded = EditHistoryItem.decodeList(jsonStr);
        if (mounted) state = loaded;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historyKey, EditHistoryItem.encodeList(state));
    } catch (_) {}
  }

  /// Adds a new single entry at the top of the list.
  void addEntry(EditHistoryItem item) {
    state = [item, ...state].take(_maxHistoryItems).toList();
    _save();
  }

  /// Adds a batch/group entry at the top (for multi-file operations).
  void addGroup({
    required String toolName,
    required IconData toolIcon,
    required int count,
    String? thumbnailPath,
    String? filePath,
  }) {
    final item = EditHistoryItem(
      fileName: '$toolName ($count files)',
      toolUsed: toolName,
      editedAt: DateTime.now(),
      filePath: filePath,
      thumbnailPath: thumbnailPath,
      toolIcon: toolIcon,
      isGroup: true,
      groupCount: count,
    );
    state = [item, ...state].take(_maxHistoryItems).toList();
    _save();
  }

  /// Removes a specific entry from history.
  void removeEntry(EditHistoryItem item) {
    state = state.where((e) => e != item).toList();
    _save();
  }

  /// Clears all history.
  void clear() {
    state = [];
    _save();
  }
}

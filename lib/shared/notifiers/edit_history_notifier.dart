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
  EditHistoryNotifier() : super([]);

  /// Adds a new entry at the top of the list.
  void addEntry(EditHistoryItem item) {
    state = [item, ...state].take(_maxHistoryItems).toList();
  }

  /// Removes a specific entry from history.
  void removeEntry(EditHistoryItem item) {
    state = state.where((e) => e != item).toList();
  }

  /// Clears all history.
  void clear() => state = [];
}

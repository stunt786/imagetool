import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/picked_file.dart';
import '../services/file_picker_service.dart';

@immutable
class PickedFilesState {
  const PickedFilesState({
    required this.files,
    required this.isPicking,
    required this.errorMessage,
  });

  const PickedFilesState.initial()
      : files = const <PickedFile>[],
        isPicking = false,
        errorMessage = null;

  final List<PickedFile> files;
  final bool isPicking;
  final String? errorMessage;

  PickedFilesState copyWith({
    List<PickedFile>? files,
    bool? isPicking,
    String? errorMessage,
  }) {
    return PickedFilesState(
      files: files ?? this.files,
      isPicking: isPicking ?? this.isPicking,
      errorMessage: errorMessage,
    );
  }
}

final pickedFilesProvider = NotifierProvider.family<
    PickedFilesNotifier,
    PickedFilesState,
    PickTarget>(PickedFilesNotifier.new);

class PickedFilesNotifier extends FamilyNotifier<PickedFilesState, PickTarget> {
  @override
  PickedFilesState build(PickTarget arg) => const PickedFilesState.initial();

  Future<void> pick(BuildContext context, {bool allowMultiple = true}) async {
    state = state.copyWith(isPicking: true, errorMessage: null);
    try {
      final picked = await ref.read(filePickerServiceProvider).pick(
            context: context,
            target: arg,
            allowMultiple: allowMultiple,
          );
      if (picked.isEmpty) {
        state = state.copyWith(isPicking: false);
        return;
      }
      state = state.copyWith(
        isPicking: false,
        files: <PickedFile>[...state.files, ...picked],
      );
    } catch (e) {
      state = state.copyWith(isPicking: false, errorMessage: e.toString());
    }
  }

  void clear() {
    state = const PickedFilesState.initial();
  }
}

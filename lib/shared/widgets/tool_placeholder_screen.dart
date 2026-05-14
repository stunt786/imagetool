import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/picked_files_notifier.dart';
import '../services/file_picker_service.dart';
import 'empty_state.dart';

class ToolPlaceholderScreen extends ConsumerWidget {
  const ToolPlaceholderScreen({
    super.key,
    required this.title,
    required this.description,
    required this.pickTarget,
  });

  final String title;
  final String description;
  final PickTarget pickTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pickedFilesProvider(pickTarget));
    final notifier = ref.read(pickedFilesProvider(pickTarget).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: state.files.isEmpty ? null : notifier.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: state.isPicking ? null : () => notifier.pick(),
                  icon: state.isPicking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(state.isPicking ? 'Picking…' : 'Pick files'),
                ),
              ],
            ),
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.errorMessage!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: state.files.isEmpty
                ? const EmptyState(
                    icon: Icons.folder_open,
                    title: 'No files selected',
                    message:
                        'Pick a few files to validate the selection pipeline. Processing is added in later phases.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final file = state.files[index];
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(file.name),
                        subtitle: Text(
                          [
                            if (file.extension != null) file.extension,
                            '${(file.sizeBytes / 1024).toStringAsFixed(1)} KB',
                            if (file.path != null) 'path available',
                          ].whereType<String>().join(' · '),
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemCount: state.files.length,
                  ),
          ),
        ],
      ),
    );
  }
}


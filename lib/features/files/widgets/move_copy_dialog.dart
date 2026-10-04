import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifiers/operation_library_notifier.dart';

/// Dialog allowing user to Move or Copy selected files to another operation folder.
class MoveCopyDialog extends ConsumerStatefulWidget {
  const MoveCopyDialog({
    super.key,
    required this.fileIds,
    required this.currentOperationId,
  });

  final List<String> fileIds;
  final String currentOperationId;

  static Future<bool?> show(
    BuildContext context, {
    required List<String> fileIds,
    required String currentOperationId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => MoveCopyDialog(
        fileIds: fileIds,
        currentOperationId: currentOperationId,
      ),
    );
  }

  @override
  ConsumerState<MoveCopyDialog> createState() => _MoveCopyDialogState();
}

class _MoveCopyDialogState extends ConsumerState<MoveCopyDialog> {
  String? _selectedTargetId;
  bool _isCopy = false; // false = Move, true = Copy

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(operationLibraryProvider);
    final available = library.operations
        .where((op) => op.id != widget.currentOperationId)
        .toList();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isCopy ? Icons.copy_rounded : Icons.drive_file_move_outlined,
            color: const Color(0xFF00E5FF),
          ),
          const SizedBox(width: 8),
          Text(_isCopy ? 'Copy Files' : 'Move Files'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode toggle: Move vs Copy
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Move')),
                    selected: !_isCopy,
                    onSelected: (val) {
                      if (val) setState(() => _isCopy = false);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Copy')),
                    selected: _isCopy,
                    onSelected: (val) {
                      if (val) setState(() => _isCopy = true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Destination Folder:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: available.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No other folders available.'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: available.length,
                      itemBuilder: (context, index) {
                        final op = available[index];
                        final isSelected = _selectedTargetId == op.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          leading: Icon(
                            Icons.folder_rounded,
                            color: isSelected
                                ? const Color(0xFF00E5FF)
                                : scheme.primary,
                          ),
                          title: Text(
                            op.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text('${op.itemCount} file(s)'),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF00E5FF),
                                )
                              : null,
                          onTap: () =>
                              setState(() => _selectedTargetId = op.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
          ),
          onPressed: _selectedTargetId == null ? null : _submit,
          child: Text(
            _isCopy ? 'Copy Here' : 'Move Here',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_selectedTargetId == null) return;
    final notifier = ref.read(operationLibraryProvider.notifier);
    if (_isCopy) {
      final count =
          await notifier.copyFiles(widget.fileIds, _selectedTargetId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count file(s) copied.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } else {
      final count =
          await notifier.moveFiles(widget.fileIds, _selectedTargetId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count file(s) moved.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }
}

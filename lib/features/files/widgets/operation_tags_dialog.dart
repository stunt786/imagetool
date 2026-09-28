import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operation_folder.dart';
import '../notifiers/operation_library_notifier.dart';

/// Tag selector dialog matching the `Tags +` chip in `prev.jpg`.
class OperationTagsDialog extends ConsumerStatefulWidget {
  const OperationTagsDialog({
    super.key,
    required this.operation,
  });

  final OperationFolder operation;

  static Future<void> show(
    BuildContext context, {
    required OperationFolder operation,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => OperationTagsDialog(operation: operation),
    );
  }

  @override
  ConsumerState<OperationTagsDialog> createState() =>
      _OperationTagsDialogState();
}

class _OperationTagsDialogState extends ConsumerState<OperationTagsDialog> {
  late final List<String> _tags;
  final TextEditingController _customController = TextEditingController();

  static const List<String> _presetTags = [
    'Tax',
    'Work',
    'Personal',
    'Invoice',
    'Receipt',
    'Important',
    'Medical',
    'School',
    'Legal',
  ];

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.operation.tags);
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    setState(() {
      if (_tags.contains(tag)) {
        _tags.remove(tag);
      } else {
        _tags.add(tag);
      }
    });
  }

  void _addCustom() {
    final custom = _customController.text.trim();
    if (custom.isNotEmpty && !_tags.contains(custom)) {
      setState(() {
        _tags.add(custom);
        _customController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.label_outline_rounded, color: Color(0xFF00E5FF)),
          SizedBox(width: 8),
          Text('Manage Tags'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select or add tags for this folder:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _presetTags)
                  FilterChip(
                    label: Text(tag),
                    selected: _tags.contains(tag),
                    selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                    checkmarkColor: const Color(0xFF00E5FF),
                    onSelected: (_) => _toggle(tag),
                  ),
                for (final tag in _tags)
                  if (!_presetTags.contains(tag))
                    Chip(
                      label: Text(tag),
                      backgroundColor:
                          const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                    ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    decoration: const InputDecoration(
                      hintText: 'Add custom tag...',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addCustom(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFF00E5FF)),
                  onPressed: _addCustom,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
          ),
          onPressed: () async {
            await ref
                .read(operationLibraryProvider.notifier)
                .updateOperationTags(widget.operation.id, _tags);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(
            'Save Tags',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

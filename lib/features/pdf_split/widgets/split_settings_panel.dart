import 'package:flutter/material.dart';

import '../models/pdf_split_state.dart';

class SplitSettingsPanel extends StatelessWidget {
  const SplitSettingsPanel({
    super.key,
    required this.state,
    required this.onModeChanged,
    required this.onChunkSizeChanged,
    required this.onTogglePage,
    required this.onSelectAll,
    required this.onClearSelection,
  });

  final PdfSplitState state;
  final ValueChanged<SplitMode> onModeChanged;
  final ValueChanged<int> onChunkSizeChanged;
  final ValueChanged<int> onTogglePage;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Split Mode',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Mode selector
          ...SplitMode.values.map((mode) {
            final isSelected = mode == state.splitMode;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => onModeChanged(mode),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Radio<SplitMode>(
                          value: mode,
                          groupValue: state.splitMode,
                          onChanged: (_) => onModeChanged(mode),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mode.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                mode.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Chunk size input
          if (state.splitMode == SplitMode.byChunks) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Pages per chunk:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    controller: TextEditingController(
                      text: state.chunkSize.toString(),
                    ),
                    onChanged: (value) {
                      final size = int.tryParse(value);
                      if (size != null && size >= 1) {
                        onChunkSizeChanged(size);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],

          // Page range selector
          if (state.splitMode == SplitMode.pageRange && state.hasPageInfo) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Select Pages (${state.selectedPages.length}/${state.pageCount})',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onSelectAll,
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: onClearSelection,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(state.pageCount!, (index) {
                final pageNum = index + 1;
                final isSelected = state.selectedPages.contains(pageNum);
                return Material(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onTogglePage(pageNum),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Text(
                        '$pageNum',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

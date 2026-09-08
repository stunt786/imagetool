import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pdf_convert_state.dart';

class ConvertSettingsPanel extends StatefulWidget {
  const ConvertSettingsPanel({
    super.key,
    required this.state,
    required this.onFormatChanged,
    required this.onDpiChanged,
    required this.onPageRangeChanged,
  });

  final PdfConvertState state;
  final ValueChanged<ConvertFormat> onFormatChanged;
  final ValueChanged<ConvertDpi> onDpiChanged;
  final void Function(int? start, int? end) onPageRangeChanged;

  @override
  State<ConvertSettingsPanel> createState() => _ConvertSettingsPanelState();
}

class _ConvertSettingsPanelState extends State<ConvertSettingsPanel> {
  late TextEditingController _startController;
  late TextEditingController _endController;
  final _startFocusNode = FocusNode();
  final _endFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(
      text: widget.state.pageRangeStart?.toString() ?? '',
    );
    _endController = TextEditingController(
      text: widget.state.pageRangeEnd?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant ConvertSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.state.usePageRange && oldWidget.state.usePageRange) {
      _startController.clear();
      _endController.clear();
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _startFocusNode.dispose();
    _endFocusNode.dispose();
    super.dispose();
  }

  void _applyRange() {
    final start = int.tryParse(_startController.text);
    final end = int.tryParse(_endController.text);
    if (start != null && end != null && start >= 1 && end >= start) {
      widget.onPageRangeChanged(start, end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImageFormat = widget.state.outputFormat == ConvertFormat.jpg ||
        widget.state.outputFormat == ConvertFormat.png;
    final pageCount = widget.state.pageCount ?? 0;
    final useCustomRange = widget.state.usePageRange;

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
            'Output Format',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          ...ConvertFormat.values.map((format) {
            final isSelected = format == widget.state.outputFormat;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => widget.onFormatChanged(format),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Radio<ConvertFormat>(
                          value: format,
                          // ignore: deprecated_member_use
                          onChanged: (_) => widget.onFormatChanged(format),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                format.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                format.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          if (isImageFormat) ...[
            const SizedBox(height: 16),
            Text(
              'Resolution (DPI)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...ConvertDpi.values.map((dpi) {
              final isSelected = dpi == widget.state.dpi;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => widget.onDpiChanged(dpi),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<ConvertDpi>(
                            value: dpi,
                            // ignore: deprecated_member_use
                            onChanged: (_) => widget.onDpiChanged(dpi),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dpi.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
          Text(
            'Pages to convert',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (pageCount > 0) ...[
            Material(
              color: !useCustomRange
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => widget.onPageRangeChanged(null, null),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Radio<bool>(
                        value: false,
                        groupValue: useCustomRange,
                        // ignore: deprecated_member_use
                        onChanged: (_) =>
                            widget.onPageRangeChanged(null, null),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'All pages ($pageCount)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Material(
              color: useCustomRange
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () {
                  final start =
                      int.tryParse(_startController.text) ?? 1;
                  final end = int.tryParse(_endController.text) ??
                      pageCount;
                  widget.onPageRangeChanged(
                    start.clamp(1, pageCount),
                    end.clamp(1, pageCount),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Radio<bool>(
                        value: true,
                        groupValue: useCustomRange,
                        // ignore: deprecated_member_use
                        onChanged: (_) {
                          final start =
                              int.tryParse(_startController.text) ?? 1;
                          final end = int.tryParse(_endController.text) ??
                              pageCount;
                          widget.onPageRangeChanged(
                            start.clamp(1, pageCount),
                            end.clamp(1, pageCount),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Custom range',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (useCustomRange) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      focusNode: _startFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Start page',
                        hintText: '1',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _applyRange(),
                      onSubmitted: (_) {
                        _endFocusNode.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endController,
                      focusNode: _endFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: 'End page',
                        hintText: '$pageCount',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _applyRange(),
                      onSubmitted: (_) => _applyRange(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Range: 1 – $pageCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ] else ...[
            Text(
              'Load a PDF to select pages',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          if (widget.state.outputFormat == ConvertFormat.txt ||
              widget.state.outputFormat == ConvertFormat.docx) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.state.outputFormat == ConvertFormat.docx
                          ? 'Text extracted via OCR with table detection. Complex layouts may vary.'
                          : 'Text extracted via OCR. Images and tables are not included.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

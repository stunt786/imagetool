import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scanned_page.dart';
import '../../notifiers/document_batch_notifier.dart';
import '../../services/image_filter_service.dart';

/// Popup modal for the Enhance tool.
///
/// Filters preview instantly (low-resolution pass, non-blocking) so the user
/// never has to stare at a loading spinner. Tapping Apply commits the chosen
/// filter right away using the preview bytes and then upgrades the page to
/// full resolution in the background.
class EnhanceFiltersSheet extends ConsumerStatefulWidget {
  const EnhanceFiltersSheet({super.key, required this.pageIndex});

  final int pageIndex;

  @override
  ConsumerState<EnhanceFiltersSheet> createState() => _EnhanceFiltersSheetState();
}

class _EnhanceFiltersSheetState extends ConsumerState<EnhanceFiltersSheet> {
  FilterType _selectedFilter = FilterType.none;
  Uint8List? _previewBytes;
  bool _isPreviewing = false;
  bool _isApplying = false;
  int _previewRequest = 0;

  @override
  void initState() {
    super.initState();
    final batch = ref.read(documentBatchProvider);
    if (widget.pageIndex >= 0 && widget.pageIndex < batch.pages.length) {
      _selectedFilter = batch.pages[widget.pageIndex].filterType;
    }
  }

  Future<void> _selectFilter(FilterType filterType) async {
    final request = ++_previewRequest;
    final batch = ref.read(documentBatchProvider);
    if (widget.pageIndex < 0 || widget.pageIndex >= batch.pages.length) return;
    final page = batch.pages[widget.pageIndex];
    if (!page.isLoaded) return;

    setState(() {
      _selectedFilter = filterType;
      _previewBytes = null;
      _isPreviewing = filterType != FilterType.none;
    });

    try {
      if (filterType != FilterType.none) {
        final result =
            await ImageFilterService.applyPreview(page.imageBytes!, filterType);
        if (!mounted || request != _previewRequest || result == null) return;
        setState(() => _previewBytes = result.bytes);
      }
    } finally {
      if (mounted && request == _previewRequest) {
        setState(() => _isPreviewing = false);
      }
    }
  }

  Future<void> _apply() async {
    if (_isApplying) return;
    final batch = ref.read(documentBatchProvider);
    if (widget.pageIndex < 0 || widget.pageIndex >= batch.pages.length) return;

    final notifier = ref.read(documentBatchProvider.notifier);
    final filter = _selectedFilter;
    final preview = _previewBytes;

    setState(() => _isApplying = true);
    try {
      if (filter == FilterType.none) {
        await notifier.applyFilterToPage(widget.pageIndex, FilterType.none);
      } else if (preview != null) {
        final current =
            ref.read(documentBatchProvider).pages[widget.pageIndex];
        notifier.updatePage(
          widget.pageIndex,
          current.copyWith(
            filteredBytes: preview,
            filterType: filter,
          ),
        );
      } else {
        await notifier.applyFilterToPage(widget.pageIndex, filter);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }

    // Upgrade the freshly applied preview to full resolution.
    if (filter != FilterType.none && preview != null) {
      await notifier.applyFilterToPage(widget.pageIndex, filter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(documentBatchProvider);
    final page = widget.pageIndex >= 0 && widget.pageIndex < batch.pages.length
        ? batch.pages[widget.pageIndex]
        : null;

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF25262A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: page == null || !page.isLoaded
            ? const Center(
                child: Text('No page to enhance',
                    style: TextStyle(color: Colors.white54)),
              )
            : Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Enhance',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Page ${widget.pageIndex + 1} of ${batch.pageCount}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _buildPreview(page)),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Filters',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filterOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final option = _filterOptions[index];
                        return _FilterTile(
                          icon: option.icon,
                          title: option.label,
                          isSelected: _selectedFilter == option.type,
                          onTap: () => _selectFilter(option.type),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isApplying ? null : _apply,
                    icon: _isApplying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 20),
                    label: Text(_isApplying ? 'Applying…' : 'Apply'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF2F80ED),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPreview(ScannedPage page) {
    final Uint8List previewSource;
    if (_previewBytes != null) {
      previewSource = _previewBytes!;
    } else if (_selectedFilter == FilterType.none) {
      previewSource = page.imageBytes ?? page.displayBytes;
    } else {
      previewSource = page.displayBytes;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            previewSource,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.black54, size: 40),
            ),
          ),
          if (_isPreviewing)
            const Positioned(
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.type, this.icon, this.label);
  final FilterType type;
  final IconData icon;
  final String label;
}

final List<_FilterOption> _filterOptions = [
  const _FilterOption(FilterType.none, Icons.auto_fix_high, 'Original'),
  const _FilterOption(FilterType.lighten, Icons.wb_sunny_outlined, 'Lighten'),
  const _FilterOption(FilterType.enhance, Icons.auto_awesome, 'Enhance'),
  const _FilterOption(FilterType.noShadow, Icons.wb_cloudy_outlined, 'No shadow'),
  const _FilterOption(FilterType.blackWhite, Icons.contrast, 'B&W'),
  const _FilterOption(FilterType.eco, Icons.eco_outlined, 'Eco'),
  const _FilterOption(FilterType.grayscale, Icons.gradient, 'Grayscale'),
  const _FilterOption(FilterType.invert, Icons.invert_colors_outlined, 'Invert'),
  const _FilterOption(FilterType.magicColor, Icons.palette_outlined, 'Magic color'),
  const _FilterOption(FilterType.binarization, Icons.text_fields, 'Binarize'),
  const _FilterOption(FilterType.shadowRemoval, Icons.light_mode, 'Shadow removal'),
];

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFF2F80ED).withValues(alpha: 0.28)
              : Colors.white10,
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2F80ED).withValues(alpha: 0.8)
                : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white70,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

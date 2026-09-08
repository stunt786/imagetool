import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/scanned_page.dart';
import '../../notifiers/document_batch_notifier.dart';
import '../../services/image_filter_service.dart';

class DocumentFilterScreen extends ConsumerStatefulWidget {
  const DocumentFilterScreen({super.key});

  @override
  ConsumerState<DocumentFilterScreen> createState() =>
      _DocumentFilterScreenState();
}

class _DocumentFilterScreenState extends ConsumerState<DocumentFilterScreen> {
  int? _selectedPageIndex;
  FilterType _selectedFilter = FilterType.none;
  bool _isProcessing = false;
  bool _applyToAll = false;
  int _previewRequest = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedPageIndex = GoRouterState.of(context).extra as int?;
    _applyToAll = _selectedPageIndex == -1;
    final batch = ref.read(documentBatchProvider);
    if (_selectedFilter == FilterType.none && batch.hasPages) {
      final index = _applyToAll ? 0 : (_selectedPageIndex ?? 0);
      if (index >= 0 && index < batch.pages.length) {
        _selectedFilter = batch.pages[index].filterType;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(documentBatchProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!batch.hasPages) {
      return Scaffold(
        appBar: AppBar(title: const Text('Filters')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_hdr_outlined,
                  size: 64,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text('No pages to filter',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final currentPage = _applyToAll || _selectedPageIndex == null
        ? batch.pages.first
        : batch.pages[_selectedPageIndex!];

    final filterOptions = [
      _FilterOption(FilterType.none, Icons.auto_fix_high, 'Original'),
      _FilterOption(FilterType.lighten, Icons.wb_sunny_outlined, 'Lighten'),
      _FilterOption(FilterType.enhance, Icons.auto_awesome, 'Enhance'),
      _FilterOption(FilterType.noShadow, Icons.wb_cloudy_outlined, 'No shadow'),
      _FilterOption(FilterType.blackWhite, Icons.contrast, 'B&W'),
      _FilterOption(FilterType.eco, Icons.eco_outlined, 'Eco'),
      _FilterOption(FilterType.grayscale, Icons.gradient, 'Grayscale'),
      _FilterOption(FilterType.invert, Icons.invert_colors_outlined, 'Invert'),
      _FilterOption(FilterType.sepia, Icons.filter_vintage_outlined, 'Sepia'),
      _FilterOption(FilterType.warm, Icons.wb_sunny, 'Warm'),
      _FilterOption(FilterType.cool, Icons.ac_unit, 'Cool'),
      _FilterOption(FilterType.dramatic, Icons.theater_comedy, 'Dramatic'),
      _FilterOption(FilterType.bwHighContrast, Icons.contrast_outlined, 'B&W High'),
      _FilterOption(FilterType.magicColor, Icons.palette_outlined, 'Magic color'),
      _FilterOption(FilterType.binarization, Icons.text_fields, 'Binarize'),
      _FilterOption(FilterType.shadowRemoval, Icons.light_mode, 'Shadow removal'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_applyToAll ? 'Apply Filter to All' : 'Edit Page'),
        actions: [
          if (_applyToAll && batch.pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text('${batch.pageCount} pages',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Preview
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              child: currentPage.imageBytes != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _selectedFilter == FilterType.none
                                  ? currentPage.imageBytes!
                                  : (currentPage.filteredBytes ??
                                      currentPage.imageBytes!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image, size: 48),
                            ),
                          ),
                        ),
                        if (_isProcessing)
                          const Positioned(
                            right: 16,
                            bottom: 16,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(6),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : const Center(child: Icon(Icons.image, size: 48)),
            ),
          ),

          // Filter selector
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Select Filter',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filterOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final option = filterOptions[index];
                      return _FilterTile(
                        icon: option.icon,
                        title: option.label,
                        isSelected: _selectedFilter == option.type,
                        onTap: () => _previewFilter(option.type),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _isProcessing ? null : _applyFilter,
            icon: _isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isProcessing ? 'Applying...' : 'Apply Filter'),
          ),
        ),
      ),
    );
  }

  Future<void> _applyFilter() async {
    setState(() => _isProcessing = true);
    try {
      final notifier = ref.read(documentBatchProvider.notifier);

      if (_applyToAll) {
        await notifier.applyFilterToAllPages(_selectedFilter);
      } else if (_selectedPageIndex != null) {
        await notifier.applyFilterToPage(_selectedPageIndex!, _selectedFilter);
      }

      if (mounted) {
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _previewFilter(FilterType filterType) async {
    final request = ++_previewRequest;
    final batch = ref.read(documentBatchProvider);
    final previewIndex = _applyToAll ? 0 : _selectedPageIndex;
    if (previewIndex == null ||
        previewIndex < 0 ||
        previewIndex >= batch.pages.length) {
      return;
    }

    setState(() {
      _selectedFilter = filterType;
      _isProcessing = filterType != FilterType.none;
    });

    try {
      final notifier = ref.read(documentBatchProvider.notifier);
      if (filterType == FilterType.none) {
        await notifier.applyFilterToPage(previewIndex, filterType);
      } else {
        final result = await ImageFilterService.applyPreview(
          batch.pages[previewIndex].imageBytes!,
          filterType,
        );
        if (!mounted || request != _previewRequest || result == null) return;
        final current = ref.read(documentBatchProvider).pages[previewIndex];
        notifier.updatePage(
          previewIndex,
          current.copyWith(
            filteredBytes: result.bytes,
            filterType: filterType,
            width: result.width,
            height: result.height,
          ),
        );
      }
    } finally {
      if (mounted && request == _previewRequest) {
        setState(() => _isProcessing = false);
      }
    }
  }
}

class _FilterOption {
  const _FilterOption(this.type, this.icon, this.label);
  final FilterType type;
  final IconData icon;
  final String label;
}

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
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 108,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? scheme.primaryContainer.withValues(alpha: 0.6)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

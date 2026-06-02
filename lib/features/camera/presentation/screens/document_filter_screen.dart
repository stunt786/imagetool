import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/scanned_page.dart';
import '../../notifiers/document_batch_notifier.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedPageIndex = GoRouterState.of(context).extra as int?;
    _applyToAll = _selectedPageIndex == -1;
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
                  size: 64, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
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
      _FilterOption(FilterType.magicColor, Icons.auto_awesome, 'Magic Color'),
      _FilterOption(FilterType.binarization, Icons.text_fields, 'Binarization'),
      _FilterOption(
          FilterType.shadowRemoval, Icons.light_mode, 'Shadow Removal'),
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
              child: _isProcessing
                  ? const Center(child: CircularProgressIndicator())
                  : (currentPage.imageBytes != null
                      ? Padding(
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
                        )
                      : const Center(child: Icon(Icons.image, size: 48))),
            ),
          ),

          // Filter selector
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Select Filter',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filterOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final option = filterOptions[index];
                      final isSelected = _selectedFilter == option.type;
                      return _FilterTile(
                        icon: option.icon,
                        title: option.label,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() => _selectedFilter = option.type);
                        },
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
            label:
                Text(_isProcessing ? 'Applying...' : 'Apply Filter'),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle, color: scheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

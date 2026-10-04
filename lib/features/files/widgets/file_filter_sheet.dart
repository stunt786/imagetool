import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/image_isolate_service.dart';
import '../../camera/models/scanned_page.dart';
import '../../camera/services/image_filter_service.dart';
import '../notifiers/operation_library_notifier.dart';

/// Filter picker for the Files module.
///
/// Previews every option on a downscaled pass and commits the chosen filter at
/// full resolution straight into the operation folder the file belongs to, so
/// the result is visible in the open Files grid immediately.
class FileFilterSheet extends ConsumerStatefulWidget {
  const FileFilterSheet({super.key, required this.item});

  final AppFileItem item;

  static Future<AppFileItem?> show(BuildContext context, {required AppFileItem item}) {
    return showModalBottomSheet<AppFileItem?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FileFilterSheet(item: item),
    );
  }

  @override
  ConsumerState<FileFilterSheet> createState() => _FileFilterSheetState();
}

class _FilterOption {
  const _FilterOption(this.type, this.icon, this.label);

  final FilterType type;
  final IconData icon;
  final String label;
}

const List<_FilterOption> _filterOptions = [
  _FilterOption(FilterType.none, Icons.auto_fix_high, 'Original'),
  _FilterOption(FilterType.antiLight, Icons.light_mode_outlined, 'Anti-Light'),
  _FilterOption(
      FilterType.autoBrighten, Icons.brightness_6_outlined, 'Auto Bright'),
  _FilterOption(FilterType.magicColor, Icons.palette_outlined, 'Magic color'),
  _FilterOption(FilterType.enhance, Icons.auto_awesome, 'Enhance'),
  _FilterOption(FilterType.lighten, Icons.wb_sunny_outlined, 'Lighten'),
  _FilterOption(FilterType.noShadow, Icons.wb_cloudy_outlined, 'No shadow'),
  _FilterOption(FilterType.blackWhite, Icons.contrast, 'B&W'),
  _FilterOption(FilterType.grayscale, Icons.gradient, 'Grayscale'),
  _FilterOption(FilterType.invert, Icons.invert_colors_outlined, 'Invert'),
  _FilterOption(FilterType.binarization, Icons.text_fields, 'Binarize'),
  _FilterOption(
    FilterType.shadowRemoval,
    Icons.wb_twilight,
    'Shadow removal',
  ),
];

class _FileFilterSheetState extends ConsumerState<FileFilterSheet> {
  Uint8List? _bytes;
  Uint8List? _basePreviewBytes;
  String? _error;
  FilterType _selected = FilterType.none;
  Uint8List? _previewBytes;
  bool _isPreviewing = false;
  bool _isApplying = false;
  int _previewRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.item.path);
      if (!await file.exists()) {
        throw Exception('File is no longer available');
      }
      final bytes = await file.readAsBytes();
      final ext = widget.item.extension.toLowerCase();
      Uint8List? basePreview;
      if (ext == 'tiff' || ext == 'tif') {
        basePreview = await ImageIsolateService.thumbnail(bytes, maxSide: 2048);
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _basePreviewBytes = basePreview;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _selectFilter(FilterType filter) async {
    final bytes = _bytes;
    if (bytes == null || _isApplying) return;

    final request = ++_previewRequest;
    setState(() {
      _selected = filter;
      _previewBytes = null;
      _isPreviewing = filter != FilterType.none;
    });

    if (filter == FilterType.none) return;
    try {
      final result = await ImageFilterService.applyPreview(bytes, filter);
      if (!mounted || request != _previewRequest) return;
      setState(() => _previewBytes = result?.bytes);
    } catch (_) {
      if (!mounted || request != _previewRequest) return;
    } finally {
      if (mounted && request == _previewRequest) {
        setState(() => _isPreviewing = false);
      }
    }
  }

  Future<void> _apply() async {
    final bytes = _bytes;
    if (bytes == null || _isApplying) return;
    if (_selected == FilterType.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a filter first'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isApplying = true);
    try {
      final result = await ImageFilterService.applyFilter(bytes, _selected);
      if (result == null || result.bytes.isEmpty) {
        throw Exception('Filter could not be applied');
      }

      Uint8List finalBytes = result.bytes;
      final ext = widget.item.extension.toLowerCase();
      if (ext == 'png' || ext == 'webp' || ext == 'tiff' || ext == 'tif' || ext == 'bmp') {
        final targetExt = (ext == 'tif') ? 'tiff' : ext;
        final converted = await ImageIsolateService.transform(
          result.bytes,
          ImageTransformRequest(targetExtension: targetExt, quality: 95),
        );
        if (converted != null && converted.isNotEmpty) {
          finalBytes = converted;
        }
      }

      final updated = await ref.read(operationStoreProvider).replaceFileBytes(
        fileId: widget.item.id,
        bytes: finalBytes,
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      Navigator.pop(context, updated ?? widget.item);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isApplying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not apply filter: $error'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF1B1E26),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filters',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isApplying ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildPreview(bytes)),
            const SizedBox(height: 12),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filterOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final option = _filterOptions[index];
                  return _FilterTile(
                    icon: option.icon,
                    label: option.label,
                    isSelected: _selected == option.type,
                    onTap: () => _selectFilter(option.type),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isApplying ? null : _apply,
              icon: _isApplying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 20),
              label: Text(_isApplying ? 'Applying…' : 'Apply & Save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFF8B1BFF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(Uint8List? bytes) {
    if (bytes == null) {
      return Center(
        child: _error != null
            ? const Text(
                'Could not load image',
                style: TextStyle(color: Colors.white54),
              )
            : const CircularProgressIndicator(color: Color(0xFF00E5FF)),
      );
    }

    final Uint8List source = _previewBytes ?? _basePreviewBytes ?? bytes;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            source,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(
                Icons.broken_image_rounded,
                size: 44,
                color: Colors.white38,
              ),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 94,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFF8B1BFF).withValues(alpha: 0.28)
              : Colors.white10,
          border: Border.all(
            color: isSelected ? const Color(0xFF8B1BFF) : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
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

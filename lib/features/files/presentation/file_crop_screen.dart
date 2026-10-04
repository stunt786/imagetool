import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/image_isolate_service.dart';
import '../../image_resize/models/crop_geometry.dart';
import '../../image_resize/widgets/crop_overlay.dart';
import '../notifiers/operation_library_notifier.dart';

/// Full-screen crop editor used by the Files module.
///
/// Unlike the camera crop route (which writes into a temporary scan batch),
/// this screen writes the result straight back into the operation folder the
/// user came from, so the cropped image shows up in the open Files grid.
class FileCropScreen extends ConsumerStatefulWidget {
  const FileCropScreen({super.key, required this.item});

  final AppFileItem item;

  @override
  ConsumerState<FileCropScreen> createState() => _FileCropScreenState();
}

enum _CropAspect {
  free('Free', null),
  square('1:1', 1),
  landscape('4:3', 4 / 3),
  widescreen('16:9', 16 / 9),
  portrait('9:16', 9 / 16);

  const _CropAspect(this.label, this.ratio);

  final String label;
  final double? ratio;
}

class _FileCropScreenState extends ConsumerState<FileCropScreen> {
  Uint8List? _bytes;
  Uint8List? _displayBytes;
  ImageProbeResult? _probe;
  CropRect? _crop;
  _CropAspect _aspect = _CropAspect.free;
  String? _error;
  bool _isApplying = false;

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
      final probe = await ImageIsolateService.probe(bytes);
      if (!probe.isValid || probe.width <= 0 || probe.height <= 0) {
        throw Exception('This file could not be decoded as an image');
      }
      final ext = widget.item.extension.toLowerCase();
      Uint8List displayBytes = bytes;
      if (ext == 'tiff' || ext == 'tif') {
        final thumb = await ImageIsolateService.thumbnail(bytes, maxSide: 2048);
        if (thumb != null && thumb.isNotEmpty) {
          displayBytes = thumb;
        }
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _displayBytes = displayBytes;
        _probe = probe;
        _crop = CropRect.full(probe.width, probe.height);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _apply() async {
    final bytes = _bytes;
    final probe = _probe;
    final crop = _crop;
    if (_isApplying || bytes == null || probe == null || crop == null) return;

    final pixel = crop.toPixelRect(
      imageWidth: probe.width,
      imageHeight: probe.height,
    );
    if (pixel.width <= 0 || pixel.height <= 0) return;

    setState(() => _isApplying = true);
    try {
      final sourceExt = widget.item.extension.toLowerCase();
      final targetExt = switch (sourceExt) {
        'png' => 'png',
        'webp' => 'webp',
        'bmp' => 'bmp',
        'tif' || 'tiff' => 'tiff',
        _ => 'jpg',
      };

      final cropped = await ImageIsolateService.crop(
        bytes,
        x: pixel.x,
        y: pixel.y,
        width: pixel.width,
        height: pixel.height,
        targetExtension: targetExt,
        quality: 95,
      );
      if (cropped == null || cropped.isEmpty) {
        throw Exception('Crop failed');
      }

      final updated = await ref.read(operationStoreProvider).replaceFileBytes(
        fileId: widget.item.id,
        bytes: cropped,
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      Navigator.pop(context, updated ?? widget.item);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isApplying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not crop image: $error'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final probe = _probe;
    final crop = _crop;

    return Scaffold(
      backgroundColor: const Color(0xFF101216),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101216),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Crop',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _isApplying ? null : _apply,
            child: _isApplying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00E5FF),
                    ),
                  )
                : const Text(
                    'Apply',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? _ErrorView(message: _error!, onRetry: _load)
            : bytes == null || probe == null || crop == null
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF00E5FF),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: CropOverlay(
                            imageBytes: _displayBytes ?? bytes,
                            imageWidth: probe.width,
                            imageHeight: probe.height,
                            crop: crop,
                            aspectRatio: _aspect.ratio,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                            onCropChanged: (rect) => _crop = rect,
                            onCropCommitted: (rect) =>
                                setState(() => _crop = rect),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _CropAspect.values.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final preset = _CropAspect.values[index];
                            final selected = preset == _aspect;
                            return Center(
                              child: ChoiceChip(
                                label: Text(preset.label),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _aspect = preset;
                                    _crop = _fitCropToAspect(preset);
                                  });
                                },
                                selectedColor: const Color(0xFF8B1BFF)
                                    .withValues(alpha: 0.4),
                                labelStyle: TextStyle(
                                  color:
                                      selected ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                                side: BorderSide(
                                  color: selected
                                      ? const Color(0xFF8B1BFF)
                                      : Colors.white24,
                                ),
                                backgroundColor: const Color(0xFF1B1E26),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isApplying
                                    ? null
                                    : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white24),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: _isApplying ? null : _apply,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B1BFF),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: Text(
                                  _isApplying ? 'Cropping…' : 'Crop & Save',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// Keeps the selection inside the image while honouring the chosen ratio.
  CropRect? _fitCropToAspect(_CropAspect preset) {
    final probe = _probe;
    final crop = _crop;
    if (probe == null || crop == null) return crop;

    final ratio = preset.ratio;
    if (ratio == null) return CropRect.full(probe.width, probe.height);

    final maxWidth = probe.width.toDouble();
    var width = crop.width;
    var height = width / ratio;
    if (height > probe.height) {
      height = probe.height.toDouble();
      width = height * ratio;
    }
    if (width > maxWidth) {
      width = maxWidth;
      height = width / ratio;
    }

    final left =
        (crop.left + (crop.width - width) / 2).clamp(0.0, maxWidth - width);
    final top = (crop.top + (crop.height - height) / 2)
        .clamp(0.0, probe.height - height);
    return CropRect(
      left: left,
      top: top,
      right: left + width,
      bottom: top + height,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_rounded,
                size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

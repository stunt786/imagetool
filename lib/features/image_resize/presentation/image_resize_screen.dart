import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/app_review_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/models/picked_file.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/notifiers/image_edit_notifier.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../core/models/operation_folder.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/public_storage.dart';
import '../models/batch_policy.dart';
import '../models/crop_geometry.dart';
import '../models/social_presets.dart';
import '../services/image_processor_service.dart';
import '../widgets/crop_overlay.dart';
import '../../../core/utils/file_type_detector.dart';
import '../../../core/utils/deferred_clear.dart';

class ImageResizeScreen extends ConsumerStatefulWidget {
  const ImageResizeScreen({super.key});

  @override
  ConsumerState<ImageResizeScreen> createState() => _ImageResizeScreenState();
}

enum _ResizeMode { dimensions, percentage, preset, bestFit, smartCompress }

enum _EditorPanel { resize, crop, rotate }

enum _PresetCategory { profile, banner }

enum _CropAspectPreset {
  free('Free', null),
  square('1:1', 1),
  landscape('4:3', 4 / 3),
  widescreen('16:9', 16 / 9),
  portrait('9:16', 9 / 16);

  const _CropAspectPreset(this.label, this.ratio);

  final String label;
  final double? ratio;
}

class _ImageResizeScreenState extends ConsumerState<ImageResizeScreen> {
  static const List<_PresetSize> _presetSizes = <_PresetSize>[
    _PresetSize('Instagram', 1080, 1080),
    _PresetSize('Story', 1080, 1920),
    _PresetSize('HD', 1280, 720),
    _PresetSize('Full HD', 1920, 1080),
    _PresetSize('Square', 2048, 2048),
    _PresetSize('Cover', 1500, 500),
  ];

  static const List<_QualityOption> _qualityOptions = <_QualityOption>[
    _QualityOption('100% (Best)', 100),
    _QualityOption('90% (High)', 90),
    _QualityOption('80% (Balanced)', 80),
    _QualityOption('70% (Medium)', 70),
    _QualityOption('60% (Small)', 60),
  ];

  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _percentageController = TextEditingController(
    text: '100',
  );
  final TextEditingController _bestFitWidthController = TextEditingController();
  final TextEditingController _bestFitHeightController =
      TextEditingController();
  final TextEditingController _cropXController = TextEditingController(
    text: '0',
  );
  final TextEditingController _cropYController = TextEditingController(
    text: '0',
  );
  final TextEditingController _cropWidthController = TextEditingController();
  final TextEditingController _cropHeightController = TextEditingController();
  List<Uint8List> _undoStack = <Uint8List>[];
  int _undoIndex = -1;

  /// Cap on retained undo snapshots. Each snapshot is a full-resolution
  /// bitmap, so an unbounded stack turns a long editing session into
  /// unbounded growth.
  static const int _maxUndoDepth = 10;

  _EditorPanel _activePanel = _EditorPanel.resize;
  _ResizeMode _mode = _ResizeMode.dimensions;
  _CropAspectPreset _cropPreset = _CropAspectPreset.free;
  OutputImageFormat _outputFormat = OutputImageFormat.jpg;
  _QualityOption _quality = _qualityOptions[1];
  bool _lockAspectRatio = true;
  int _aspectWidth = 1;
  int _aspectHeight = 1;
  double _percentage = 100;
  int _targetSizeKB = SocialPresets.targetFileSizeKB[2];
  int? _estimatedBytes;
  bool _isPicking = false;
  bool _isSyncingFields = false;
  _PresetCategory _presetCategory = _PresetCategory.profile;
  SocialPreset? _selectedSocialPreset;
  static const String _recentSizesKey = 'recent_resize_sizes_v1';
  List<Size> _recentSizes = <Size>[
    const Size(1280, 960),
    const Size(1024, 768),
    const Size(800, 600),
    const Size(1920, 1080),
  ];
  int _estimateRequestId = 0;
  double _rotationPreviewDegrees = 0;
  bool _flipPreviewH = false;
  bool _flipPreviewV = false;

  bool _replaceOriginal = false;
  bool _hasAutoTriggered = false;
  bool _isOneClickOpening = false;
  List<PickedFile> _batchFiles = <PickedFile>[];
  bool _isBatchMode = false;
  bool _isCropDragging = false;

  late final ImageEditNotifier _imageEditNotifier;

  @override
  void initState() {
    super.initState();
    _imageEditNotifier = ref.read(imageEditProvider.notifier);
    _loadRecentSizes();
    _isOneClickOpening = ref.read(appSettingsProvider).oneClickOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isOneClickOpening && !_hasAutoTriggered) {
        _hasAutoTriggered = true;
        setState(() => _isOneClickOpening = false);
        final state = ref.read(imageEditProvider);
        if (!state.hasImage) {
          _pickImage();
        }
      }
    });
  }

  @override
  void dispose() {
    // Release the provider's retained byte buffers on exit. Clearing is
    // deferred past the current frame so notifying listeners never happens
    // while the element tree is being torn down.
    runDeferredClear(_imageEditNotifier.clear);
    _widthController.dispose();
    _heightController.dispose();
    _percentageController.dispose();
    _bestFitWidthController.dispose();
    _bestFitHeightController.dispose();
    _cropXController.dispose();
    _cropYController.dispose();
    _cropWidthController.dispose();
    _cropHeightController.dispose();
    super.dispose();
  }

  static const int _maxBatchCount = FileTypeDetector.maxResizeImageCount;

  Future<void> _pickImage({bool allowMultiple = true}) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final service = ref.read(filePickerServiceProvider);
      final picked = await service.pick(
        context: context,
        target: PickTarget.images,
        allowMultiple: allowMultiple,
        maxAssets: allowMultiple ? _maxBatchCount : 1,
      );

      if (picked.isEmpty) return;

      final validImages = <PickedFile>[];
      var unsupportedCount = 0;
      for (final file in picked) {
        final detected = FileTypeDetector.detect(
          path: file.path,
          name: file.name,
          bytes: file.bytes,
        );
        if (detected.isImage) {
          validImages.add(file);
        } else {
          unsupportedCount++;
        }
      }

      if (unsupportedCount > 0) {
        _showSnack(
          unsupportedCount == 1
              ? '1 file was skipped because it is an unsupported file type.'
              : '$unsupportedCount files were skipped because they are unsupported file types.',
        );
      }

      if (validImages.isEmpty) {
        _showSnack('No supported image files were found in the selection.');
        return;
      }

      var finalSelection = validImages;
      if (validImages.length > _maxBatchCount) {
        finalSelection = validImages.take(_maxBatchCount).toList();
        _showSnack(
            'Only up to $_maxBatchCount images can be resized at a time.');
      }

      _batchFiles = List<PickedFile>.from(finalSelection);
      _isBatchMode = _batchFiles.length > 1;

      final file = _batchFiles.first;
      final fileBytes = await file.resolveBytes();
      if (fileBytes == null || fileBytes.isEmpty) {
        _showSnack('Unable to read that image.');
        return;
      }

      await ref
          .read(imageEditProvider.notifier)
          .loadImage(fileBytes, file.name, sourcePath: file.path);
      if (!mounted) return;

      final state = ref.read(imageEditProvider);
      if (!state.hasImage) return;

      _syncInputsFromImage(state.width, state.height);
      _undoStack = <Uint8List>[fileBytes];
      _undoIndex = 0;
      setState(() => _mode = _ResizeMode.dimensions);
      await _refreshEstimate();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _addMoreImages() async {
    if (_isPicking) return;
    if (_batchFiles.length >= _maxBatchCount) {
      _showSnack('Maximum limit of $_maxBatchCount images reached.');
      return;
    }
    setState(() => _isPicking = true);

    try {
      final remaining = _maxBatchCount - _batchFiles.length;
      final service = ref.read(filePickerServiceProvider);
      final picked = await service.pick(
        context: context,
        target: PickTarget.images,
        allowMultiple: true,
        maxAssets: remaining,
      );

      if (picked.isEmpty) return;

      var unsupportedCount = 0;
      final validPicked = <PickedFile>[];
      for (final file in picked) {
        final detected = FileTypeDetector.detect(
          path: file.path,
          name: file.name,
          bytes: file.bytes,
        );
        if (detected.isImage) {
          validPicked.add(file);
        } else {
          unsupportedCount++;
        }
      }

      if (unsupportedCount > 0) {
        _showSnack(
          unsupportedCount == 1
              ? '1 file was skipped because it is an unsupported file type.'
              : '$unsupportedCount files were skipped because they are unsupported file types.',
        );
      }

      final existingNames = _batchFiles.map((f) => f.name).toSet();
      final newFiles =
          validPicked.where((f) => !existingNames.contains(f.name)).toList();

      if (newFiles.isNotEmpty) {
        final availableSlots = _maxBatchCount - _batchFiles.length;
        if (newFiles.length > availableSlots) {
          _batchFiles.addAll(newFiles.take(availableSlots));
          _showSnack(
              'Only up to $_maxBatchCount images can be selected in total.');
        } else {
          _batchFiles.addAll(newFiles);
        }
      }
      _isBatchMode = _batchFiles.length > 1;

      if (!ref.read(imageEditProvider).hasImage && _batchFiles.isNotEmpty) {
        final first = _batchFiles.first;
        final firstBytes = await first.resolveBytes();
        if (firstBytes != null) {
          await ref
              .read(imageEditProvider.notifier)
              .loadImage(firstBytes, first.name, sourcePath: first.path);
          _syncInputsFromImage(ref.read(imageEditProvider).width,
              ref.read(imageEditProvider).height);
        }
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _removeBatchFileAt(int index) async {
    final removed = _batchFiles.removeAt(index);
    if (_batchFiles.isEmpty) {
      _isBatchMode = false;
      ref.read(imageEditProvider.notifier).clear();
      if (mounted) setState(() {});
      return;
    }
    if (_batchFiles.length == 1) {
      _isBatchMode = false;
    }
    if (ref.read(imageEditProvider).fileName == removed.name &&
        _batchFiles.isNotEmpty) {
      final next = _batchFiles.first;
      final nextBytes = await next.resolveBytes();
      if (nextBytes != null) {
        await ref
            .read(imageEditProvider.notifier)
            .loadImage(nextBytes, next.name, sourcePath: next.path);
        _syncInputsFromImage(ref.read(imageEditProvider).width,
            ref.read(imageEditProvider).height);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _processBatchResize() async {
    if (_batchFiles.isEmpty) {
      _showSnack('No images in batch to process.');
      return;
    }

    final appSettings = ref.read(appSettingsProvider);
    final progressNotifier = ValueNotifier<({int current, int total})>(
      (current: 1, total: _batchFiles.length),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<({int current, int total})>(
          valueListenable: progressNotifier,
          builder: (context, val, _) {
            return AlertDialog(
              content: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        'Resizing image ${val.current} of ${val.total}...',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    final entries = <OutputEntry>[];
    String? firstSavedPath;
    int successCount = 0;

    try {
      for (int i = 0; i < _batchFiles.length; i++) {
        progressNotifier.value = (current: i + 1, total: _batchFiles.length);
        final file = _batchFiles[i];
        final sourceBytes = await file.resolveBytes();
        if (sourceBytes == null || sourceBytes.isEmpty) continue;

        ImageProcessResult? result;

        if (_mode == _ResizeMode.smartCompress) {
          final targetBytes =
              math.min(_targetSizeKB * 1000, _targetSizeKB * 1024);
          result = await ImageProcessorService.compressToTargetSize(
            bytes: sourceBytes,
            targetBytes: targetBytes,
            format: _outputFormat,
            settings: appSettings,
          );
        } else if (_mode == _ResizeMode.preset &&
            _selectedSocialPreset != null) {
          result = await ImageProcessorService.resizeToPreset(
            bytes: sourceBytes,
            preset: _selectedSocialPreset!,
            format: _outputFormat,
            quality: _quality.value,
            settings: appSettings,
          );
        } else if (_mode == _ResizeMode.percentage) {
          final info = await ImageProcessorService.decodeImageInfo(sourceBytes);
          if (info != null) {
            final factor = _percentage / 100;
            final targetWidth = math.max(1, (info.width * factor).round());
            final targetHeight = math.max(1, (info.height * factor).round());
            result = await ImageProcessorService.resize(
              bytes: sourceBytes,
              width: targetWidth,
              height: targetHeight,
              format: _outputFormat,
              quality: _quality.value,
              settings: appSettings,
              preserveAspectRatio: _lockAspectRatio,
            );
          }
        } else if (_mode == _ResizeMode.bestFit) {
          final info = await ImageProcessorService.decodeImageInfo(sourceBytes);
          if (info != null) {
            final maxWidth =
                int.tryParse(_bestFitWidthController.text) ?? info.width;
            final maxHeight =
                int.tryParse(_bestFitHeightController.text) ?? info.height;
            int targetWidth = maxWidth;
            int targetHeight = maxHeight;
            if (_lockAspectRatio && info.width > 0 && info.height > 0) {
              final scale = math.min(
                maxWidth / info.width,
                maxHeight / info.height,
              );
              targetWidth = math.max(1, (info.width * scale).round());
              targetHeight = math.max(1, (info.height * scale).round());
            }
            result = await ImageProcessorService.resize(
              bytes: sourceBytes,
              width: targetWidth,
              height: targetHeight,
              format: _outputFormat,
              quality: _quality.value,
              settings: appSettings,
              preserveAspectRatio: _lockAspectRatio,
            );
          }
        } else {
          final state = ref.read(imageEditProvider);
          final target = _resolveTargetSize(state);
          if (target != null) {
            result = await ImageProcessorService.resize(
              bytes: sourceBytes,
              width: target.width,
              height: target.height,
              format: _outputFormat,
              quality: _quality.value,
              settings: appSettings,
            );
          }
        }

        if (result != null) {
          final fileName = _buildOutputFileName(
            baseName: file.name,
            format: _outputFormat,
          );
          entries.add(
            OutputEntry.bytes(
              bytes: result.bytes,
              fileName: fileName,
              publicKind: PublicFileKind.image,
            ),
          );
        }
      }

      if (entries.isNotEmpty) {
        final savedOutputs = await saveToolOutputs(
          ref.read(operationStoreProvider),
          kind: OperationKind.resize,
          entries: entries,
        );
        successCount = savedOutputs.length;
        if (savedOutputs.isNotEmpty) {
          firstSavedPath =
              savedOutputs.first.publicPath ?? savedOutputs.first.localPath;
        }
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Batch resize error: $error');
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (mounted && successCount > 0) {
      if (_mode == _ResizeMode.dimensions || _mode == _ResizeMode.preset) {
        final state = ref.read(imageEditProvider);
        final target = _resolveTargetSize(state);
        if (target != null) {
          _rememberRecentSize(
            Size(target.width.toDouble(), target.height.toDouble()),
          );
        }
      } else if (_mode == _ResizeMode.bestFit) {
        final maxWidth = int.tryParse(_bestFitWidthController.text);
        final maxHeight = int.tryParse(_bestFitHeightController.text);
        if (maxWidth != null &&
            maxHeight != null &&
            maxWidth > 0 &&
            maxHeight > 0) {
          _rememberRecentSize(
            Size(maxWidth.toDouble(), maxHeight.toDouble()),
          );
        }
      } else if (_mode == _ResizeMode.percentage) {
        final state = ref.read(imageEditProvider);
        if (state.hasImage) {
          final factor = _percentage / 100;
          final w = math.max(1, (state.width * factor).round());
          final h = math.max(1, (state.height * factor).round());
          _rememberRecentSize(Size(w.toDouble(), h.toDouble()));
        }
      }
      ref.read(editHistoryProvider.notifier).addGroup(
            toolName: 'Batch Resize',
            toolIcon: Icons.photo_size_select_large_rounded,
            count: successCount,
            filePath: firstSavedPath,
            thumbnailPath: firstSavedPath,
          );
      _showSnack('Batch resize complete. $successCount images saved.');
      AppReviewService.instance.notifyOperationCompleted(context);
      _resetScreen();
    }
  }

  void _resetScreen() {
    _batchFiles.clear();
    _undoStack.clear();
    _undoIndex = -1;
    _isBatchMode = false;
    ref.read(imageEditProvider.notifier).clear();
    setState(() {});
  }

  void _syncInputsFromImage(int width, int height) {
    _isSyncingFields = true;
    _aspectWidth = width;
    _aspectHeight = height;
    _activePanel = _EditorPanel.resize;
    _cropPreset = _CropAspectPreset.free;
    _presetCategory = _PresetCategory.profile;
    _selectedSocialPreset = null;
    _percentage = 100;
    _rotationPreviewDegrees = 0;
    _widthController.text = width.toString();
    _heightController.text = height.toString();
    _bestFitWidthController.text = width.toString();
    _bestFitHeightController.text = height.toString();
    _cropXController.text = '0';
    _cropYController.text = '0';
    _cropWidthController.text = width.toString();
    _cropHeightController.text = height.toString();
    _percentageController.text = '100';
    _estimatedBytes = ref.read(imageEditProvider).fileSize;
    _flipPreviewH = false;
    _flipPreviewV = false;
    _isSyncingFields = false;
    setState(() {});
  }

  void _setActivePanel(_EditorPanel panel) {
    setState(() => _activePanel = panel);
    _refreshEstimate();
  }

  void _setMode(_ResizeMode mode) {
    setState(() {
      _mode = mode;
      if (mode != _ResizeMode.preset) {
        _selectedSocialPreset = null;
      }
    });
    _refreshEstimate();
  }

  void _toggleAspectLock(bool value) {
    setState(() => _lockAspectRatio = value);
    if (value) {
      if (_mode == _ResizeMode.dimensions) {
        _handleWidthChanged(_widthController.text);
      } else if (_mode == _ResizeMode.bestFit) {
        _handleBestFitWidthChanged(_bestFitWidthController.text);
      }
    }
    _refreshEstimate();
  }

  void _handleWidthChanged(String value) {
    if (_isSyncingFields) return;
    if (!_lockAspectRatio) {
      _refreshEstimate();
      return;
    }
    final width = int.tryParse(value);
    if (width == null || width <= 0) {
      _refreshEstimate();
      return;
    }
    _isSyncingFields = true;
    _heightController.text = _scaledHeightForWidth(width).toString();
    _isSyncingFields = false;
    _refreshEstimate();
  }

  void _handleHeightChanged(String value) {
    if (_isSyncingFields) return;
    if (!_lockAspectRatio) {
      _refreshEstimate();
      return;
    }
    final height = int.tryParse(value);
    if (height == null || height <= 0) {
      _refreshEstimate();
      return;
    }
    _isSyncingFields = true;
    _widthController.text = _scaledWidthForHeight(height).toString();
    _isSyncingFields = false;
    _refreshEstimate();
  }

  void _handlePercentageChanged(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      _refreshEstimate();
      return;
    }
    final clamped = parsed.clamp(1, 400).toDouble();
    setState(() => _percentage = clamped);
    _refreshEstimate();
  }

  void _handlePercentageSlider(double value) {
    setState(() {
      _percentage = value;
      _percentageController.text = value.round().toString();
    });
    _refreshEstimate();
  }

  void _handleBestFitWidthChanged(String value) {
    if (_isSyncingFields) return;
    if (!_lockAspectRatio) {
      _refreshEstimate();
      return;
    }
    final width = int.tryParse(value);
    if (width == null || width <= 0) {
      _refreshEstimate();
      return;
    }
    _isSyncingFields = true;
    _bestFitHeightController.text = _scaledHeightForWidth(width).toString();
    _isSyncingFields = false;
    _refreshEstimate();
  }

  void _handleBestFitHeightChanged(String value) {
    if (_isSyncingFields) return;
    if (!_lockAspectRatio) {
      _refreshEstimate();
      return;
    }
    final height = int.tryParse(value);
    if (height == null || height <= 0) {
      _refreshEstimate();
      return;
    }
    _isSyncingFields = true;
    _bestFitWidthController.text = _scaledWidthForHeight(height).toString();
    _isSyncingFields = false;
    _refreshEstimate();
  }

  void _applyPreset(Size size) {
    _isSyncingFields = true;
    _widthController.text = size.width.round().toString();
    _heightController.text = size.height.round().toString();
    _bestFitWidthController.text = size.width.round().toString();
    _bestFitHeightController.text = size.height.round().toString();
    _isSyncingFields = false;
    setState(() {
      _mode = _ResizeMode.preset;
      _selectedSocialPreset = null;
    });
    _refreshEstimate();
  }

  void _applyRecentSize(Size size) {
    _isSyncingFields = true;
    _widthController.text = size.width.round().toString();
    _heightController.text = size.height.round().toString();
    _isSyncingFields = false;
    setState(() {
      _mode = _ResizeMode.dimensions;
      _selectedSocialPreset = null;
    });
    _rememberRecentSize(size);
    _refreshEstimate();
  }

  void _selectSocialPreset(SocialPreset preset) {
    _isSyncingFields = true;
    _widthController.text = preset.width.toString();
    _heightController.text = preset.height.toString();
    _bestFitWidthController.text = preset.width.toString();
    _bestFitHeightController.text = preset.height.toString();
    _isSyncingFields = false;
    setState(() {
      _mode = _ResizeMode.preset;
      _selectedSocialPreset = preset;
    });
    _refreshEstimate();
  }

  Future<void> _addCustomRecentSize() async {
    final widthController = TextEditingController();
    final heightController = TextEditingController();

    final size = await showDialog<Size>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom size'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widthController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Width'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final width = int.tryParse(widthController.text);
              final height = int.tryParse(heightController.text);
              if (width == null ||
                  height == null ||
                  width <= 0 ||
                  height <= 0) {
                return;
              }
              Navigator.of(
                context,
              ).pop(Size(width.toDouble(), height.toDouble()));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    widthController.dispose();
    heightController.dispose();

    if (size == null) return;
    _rememberRecentSize(size);
    _applyRecentSize(size);
  }

  Future<void> _refreshEstimate() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      if (mounted) {
        setState(() => _estimatedBytes = null);
      }
      return;
    }

    final requestId = ++_estimateRequestId;
    // Estimation performs a real isolated encode. Debouncing rapid typing and
    // slider movement keeps the editor responsive instead of queueing dozens
    // of full-resolution encodes that the user will never see.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted || requestId != _estimateRequestId) return;

    if (_mode == _ResizeMode.smartCompress &&
        _activePanel == _EditorPanel.resize) {
      if (mounted) {
        setState(() => _estimatedBytes = _targetSizeKB * 1024);
      }
      return;
    }

    // Crop panel: estimate from the crop rectangle at the current quality.
    // Rotate panel: rotation preserves pixel count, so the current size is
    // the honest estimate.
    final notifier = ref.read(imageEditProvider.notifier);
    if (_activePanel == _EditorPanel.crop) {
      final w = int.tryParse(_cropWidthController.text) ?? 0;
      final h = int.tryParse(_cropHeightController.text) ?? 0;
      if (w <= 0 || h <= 0) {
        if (mounted) setState(() => _estimatedBytes = null);
        return;
      }
      final estimate = await notifier.estimateResizeBytes(
        width: w,
        height: h,
        format: _outputFormat,
        quality: _quality.value,
      );
      if (!mounted || requestId != _estimateRequestId) return;
      setState(() => _estimatedBytes = estimate);
      return;
    }
    if (_activePanel == _EditorPanel.rotate) {
      if (mounted) setState(() => _estimatedBytes = state.fileSize);
      return;
    }

    final target = _resolveTargetSize(state);
    if (target == null) {
      if (mounted) {
        setState(() => _estimatedBytes = null);
      }
      return;
    }

    // Social presets apply cover-resize + center-crop, so estimate with the
    // same worker; plain resize would report a mismatched size.
    final int? estimate;
    if (_selectedSocialPreset != null && _mode == _ResizeMode.preset) {
      estimate = await notifier.estimatePresetBytes(
        targetWidth: _selectedSocialPreset!.width,
        targetHeight: _selectedSocialPreset!.height,
        format: _outputFormat,
        quality: _quality.value,
      );
    } else {
      estimate = await notifier.estimateResizeBytes(
        width: target.width,
        height: target.height,
        format: _outputFormat,
        quality: _quality.value,
      );
    }

    if (!mounted || requestId != _estimateRequestId) return;
    setState(() => _estimatedBytes = estimate);
  }

  Future<void> _resizeImage() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    if (_mode == _ResizeMode.smartCompress) {
      await _compressImage();
      return;
    }

    final target = _resolveTargetSize(state);
    if (target == null) {
      _showSnack('Enter a valid target size.');
      return;
    }

    final replaceOriginal = await _showSaveDialog(
      canReplace: _sourcePathFor(state.fileName) != null,
    );
    if (replaceOriginal == null || !mounted) return;
    _replaceOriginal = replaceOriginal;

    ref.read(imageEditProvider.notifier).setLoading(true);

    final result = _selectedSocialPreset != null && _mode == _ResizeMode.preset
        ? await ref.read(imageEditProvider.notifier).resizeToPreset(
              _selectedSocialPreset!.width,
              _selectedSocialPreset!.height,
              _outputFormat,
              _quality.value,
            )
        : await ref.read(imageEditProvider.notifier).generateResize(
              width: target.width,
              height: target.height,
              format: _outputFormat,
              quality: _quality.value,
            );

    if (!mounted) return;

    if (result == null) {
      ref.read(imageEditProvider.notifier).setLoading(false);
      _showSnack(ref.read(imageEditProvider).errorMessage ?? 'Resize failed.');
      return;
    }

    final fileName = _buildSaveFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
      replaceOriginal: _replaceOriginal,
    );

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);

    _rememberRecentSize(
      Size(target.width.toDouble(), target.height.toDouble()),
    );
    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);

    try {
      final savedPath = await _saveAndRecordEditedOutput(
        bytes: result.bytes,
        fileName: fileName,
        kind: OperationKind.resize,
        replaceOriginal: _replaceOriginal,
        replacePath: _replaceOriginal ? _sourcePathFor(state.fileName) : null,
      );
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
            EditHistoryItem(
              fileName: fileName,
              toolUsed: 'Image Resizer',
              editedAt: DateTime.now(),
              toolIcon: Icons.photo_size_select_large_rounded,
              filePath: savedPath ?? '',
              thumbnailPath: savedPath ?? '',
            ),
          );
      _showSnack(_replaceOriginal ? 'Replaced original' : 'Saved');
      AppReviewService.instance.notifyOperationCompleted(context);
      _resetScreen();
    } catch (error) {
      _showSnack('Resized image is ready, but saving failed: $error');
    }
  }

  Future<void> _rotateImage() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    // If only flip preview with no rotation, use flipImage path for efficiency.
    if (_rotationPreviewDegrees == 0 && (_flipPreviewH || _flipPreviewV)) {
      await _flipImage(
        horizontal: _flipPreviewH,
        vertical: _flipPreviewV,
        label: 'Flip',
      );
      return;
    }

    final replaceOriginal = await _showSaveDialog(
      canReplace: _sourcePathFor(state.fileName) != null,
    );
    if (replaceOriginal == null || !mounted) return;

    ref.read(imageEditProvider.notifier).setLoading(true);

    // Apply rotation first, then flip if needed.
    var result = await ref.read(imageEditProvider.notifier).generateRotate(
          angleDegrees: _normalizedRotationDegrees,
          format: _outputFormat,
          quality: _quality.value,
        );

    if (!mounted) return;

    if (result == null) {
      ref.read(imageEditProvider.notifier).setLoading(false);
      _showSnack(
        ref.read(imageEditProvider).errorMessage ?? 'Rotation failed.',
      );
      return;
    }

    if (_flipPreviewH || _flipPreviewV) {
      // Load rotated result temporarily, then flip. Preserve the original
      // source path so Replace Original stays available after rotate+flip.
      await ref.read(imageEditProvider.notifier).loadImage(
            result.bytes,
            state.fileName ?? 'image.jpg',
            sourcePath: _sourcePathFor(state.fileName),
          );
      final flipResult =
          await ref.read(imageEditProvider.notifier).generateFlip(
                _flipPreviewH,
                _flipPreviewV,
                format: _outputFormat,
                quality: _quality.value,
              );
      if (!mounted) return;
      result = flipResult ?? result;
    }

    final fileName = _buildSaveFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
      replaceOriginal: replaceOriginal,
    );

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);

    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);
    setState(() {
      _rotationPreviewDegrees = 0;
      _flipPreviewH = false;
      _flipPreviewV = false;
    });
    try {
      final savedPath = await _saveAndRecordEditedOutput(
        bytes: result.bytes,
        fileName: fileName,
        kind: OperationKind.imageEdit,
        replaceOriginal: replaceOriginal,
        replacePath: replaceOriginal ? _sourcePathFor(state.fileName) : null,
      );
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
            EditHistoryItem(
              fileName: fileName,
              toolUsed: 'Image Resizer',
              editedAt: DateTime.now(),
              toolIcon: Icons.rotate_right_rounded,
              filePath: savedPath ?? '',
              thumbnailPath: savedPath ?? '',
            ),
          );
      _showSnack(
          replaceOriginal ? 'Replaced original' : 'Rotation applied & saved.');
      _resetScreen();
    } catch (error) {
      _showSnack('Rotation applied, but saving failed: $error');
    }
  }

  Future<void> _flipImage({
    required bool horizontal,
    required bool vertical,
    required String label,
  }) async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    final replaceOriginal = await _showSaveDialog(
      canReplace: _sourcePathFor(state.fileName) != null,
    );
    if (replaceOriginal == null || !mounted) return;

    ref.read(imageEditProvider.notifier).setLoading(true);
    final result = await ref.read(imageEditProvider.notifier).generateFlip(
          horizontal,
          vertical,
          format: _outputFormat,
          quality: _quality.value,
        );

    if (!mounted) return;

    if (result == null) {
      ref.read(imageEditProvider.notifier).setLoading(false);
      _showSnack(ref.read(imageEditProvider).errorMessage ?? 'Flip failed.');
      return;
    }

    final fileName = _buildSaveFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
      replaceOriginal: replaceOriginal,
    );

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);

    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);
    try {
      final savedPath = await _saveAndRecordEditedOutput(
        bytes: result.bytes,
        fileName: fileName,
        kind: OperationKind.imageEdit,
        replaceOriginal: replaceOriginal,
        replacePath: replaceOriginal ? _sourcePathFor(state.fileName) : null,
      );
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
            EditHistoryItem(
              fileName: fileName,
              toolUsed: 'Image Resizer',
              editedAt: DateTime.now(),
              toolIcon: Icons.flip_rounded,
              filePath: savedPath ?? '',
              thumbnailPath: savedPath ?? '',
            ),
          );
      _showSnack(
          replaceOriginal ? 'Replaced original' : '$label applied & saved.');
      _resetScreen();
    } catch (error) {
      _showSnack('$label applied, but saving failed: $error');
    }
  }

  Future<void> _compressImage() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    // Compression is an export operation. Ask once up front, then process and
    // save in the same action so users never need to apply and save twice.
    final replaceOriginal = await _showSaveDialog(
      canReplace: _sourcePathFor(state.fileName) != null,
    );
    if (replaceOriginal == null || !mounted) return;

    final targetBytes = math.min(_targetSizeKB * 1000, _targetSizeKB * 1024);
    final appSettings = ref.read(appSettingsProvider);
    final result = await ref
        .read(imageEditProvider.notifier)
        .compressToTargetSize(targetBytes, _outputFormat,
            settings: appSettings);

    if (!mounted) return;

    if (result == null) {
      _showSnack(
        ref.read(imageEditProvider).errorMessage ?? 'Compression failed.',
      );
      return;
    }

    final fileName = _buildSaveFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
      replaceOriginal: replaceOriginal,
    );
    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);
    _rememberRecentSize(
      Size(result.width.toDouble(), result.height.toDouble()),
    );
    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);

    try {
      final savedPath = await _saveAndRecordEditedOutput(
        bytes: result.bytes,
        fileName: fileName,
        kind: OperationKind.resize,
        replaceOriginal: replaceOriginal,
        replacePath: replaceOriginal ? _sourcePathFor(state.fileName) : null,
      );
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
            EditHistoryItem(
              fileName: fileName,
              toolUsed: 'Image Resizer',
              editedAt: DateTime.now(),
              toolIcon: Icons.compress_rounded,
              filePath: savedPath ?? '',
              thumbnailPath: savedPath ?? '',
              compressionLevel: 'Smart',
            ),
          );
      if (result.fileSize > targetBytes) {
        _showSnack(
            'Minimum quality reached. Final size: ${_formatFileSize(result.fileSize)}');
      } else {
        _showSnack(
          '${replaceOriginal ? 'Replaced original with' : 'Compressed to'} ${_formatFileSize(result.fileSize)}.',
        );
      }
      _resetScreen();
    } catch (error) {
      _showSnack('Compression applied, but saving failed: $error');
    }
  }

  void _rotatePreviewBy(double deltaDegrees) {
    setState(() {
      _rotationPreviewDegrees = _normalizeDegrees(
        _rotationPreviewDegrees + deltaDegrees,
      );
    });
    _refreshEstimate();
  }

  void _resetRotationPreview() {
    setState(() => _rotationPreviewDegrees = 0);
    _refreshEstimate();
  }

  double get _normalizedRotationDegrees =>
      _normalizeDegrees(_rotationPreviewDegrees);

  double _normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  void _resetCropValues() {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) return;
    setState(() {
      _cropXController.text = '0';
      _cropYController.text = '0';
      _cropWidthController.text = state.width.toString();
      _cropHeightController.text = state.height.toString();
    });
    _refreshEstimate();
  }

  void _setCropPreset(_CropAspectPreset preset) {
    final state = ref.read(imageEditProvider);
    if (state.hasImage && preset.ratio != null) {
      final ratio = preset.ratio!;
      int newWidth, newHeight;
      if (state.width / state.height > ratio) {
        newHeight = state.height;
        newWidth = (newHeight * ratio).round().clamp(1, state.width);
      } else {
        newWidth = state.width;
        newHeight = (newWidth / ratio).round().clamp(1, state.height);
      }
      final newX = ((state.width - newWidth) / 2)
          .round()
          .clamp(0, math.max(0, state.width - 1));
      final newY = ((state.height - newHeight) / 2)
          .round()
          .clamp(0, math.max(0, state.height - 1));
      setState(() {
        _cropPreset = preset;
        _cropXController.text = newX.toString();
        _cropYController.text = newY.toString();
        _cropWidthController.text = newWidth.toString();
        _cropHeightController.text = newHeight.toString();
      });
      _refreshEstimate();
      return;
    }
    setState(() => _cropPreset = preset);
    _handleCropWidthChanged(_cropWidthController.text);
  }

  void _handleCropXChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditProvider);
    if (parsed +
            (_cropWidthController.text.isNotEmpty
                ? int.parse(_cropWidthController.text)
                : state.width) >
        state.width) {
      _cropXController.text =
          (state.width - int.parse(_cropWidthController.text))
              .clamp(0, state.width)
              .toString();
    }
    setState(() {});
    _refreshEstimate();
  }

  void _handleCropYChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditProvider);
    if (parsed +
            (_cropHeightController.text.isNotEmpty
                ? int.parse(_cropHeightController.text)
                : state.height) >
        state.height) {
      _cropYController.text =
          (state.height - int.parse(_cropHeightController.text))
              .clamp(0, state.height)
              .toString();
    }
    setState(() {});
    _refreshEstimate();
  }

  void _handleCropWidthChanged(String value) {
    if (_isSyncingFields) return;
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditProvider);
    final x = int.tryParse(_cropXController.text) ?? 0;
    final safeWidth = math.min(parsed, state.width - x).clamp(1, state.width);
    if (safeWidth != parsed) {
      _cropWidthController.text = safeWidth.toString();
    }
    if (_cropPreset.ratio != null) {
      _isSyncingFields = true;
      final safeHeight = math.max(
        1,
        math.min(
          state.height - (int.tryParse(_cropYController.text) ?? 0),
          (safeWidth / _cropPreset.ratio!).round(),
        ),
      );
      _cropHeightController.text = safeHeight.toString();
      _isSyncingFields = false;
    }
    setState(() {});
    _refreshEstimate();
  }

  void _handleCropHeightChanged(String value) {
    if (_isSyncingFields) return;
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditProvider);
    final y = int.tryParse(_cropYController.text) ?? 0;
    final safeHeight =
        math.min(parsed, state.height - y).clamp(1, state.height);
    if (safeHeight != parsed) {
      _cropHeightController.text = safeHeight.toString();
    }
    if (_cropPreset.ratio != null) {
      _isSyncingFields = true;
      final safeWidth = math.max(
        1,
        math.min(
          state.width - (int.tryParse(_cropXController.text) ?? 0),
          (safeHeight * _cropPreset.ratio!).round(),
        ),
      );
      _cropWidthController.text = safeWidth.toString();
      _isSyncingFields = false;
    }
    setState(() {});
    _refreshEstimate();
  }

  void _updateCropFromDrag({
    required int x,
    required int y,
    required int width,
    required int height,
    bool rebuild = false,
  }) {
    final state = ref.read(imageEditProvider);
    final clampedX = x.clamp(0, state.width - 1);
    final clampedY = y.clamp(0, state.height - 1);
    final maxAllowedWidth = state.width - clampedX;
    final maxAllowedHeight = state.height - clampedY;
    final clampedWidth = width.clamp(1, maxAllowedWidth);
    final clampedHeight = height.clamp(1, maxAllowedHeight);
    void syncFields() {
      _cropXController.text = clampedX.toString();
      _cropYController.text = clampedY.toString();
      _cropWidthController.text = clampedWidth.toString();
      _cropHeightController.text = clampedHeight.toString();
    }

    if (rebuild) {
      setState(syncFields);
      return;
    }

    syncFields();
  }

  Future<void> _applyCrop() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) return;

    final x = int.tryParse(_cropXController.text);
    final y = int.tryParse(_cropYController.text);
    final width = int.tryParse(_cropWidthController.text);
    final height = int.tryParse(_cropHeightController.text);

    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0) {
      _showSnack('Enter a valid crop area.');
      return;
    }

    // Single-step flow: save options first, then process + save together.
    final replaceOriginal = await _showSaveDialog(
      canReplace: _sourcePathFor(state.fileName) != null,
    );
    if (replaceOriginal == null || !mounted) return;

    ref.read(imageEditProvider.notifier).setLoading(true);
    final result = await ref.read(imageEditProvider.notifier).generateCrop(
          x: x,
          y: y,
          width: width,
          height: height,
          format: _outputFormat,
          quality: _quality.value,
        );

    if (!mounted) return;

    if (result == null) {
      ref.read(imageEditProvider.notifier).setLoading(false);
      _showSnack(ref.read(imageEditProvider).errorMessage ?? 'Crop failed.');
      return;
    }

    final fileName = _buildSaveFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
      replaceOriginal: replaceOriginal,
    );
    ref.read(imageEditProvider.notifier).replaceWithResult(
          result: result,
          fileName: fileName,
        );
    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);
    setState(() {});
    try {
      final savedPath = await _saveAndRecordEditedOutput(
        bytes: result.bytes,
        fileName: fileName,
        kind: OperationKind.imageEdit,
        replaceOriginal: replaceOriginal,
        replacePath: replaceOriginal ? _sourcePathFor(state.fileName) : null,
      );
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
            EditHistoryItem(
              fileName: fileName,
              toolUsed: 'Image Resizer',
              editedAt: DateTime.now(),
              toolIcon: Icons.crop_rounded,
              filePath: savedPath ?? '',
              thumbnailPath: savedPath ?? '',
            ),
          );
      _showSnack(
          replaceOriginal ? 'Replaced original' : 'Crop applied & saved.');
      _resetScreen();
    } catch (error) {
      _showSnack('Crop applied, but saving failed: $error');
    }
  }

  _ResizeTarget? _resolveTargetSize(ImageEditState state) {
    switch (_mode) {
      case _ResizeMode.dimensions:
      case _ResizeMode.preset:
        final width = int.tryParse(_widthController.text);
        final height = int.tryParse(_heightController.text);
        if (width == null || height == null || width <= 0 || height <= 0) {
          return null;
        }
        return _ResizeTarget(width, height);
      case _ResizeMode.percentage:
        final factor = _percentage / 100;
        final width = math.max(1, (state.width * factor).round());
        final height = math.max(1, (state.height * factor).round());
        return _ResizeTarget(width, height);
      case _ResizeMode.bestFit:
        final maxWidth = int.tryParse(_bestFitWidthController.text);
        final maxHeight = int.tryParse(_bestFitHeightController.text);
        if (maxWidth == null ||
            maxHeight == null ||
            maxWidth <= 0 ||
            maxHeight <= 0) {
          return null;
        }
        if (!_lockAspectRatio) {
          return _ResizeTarget(maxWidth, maxHeight);
        }
        final scale = math.min(
          maxWidth / state.width,
          maxHeight / state.height,
        );
        final width = math.max(1, (state.width * scale).round());
        final height = math.max(1, (state.height * scale).round());
        return _ResizeTarget(width, height);
      case _ResizeMode.smartCompress:
        return null;
    }
  }

  int _scaledHeightForWidth(int width) {
    if (_aspectWidth == 0 || _aspectHeight == 0) return width;
    // Use integer arithmetic to avoid floating-point drift
    return math.max(
        1, (width * _aspectHeight + _aspectWidth ~/ 2) ~/ _aspectWidth);
  }

  int _scaledWidthForHeight(int height) {
    if (_aspectWidth == 0 || _aspectHeight == 0) return height;
    // Use integer arithmetic to avoid floating-point drift
    return math.max(
        1, (height * _aspectWidth + _aspectHeight ~/ 2) ~/ _aspectHeight);
  }

  Future<void> _loadRecentSizes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_recentSizesKey);
      if (saved != null) {
        final parsed = <Size>[];
        for (final item in saved) {
          final parts = item.split('x');
          if (parts.length == 2) {
            final w = double.tryParse(parts[0]);
            final h = double.tryParse(parts[1]);
            if (w != null && h != null && w > 0 && h > 0) {
              parsed.add(Size(w, h));
            }
          }
        }
        if (mounted) {
          setState(() {
            _recentSizes = parsed;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _persistRecentSizes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _recentSizes
          .map((s) => '${s.width.round()}x${s.height.round()}')
          .toList();
      await prefs.setStringList(_recentSizesKey, list);
    } catch (_) {}
  }

  void _clearRecentSizes() {
    setState(() {
      _recentSizes = <Size>[];
    });
    _persistRecentSizes();
  }

  void _rememberRecentSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    setState(() {
      _recentSizes = <Size>[
        size,
        ..._recentSizes.where(
          (item) =>
              item.width.round() != size.width.round() ||
              item.height.round() != size.height.round(),
        ),
      ].take(8).toList(growable: false);
    });
    _persistRecentSizes();
  }

  String _buildOutputFileName({
    required String baseName,
    required OutputImageFormat format,
  }) {
    final dot = baseName.lastIndexOf('.');
    final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
    return '${stem}_resized.${format.extension}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatEstimateComparison(ImageEditState state) {
    final estimate = _estimatedBytes;
    if (estimate == null) return 'Estimated file size will appear here';
    if (_mode == _ResizeMode.smartCompress) {
      return 'up to ${_formatFileSize(estimate)} target';
    }
    final delta = estimate - state.fileSize;
    final percent = state.fileSize == 0
        ? 0
        : ((delta.abs() / state.fileSize) * 100).round();
    final changeLabel = delta == 0
        ? 'same size'
        : delta < 0
            ? '$percent% smaller'
            : '$percent% larger';
    return '~ ${_formatFileSize(estimate)} ($changeLabel)';
  }

  Widget _buildEstimateRow(ImageEditState state) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          Icons.insert_chart_outlined_rounded,
          size: 16,
          color: scheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          'Est. size: ',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            _formatEstimateComparison(state),
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  String _aspectRatioLabel(_ResizeTarget? target) {
    if (target == null) return '--';
    final divisor = _gcd(target.width, target.height);
    return '${target.width ~/ divisor}:${target.height ~/ divisor}';
  }

  int _gcd(int a, int b) {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
      final temp = x % y;
      x = y;
      y = temp;
    }
    return x == 0 ? 1 : x;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<bool?> _showSaveDialog({required bool canReplace}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Options'),
        content: Text(
          canReplace
              ? 'Would you like to replace the original file or save as a new file?'
              : 'This image source cannot be safely overwritten. It will be saved as a new file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Save as New'),
          ),
          if (canReplace)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Replace Original'),
            ),
        ],
      ),
    );
  }

  /// Persists an edited image through the unified [saveToolOutputs] pipeline.
  /// If [replaceOriginal] is requested with an existing [replacePath], overwrites
  /// that file directly. Otherwise, materializes into the operation folder and
  /// publishes to public storage (MediaStore or user-chosen SAF tree).
  Future<String?> _saveAndRecordEditedOutput({
    required Uint8List bytes,
    required String fileName,
    required OperationKind kind,
    bool replaceOriginal = false,
    String? replacePath,
  }) async {
    if (replaceOriginal && replacePath != null && replacePath.isNotEmpty) {
      final original = File(replacePath);
      if (await original.exists()) {
        await original.writeAsBytes(bytes, flush: true);
        return original.path;
      }
      throw StateError('The original image is no longer available to replace.');
    }
    final saved = await saveToolOutputs(
      ref.read(operationStoreProvider),
      kind: kind,
      entries: [
        OutputEntry.bytes(
          bytes: bytes,
          fileName: fileName,
          publicKind: PublicFileKind.image,
        ),
      ],
    );
    return saved.isNotEmpty ? saved.first.localPath : null;
  }

  String _buildSaveFileName({
    required String baseName,
    required OutputImageFormat format,
    required bool replaceOriginal,
  }) {
    if (replaceOriginal) {
      final dot = baseName.lastIndexOf('.');
      final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
      return '$stem.${format.extension}';
    }
    return _buildOutputFileName(baseName: baseName, format: format);
  }

  String? _sourcePathFor(String? fileName) {
    if (fileName == null) return ref.read(imageEditProvider).sourcePath;
    for (final file in _batchFiles) {
      if (file.name == fileName && file.path != null && file.path!.isNotEmpty) {
        return file.path;
      }
    }
    return ref.read(imageEditProvider).sourcePath;
  }

  void _pushUndoState(Uint8List bytes) {
    if (_undoIndex >= 0 && _undoIndex < _undoStack.length - 1) {
      _undoStack = _undoStack.sublist(0, _undoIndex + 1);
    }
    _undoStack.add(bytes);
    // Every entry is a full-resolution copy of the image, so the stack needs a
    // hard ceiling or a long editing session grows without bound.
    while (_undoStack.length > _maxUndoDepth) {
      _undoStack.removeAt(0);
      if (_undoIndex >= 0) _undoIndex--;
    }
    _undoIndex = _undoStack.length - 1;
    setState(() {});
  }

  Future<void> _undo() async {
    if (_undoIndex <= 0 || _undoStack.isEmpty) return;
    _undoIndex--;
    final bytes = _undoStack[_undoIndex];
    await ref.read(imageEditProvider.notifier).restoreImageBytes(bytes);
    if (!mounted) return;
    final state = ref.read(imageEditProvider);
    if (state.hasImage) {
      _syncInputsFromImage(state.width, state.height);
    }
  }

  Future<void> _redo() async {
    if (_undoIndex >= _undoStack.length - 1 || _undoStack.isEmpty) return;
    _undoIndex++;
    final bytes = _undoStack[_undoIndex];
    await ref.read(imageEditProvider.notifier).restoreImageBytes(bytes);
    if (!mounted) return;
    final state = ref.read(imageEditProvider);
    if (state.hasImage) {
      _syncInputsFromImage(state.width, state.height);
    }
  }

  Future<void> _applyActiveTool() {
    return switch (_activePanel) {
      _EditorPanel.resize => _resizeImage(),
      _EditorPanel.crop => _applyCrop(),
      _EditorPanel.rotate => _rotateImage(),
    };
  }

  /// True when the active panel should run over every selected image.
  bool get _toolProcessesWholeBatch => BatchPolicy.processesWholeBatch(
        isResizeTool: _activePanel == _EditorPanel.resize,
        batchCount: _batchFiles.length,
      );

  Future<void> _applyAndSave() async {
    // Batch processing belongs to the Resize panel only. Crop and Rotate always
    // act on the single image currently being edited, even when the user
    // selected several images.
    if (_toolProcessesWholeBatch) {
      await _processBatchResize();
      return;
    }
    await _applyActiveTool();
  }

  /// Index of the batch image currently loaded in the editor, or -1.
  int get _currentBatchIndex {
    if (_batchFiles.isEmpty) return -1;
    final name = ref.read(imageEditProvider).fileName;
    return _batchFiles.indexWhere((file) => file.name == name);
  }

  String get _applyButtonLabel {
    if (_toolProcessesWholeBatch) {
      return 'Resize ${_batchFiles.length} Images';
    }

    final base = switch (_activePanel) {
      _EditorPanel.resize => _mode == _ResizeMode.smartCompress
          ? 'Apply Compression & Save'
          : 'Apply Resize & Save',
      _EditorPanel.crop => 'Apply Crop & Save',
      _EditorPanel.rotate => 'Apply Rotation & Save',
    };

    // Make it obvious that crop/rotate only touch the current image.
    if (BatchPolicy.editsSingleImage(
      isResizeTool: _activePanel == _EditorPanel.resize,
      batchCount: _batchFiles.length,
    )) {
      return '$base (${BatchPolicy.positionLabel(index: _currentBatchIndex, batchCount: _batchFiles.length)})';
    }
    return base;
  }

  /// Batch strip thumbnail. Prefers the in-memory bytes, otherwise decodes
  /// straight from the picked path at a bounded size so a 12 MP source never
  /// lands in the image cache at full resolution.
  Widget _batchThumb(PickedFile file, Color placeholderColor) {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 140);
    }
    if (file.hasReadablePath) {
      return Image.file(
        File(file.path!),
        fit: BoxFit.cover,
        cacheWidth: 140,
        errorBuilder: (context, error, stackTrace) => Container(
          color: placeholderColor,
          child: const Icon(Icons.image),
        ),
      );
    }
    return Container(color: placeholderColor, child: const Icon(Icons.image));
  }

  /// Loads the batch image at [index] into the editor (used by the compact
  /// previous/next control shown for Crop and Rotate).
  Future<void> _selectBatchIndex(int index) async {
    if (index < 0 || index >= _batchFiles.length) return;
    final file = _batchFiles[index];
    final fileBytes = await file.resolveBytes();
    if (fileBytes == null) return;

    await ref.read(imageEditProvider.notifier).loadImage(
          fileBytes,
          file.name,
          sourcePath: file.path,
        );
    if (!mounted) return;
    _syncInputsFromImage(
      ref.read(imageEditProvider).width,
      ref.read(imageEditProvider).height,
    );
    _resetCropValues();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageEditProvider);
    final target = state.hasImage ? _resolveTargetSize(state) : null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? scheme.surface
          : const Color(0xFFF9F7FF),
      appBar: AppBar(
        title: const Text('Resize Image'),
        actions: [
          if (state.hasImage) ...[
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo',
              onPressed: _undoIndex > 0 ? _undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'Redo',
              onPressed: (_undoIndex >= 0 && _undoIndex < _undoStack.length - 1)
                  ? _redo
                  : null,
            ),
          ],
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.hasImage
              ? _buildEditorView(state, target)
              : _isOneClickOpening
                  ? const Center(child: CircularProgressIndicator())
                  : _buildSelectPhotosScreen(),
      bottomNavigationBar: state.hasImage
          ? SafeArea(
              top: false,
              child: _buildBottomActionBar(state),
            )
          : null,
    );
  }

  Widget _buildSelectPhotosScreen() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library,
                size: 50,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Resize Image',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Resize, crop, rotate, or compress single or batch images',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _pickImage(allowMultiple: true),
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Pick Images'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'JPG, PNG, WebP, GIF, BMP, HEIC & more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorView(ImageEditState state, _ResizeTarget? target) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: _isCropDragging
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.errorMessage != null) ...[
                  _ErrorBanner(message: state.errorMessage!),
                  const SizedBox(height: 8),
                ],
                // The Resize panel is a batch tool, so it keeps the full
                // filmstrip. Crop and Rotate edit one image at a time and use
                // a compact stepper instead.
                if (_activePanel == _EditorPanel.resize &&
                    (_isBatchMode || _batchFiles.length > 1)) ...[
                  _buildBatchFilmstrip(),
                ],
                if (BatchPolicy.editsSingleImage(
                  isResizeTool: _activePanel == _EditorPanel.resize,
                  batchCount: _batchFiles.length,
                )) ...[
                  _buildCurrentImageStepper(),
                ],
                _buildImageCard(state),
                const SizedBox(height: 10),
                _buildEditorCard(state, target),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Compact "which image am I editing" control for Crop and Rotate.
  Widget _buildCurrentImageStepper() {
    final scheme = Theme.of(context).colorScheme;
    final index = _currentBatchIndex;
    final position = index >= 0 ? index + 1 : 1;
    final name = index >= 0 ? _batchFiles[index].name : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous image',
            visualDensity: VisualDensity.compact,
            onPressed: index > 0 ? () => _selectBatchIndex(index - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Editing image $position of ${_batchFiles.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
                if (name.isNotEmpty)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Next image',
            visualDensity: VisualDensity.compact,
            onPressed: index >= 0 && index < _batchFiles.length - 1
                ? () => _selectBatchIndex(index + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchFilmstrip() {
    final scheme = Theme.of(context).colorScheme;
    final currentFileName = ref.watch(imageEditProvider).fileName;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_library_rounded,
                      size: 14,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_batchFiles.length} Images Selected',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _addMoreImages,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
                label: const Text('Add More'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _batchFiles.length,
              itemBuilder: (context, index) {
                final file = _batchFiles[index];
                final isSelected = currentFileName == file.name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final thumbBytes = await file.resolveBytes();
                          if (thumbBytes != null) {
                            await ref
                                .read(imageEditProvider.notifier)
                                .loadImage(
                                  thumbBytes,
                                  file.name,
                                  sourcePath: file.path,
                                );
                            _syncInputsFromImage(
                              ref.read(imageEditProvider).width,
                              ref.read(imageEditProvider).height,
                            );
                          }
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _batchThumb(
                            file,
                            scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removeBatchFileAt(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(ImageEditState state) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _InteractiveImagePreview(
                imageBytes: state.currentBytes!,
                cropX: int.tryParse(_cropXController.text) ?? 0,
                cropY: int.tryParse(_cropYController.text) ?? 0,
                cropWidth:
                    int.tryParse(_cropWidthController.text) ?? state.width,
                cropHeight:
                    int.tryParse(_cropHeightController.text) ?? state.height,
                imageWidth: state.width,
                imageHeight: state.height,
                activePanel: _activePanel,
                cropAspectRatio: _cropPreset.ratio,
                rotationDegrees: _rotationPreviewDegrees,
                flipH: _flipPreviewH,
                flipV: _flipPreviewV,
                onCropUpdate: _updateCropFromDrag,
                onCropDragStateChanged: (dragging) {
                  if (_isCropDragging != dragging) {
                    setState(() => _isCropDragging = dragging);
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildPrimaryToolStrip(),
              const SizedBox(height: 6),
              _buildImageMeta(state),
            ],
          ),
          // The crop and rotate workspaces edit the selected image only, so
          // the "add another image" affordance is hidden there. It stays
          // available for the resize panel where batching is expected.
          if (_activePanel == _EditorPanel.resize)
            Positioned(
              top: 0,
              left: 0,
              child: SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: const Icon(Icons.add),
                  onPressed: _pickImage,
                  tooltip: 'Add image',
                ),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _batchFiles.clear();
                  _isBatchMode = false;
                  ref.read(imageEditProvider.notifier).clear();
                  setState(() {});
                },
                tooltip: 'Reset',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorCard(ImageEditState state, _ResizeTarget? target) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _panelDecoration(),
      child: switch (_activePanel) {
        _EditorPanel.resize => _buildResizeEditor(state, target),
        _EditorPanel.crop => _buildCropEditor(state),
        _EditorPanel.rotate => _buildRotateEditor(state),
      },
    );
  }

  Widget _buildResizeEditor(ImageEditState state, _ResizeTarget? target) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 560;
            return GridView.count(
              shrinkWrap: true,
              crossAxisCount: wide ? 5 : 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: wide ? 1.2 : 1.1,
              children: [
                _ModeCard(
                  title: 'Smart',
                  icon: Icons.compress_rounded,
                  selected: _mode == _ResizeMode.smartCompress,
                  onTap: () => _setMode(_ResizeMode.smartCompress),
                ),
                _ModeCard(
                  title: 'Dimensions',
                  icon: Icons.crop_free_rounded,
                  selected: _mode == _ResizeMode.dimensions,
                  onTap: () => _setMode(_ResizeMode.dimensions),
                ),
                _ModeCard(
                  title: 'Percent',
                  icon: Icons.percent_rounded,
                  selected: _mode == _ResizeMode.percentage,
                  onTap: () => _setMode(_ResizeMode.percentage),
                ),
                _ModeCard(
                  title: 'Presets',
                  icon: Icons.copy_all_rounded,
                  selected: _mode == _ResizeMode.preset,
                  onTap: () => _setMode(_ResizeMode.preset),
                ),
                _ModeCard(
                  title: 'Best Fit',
                  icon: Icons.fit_screen_rounded,
                  selected: _mode == _ResizeMode.bestFit,
                  onTap: () => _setMode(_ResizeMode.bestFit),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _buildModePanel(state, target),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DropdownField<OutputImageFormat>(
                label: 'Format',
                value: _outputFormat,
                items: OutputImageFormat.values
                    .map(
                      (format) => DropdownMenuItem<OutputImageFormat>(
                        value: format,
                        child: Text(format.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _outputFormat = value);
                  _refreshEstimate();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DropdownField<_QualityOption>(
                label: 'Quality',
                value: _quality,
                items: _qualityOptions
                    .map(
                      (quality) => DropdownMenuItem<_QualityOption>(
                        value: quality,
                        child: Text(quality.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _quality = value);
                  _refreshEstimate();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.insert_chart_outlined_rounded,
              size: 16,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Est. size: ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            Expanded(
              child: Text(
                _formatEstimateComparison(state),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (_recentSizes.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _clearRecentSizes,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final size in _recentSizes)
              _RecentSizeChip(
                label: '${size.width.round()} × ${size.height.round()}',
                selected: target != null &&
                    target.width == size.width.round() &&
                    target.height == size.height.round(),
                onTap: () => _applyRecentSize(size),
              ),
            _RecentSizeChip(
              label: 'Custom  +',
              selected: false,
              onTap: _addCustomRecentSize,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Social Presets',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_PresetCategory>(
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const <ButtonSegment<_PresetCategory>>[
            ButtonSegment<_PresetCategory>(
              value: _PresetCategory.profile,
              icon: Icon(Icons.person_rounded, size: 18),
              label: Text('Profile'),
            ),
            ButtonSegment<_PresetCategory>(
              value: _PresetCategory.banner,
              icon: Icon(Icons.photo_size_select_large_rounded, size: 18),
              label: Text('Banner'),
            ),
          ],
          selected: <_PresetCategory>{_presetCategory},
          onSelectionChanged: (selection) {
            setState(() {
              _presetCategory = selection.first;
              _selectedSocialPreset = null;
            });
          },
        ),
        const SizedBox(height: 8),
        ..._buildSocialPresetTiles(),
      ],
    );
  }

  Widget _buildCropEditor(ImageEditState state) {
    final currentWidth = int.tryParse(_cropWidthController.text) ?? state.width;
    final currentHeight =
        int.tryParse(_cropHeightController.text) ?? state.height;
    final aspectRatio = currentWidth > 0 ? (currentHeight / currentWidth) : 1.0;
    final aspectText = aspectRatio.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Crop',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: _resetCropValues,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _CropAspectPreset.values
              .map(
                (preset) => ChoiceChip(
                  label: Text(preset.label),
                  selected: _cropPreset == preset,
                  onSelected: (_) => _setCropPreset(preset),
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
                  side: BorderSide(
                    color: _cropPreset == preset
                        ? _activeSelectColor(context)
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: _cropPreset == preset ? 2 : 1,
                  ),
                  labelStyle: TextStyle(
                    color: _cropPreset == preset
                        ? _activeSelectColor(context)
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _cropXController,
                label: 'X',
                onChanged: _handleCropXChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DimensionField(
                controller: _cropYController,
                label: 'Y',
                onChanged: _handleCropYChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _cropWidthController,
                label: 'Width',
                onChanged: _handleCropWidthChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DimensionField(
                controller: _cropHeightController,
                label: 'Height',
                onChanged: _handleCropHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Image: ${state.width} × ${state.height} px',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              'Ratio: $aspectText',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildEstimateRow(state),
      ],
    );
  }

  Widget _buildRotateEditor(ImageEditState state) {
    final signedAngle = _rotationPreviewDegrees > 180
        ? _rotationPreviewDegrees - 360
        : _rotationPreviewDegrees;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotate',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RotateStepChip(label: '-90°', onTap: () => _rotatePreviewBy(-90)),
            _RotateStepChip(label: '-15°', onTap: () => _rotatePreviewBy(-15)),
            _RotateStepChip(label: '+15°', onTap: () => _rotatePreviewBy(15)),
            _RotateStepChip(label: '+90°', onTap: () => _rotatePreviewBy(90)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RotateStepChip(
              label: _flipPreviewH ? '↔ Flip H ✓' : 'Flip H',
              isActive: _flipPreviewH,
              onTap: () {
                setState(() => _flipPreviewH = !_flipPreviewH);
                _refreshEstimate();
              },
            ),
            _RotateStepChip(
              label: _flipPreviewV ? '↕ Flip V ✓' : 'Flip V',
              isActive: _flipPreviewV,
              onTap: () {
                setState(() => _flipPreviewV = !_flipPreviewV);
                _refreshEstimate();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Slider(
                min: -180,
                max: 180,
                divisions: 360,
                value: signedAngle,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (value) {
                  setState(() {
                    _rotationPreviewDegrees = _normalizeDegrees(value);
                  });
                  _refreshEstimate();
                },
              ),
            ),
            SizedBox(
              width: 54,
              child: Text(
                '${signedAngle.round()}°',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _rotationPreviewDegrees == 0
                    ? 'Aligned to original'
                    : 'Rotation: ${_normalizedRotationDegrees.toStringAsFixed(1)}°',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            if (_rotationPreviewDegrees != 0)
              TextButton(
                onPressed: _resetRotationPreview,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Reset',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _buildEstimateRow(state),
      ],
    );
  }

  Widget _buildImageMeta(ImageEditState state) {
    return Row(
      children: [
        Expanded(
          child: Text(
            state.fileName ?? 'Image',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        _MetaPill(
          icon: Icons.image_rounded,
          label: '${state.width} × ${state.height}',
        ),
        const SizedBox(width: 6),
        _MetaPill(
          icon: Icons.folder_rounded,
          label: _formatFileSize(state.fileSize),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _outputFormat.label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar(ImageEditState state) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _applyAndSave,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                  switch (_activePanel) {
                    _EditorPanel.resize => Icons.auto_awesome_rounded,
                    _EditorPanel.crop => Icons.crop_rounded,
                    _EditorPanel.rotate => Icons.rotate_right_rounded,
                  },
                  size: 18),
              label: Text(
                _applyButtonLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryToolStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PreviewToolButton(
            label: 'Resize',
            icon: Icons.photo_size_select_large_rounded,
            selected: _activePanel == _EditorPanel.resize,
            onTap: () => _setActivePanel(_EditorPanel.resize),
          ),
          const SizedBox(width: 6),
          _PreviewToolButton(
            label: 'Crop',
            icon: Icons.crop_rounded,
            selected: _activePanel == _EditorPanel.crop,
            onTap: () => _setActivePanel(_EditorPanel.crop),
          ),
          const SizedBox(width: 6),
          _PreviewToolButton(
            label: 'Rotate',
            icon: Icons.rotate_right_rounded,
            selected: _activePanel == _EditorPanel.rotate,
            onTap: () => _setActivePanel(_EditorPanel.rotate),
          ),
        ],
      ),
    );
  }

  Widget _buildModePanel(ImageEditState state, _ResizeTarget? target) {
    final hideLock = _mode == _ResizeMode.preset ||
        _mode == _ResizeMode.smartCompress ||
        _mode == _ResizeMode.percentage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              switch (_mode) {
                                _ResizeMode.dimensions => 'Dimensions',
                                _ResizeMode.percentage => 'Percentage',
                                _ResizeMode.preset => 'Presets',
                                _ResizeMode.bestFit => 'Best Fit',
                                _ResizeMode.smartCompress =>
                                  'Smart Compression',
                              },
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (!hideLock) ...[
                            Text(
                              'Lock',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _lockAspectRatio,
                              onChanged: _toggleAspectLock,
                              activeThumbColor: Colors.white,
                              activeTrackColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (_mode) {
                            _ResizeMode.dimensions => 'Dimensions',
                            _ResizeMode.percentage => 'Percentage',
                            _ResizeMode.preset => 'Presets',
                            _ResizeMode.bestFit => 'Best Fit',
                            _ResizeMode.smartCompress => 'Smart Compression',
                          },
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (!hideLock) ...[
                        Text(
                          'Lock aspect',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: _lockAspectRatio,
                          onChanged: _toggleAspectLock,
                          activeThumbColor: Colors.white,
                          activeTrackColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ],
                  );
          },
        ),
        const SizedBox(height: 8),
        switch (_mode) {
          _ResizeMode.dimensions => _buildDimensionsInputs(),
          _ResizeMode.percentage => _buildPercentageInputs(state),
          _ResizeMode.preset => _buildPresetGrid(),
          _ResizeMode.bestFit => _buildBestFitInputs(state),
          _ResizeMode.smartCompress => _buildSmartCompressInputs(state),
        },
        const SizedBox(height: 6),
        Text(
          'Ratio: ${_aspectRatioLabel(target)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionsInputs() {
    return Row(
      children: [
        Expanded(
          child: _DimensionField(
            controller: _widthController,
            label: 'Width',
            onChanged: _handleWidthChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.link_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            ),
          ),
        ),
        Expanded(
          child: _DimensionField(
            controller: _heightController,
            label: 'Height',
            onChanged: _handleHeightChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPercentageInputs(ImageEditState state) {
    final width = math.max(1, (state.width * (_percentage / 100)).round());
    final height = math.max(1, (state.height * (_percentage / 100)).round());

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _percentageController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _handlePercentageChanged,
                  decoration: _fieldDecoration('Percentage'),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Slider(
            min: 10,
            max: 200,
            divisions: 19,
            value: _percentage.clamp(10, 200),
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: _handlePercentageSlider,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Result: $width × $height px',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetGrid() {
    final imageState = ref.read(imageEditProvider);
    final target = imageState.hasImage ? _resolveTargetSize(imageState) : null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in _presetSizes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _applyPreset(
                  Size(preset.width.toDouble(), preset.height.toDouble()),
                ),
                child: Container(
                  width: 120,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: target?.width == preset.width &&
                            target?.height == preset.height
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.3)
                        : Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: target?.width == preset.width &&
                              target?.height == preset.height
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: target?.width == preset.width &&
                              target?.height == preset.height
                          ? 2
                          : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${preset.width} × ${preset.height}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSocialPresetTiles() {
    final presets = _presetCategory == _PresetCategory.profile
        ? SocialPresets.profilePresets
        : SocialPresets.bannerPresets;
    final activeGreen = _activeSelectColor(context);

    return presets
        .map(
          (preset) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _selectSocialPreset(preset),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedSocialPreset?.name == preset.name
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3)
                      : Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedSocialPreset?.name == preset.name
                        ? activeGreen
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: _selectedSocialPreset?.name == preset.name ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _selectedSocialPreset?.name == preset.name
                                  ? activeGreen
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${preset.width} × ${preset.height}'
                            '${preset.description == null ? '' : ' • ${preset.description}'}',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedSocialPreset?.name == preset.name)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildBestFitInputs(ImageEditState state) {
    final target = _resolveTargetSize(state);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _bestFitWidthController,
                label: 'Max Width',
                onChanged: _handleBestFitWidthChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DimensionField(
                controller: _bestFitHeightController,
                label: 'Max Height',
                onChanged: _handleBestFitHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            target == null
                ? 'Enter bounds to fit the image.'
                : 'Output: ${target.width} × ${target.height} px',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  int _findClosestPresetIndex(int kb) {
    int closestIndex = 0;
    int minDiff = 1 << 30;
    for (int i = 0; i < SocialPresets.targetFileSizeKB.length; i++) {
      final diff = (SocialPresets.targetFileSizeKB[i] - kb).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  Future<void> _showCustomTargetSizeDialog() async {
    final controller = TextEditingController(text: _targetSizeKB.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Target size (KB)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Target File Size (KB)',
            suffixText: 'KB',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final kb = int.tryParse(controller.text);
              if (kb != null && kb > 0) {
                Navigator.of(context).pop(kb);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && mounted) {
      setState(() {
        _targetSizeKB = result;
      });
      _refreshEstimate();
    }
  }

  Widget _buildSmartCompressInputs(ImageEditState state) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Target size',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              InkWell(
                onTap: _showCustomTargetSizeDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _targetSizeKB >= 1000
                            ? '${(_targetSizeKB / 1000).toStringAsFixed(1)} MB'
                            : '$_targetSizeKB KB',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined,
                          size: 14, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Slider(
            min: 0,
            max: (SocialPresets.targetFileSizeKB.length - 1).toDouble(),
            divisions: SocialPresets.targetFileSizeKB.length - 1,
            value: SocialPresets.targetFileSizeKB.contains(_targetSizeKB)
                ? SocialPresets.targetFileSizeKB
                    .indexOf(_targetSizeKB)
                    .toDouble()
                : _findClosestPresetIndex(_targetSizeKB).toDouble(),
            activeColor: scheme.primary,
            onChanged: (value) {
              setState(() {
                _targetSizeKB = SocialPresets.targetFileSizeKB[value.round()];
              });
              _refreshEstimate();
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final size in SocialPresets.targetFileSizeKB)
                InkWell(
                  onTap: () {
                    setState(() => _targetSizeKB = size);
                    _refreshEstimate();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(
                      size >= 1000 ? '${size ~/ 1000}MB' : '${size}KB',
                      style: TextStyle(
                        fontSize: 11,
                        color: _targetSizeKB == size
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: _targetSizeKB == size
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: scheme.outlineVariant),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    );
  }
}

class _ResizeTarget {
  const _ResizeTarget(this.width, this.height);

  final int width;
  final int height;
}

class _PresetSize {
  const _PresetSize(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;
}

class _QualityOption {
  const _QualityOption(this.label, this.value);

  final String label;
  final int value;
}

/// Active-selection green for the rectangular option borders.
/// Brightness-aware so the 2px border stays visible in light and dark themes.
Color _activeSelectColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF15803D);

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final activeGreen = _activeSelectColor(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: isDark ? 0.55 : 0.3)
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? activeGreen : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? activeGreen : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: selected ? activeGreen : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DimensionField extends StatelessWidget {
  const _DimensionField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'px',
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          isDense: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _RecentSizeChip extends StatelessWidget {
  const _RecentSizeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeGreen = _activeSelectColor(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeGreen : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? activeGreen : scheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PreviewToolButton extends StatelessWidget {
  const _PreviewToolButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeGreen = _activeSelectColor(context);
    return Material(
      color: selected
          ? scheme.primary
          : scheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? activeGreen : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? scheme.onPrimary : scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RotateStepChip extends StatelessWidget {
  const _RotateStepChip(
      {required this.label, required this.onTap, this.isActive = false});

  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? scheme.primary : scheme.outlineVariant,
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? scheme.primary : scheme.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.errorContainer),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _InteractiveImagePreview extends StatefulWidget {
  const _InteractiveImagePreview({
    required this.imageBytes,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.activePanel,
    required this.cropAspectRatio,
    required this.rotationDegrees,
    required this.onCropUpdate,
    this.onCropDragStateChanged,
    this.flipH = false,
    this.flipV = false,
  });

  final Uint8List imageBytes;
  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;
  final int imageWidth;
  final int imageHeight;
  final _EditorPanel activePanel;
  final double? cropAspectRatio;
  final double rotationDegrees;
  final bool flipH;
  final bool flipV;
  final ValueChanged<bool>? onCropDragStateChanged;
  final void Function({
    required int x,
    required int y,
    required int width,
    required int height,
    bool rebuild,
  }) onCropUpdate;

  @override
  State<_InteractiveImagePreview> createState() =>
      _InteractiveImagePreviewState();
}

class _InteractiveImagePreviewState extends State<_InteractiveImagePreview> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.toDouble();
        final normalizedRotation = widget.rotationDegrees % 360;
        final isCropMode = widget.activePanel == _EditorPanel.crop;
        final maxPreviewHeight =
            MediaQuery.of(context).size.height * (isCropMode ? 0.48 : 0.22);
        final basePreviewHeight = isCropMode
            ? math
                .min(
                  (maxWidth - 44) * (widget.imageHeight / widget.imageWidth) +
                      36,
                  maxPreviewHeight,
                )
                .clamp(160.0, maxPreviewHeight)
                .toDouble()
            : math
                .min(
                  maxWidth * (widget.imageHeight / widget.imageWidth),
                  maxPreviewHeight,
                )
                .toDouble();
        final baseScale = math.min(
          maxWidth / math.max(widget.imageWidth, 1),
          basePreviewHeight / math.max(widget.imageHeight, 1),
        );
        final radians = normalizedRotation * math.pi / 180;
        final sinAngle = math.sin(radians).abs();
        final cosAngle = math.cos(radians).abs();
        final rotatedWidth =
            widget.imageWidth * cosAngle + widget.imageHeight * sinAngle;
        final rotatedHeight =
            widget.imageWidth * sinAngle + widget.imageHeight * cosAngle;
        final rotationScale = normalizedRotation == 0
            ? baseScale
            : math.min(
                maxWidth / math.max(rotatedWidth, 1),
                maxPreviewHeight / math.max(rotatedHeight, 1),
              );
        final previewWidth =
            normalizedRotation == 0 ? maxWidth : rotatedWidth * rotationScale;
        final previewHeight = normalizedRotation == 0
            ? basePreviewHeight
            : rotatedHeight * rotationScale;
        final imageDisplayWidth = widget.imageWidth * rotationScale;
        final imageDisplayHeight = widget.imageHeight * rotationScale;

        return Center(
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: InteractiveViewer(
              panEnabled: false,
              scaleEnabled: false,
              minScale: 0.75,
              maxScale: 4,
              clipBehavior: Clip.none,
              child: RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (normalizedRotation == 0)
                      SizedBox(
                        width: maxWidth,
                        height: basePreviewHeight,
                        child: widget.activePanel == _EditorPanel.crop
                            ? CropOverlay(
                                imageBytes: widget.imageBytes,
                                imageWidth: widget.imageWidth,
                                imageHeight: widget.imageHeight,
                                crop: CropRect(
                                  left: widget.cropX.toDouble(),
                                  top: widget.cropY.toDouble(),
                                  right: (widget.cropX + widget.cropWidth)
                                      .toDouble(),
                                  bottom: (widget.cropY + widget.cropHeight)
                                      .toDouble(),
                                ),
                                aspectRatio: widget.cropAspectRatio,
                                flipH: widget.flipH,
                                flipV: widget.flipV,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 18,
                                ),
                                onDragStateChanged:
                                    widget.onCropDragStateChanged,
                                onCropChanged: (crop) => widget.onCropUpdate(
                                  x: crop.left.round(),
                                  y: crop.top.round(),
                                  width: crop.width.round(),
                                  height: crop.height.round(),
                                  rebuild: false,
                                ),
                                onCropCommitted: (crop) => widget.onCropUpdate(
                                  x: crop.left.round(),
                                  y: crop.top.round(),
                                  width: crop.width.round(),
                                  height: crop.height.round(),
                                  rebuild: true,
                                ),
                              )
                            : Center(
                                child: SizedBox(
                                  width: imageDisplayWidth,
                                  height: imageDisplayHeight,
                                  child: Transform.scale(
                                    scaleX: widget.flipH ? -1.0 : 1.0,
                                    scaleY: widget.flipV ? -1.0 : 1.0,
                                    child: Image.memory(
                                      widget.imageBytes,
                                      width: imageDisplayWidth,
                                      height: imageDisplayHeight,
                                      fit: BoxFit.fill,
                                      cacheWidth: imageDisplayWidth.ceil(),
                                      cacheHeight: imageDisplayHeight.ceil(),
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.low,
                                    ),
                                  ),
                                ),
                              ),
                      )
                    else
                      Transform.rotate(
                        angle: radians,
                        child: Transform.scale(
                          scaleX: widget.flipH ? -1.0 : 1.0,
                          scaleY: widget.flipV ? -1.0 : 1.0,
                          child: SizedBox(
                            width: imageDisplayWidth,
                            height: imageDisplayHeight,
                            child: Image.memory(
                              widget.imageBytes,
                              width: imageDisplayWidth,
                              height: imageDisplayHeight,
                              fit: BoxFit.fill,
                              cacheWidth: imageDisplayWidth.ceil(),
                              cacheHeight: imageDisplayHeight.ceil(),
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.low,
                            ),
                          ),
                        ),
                      ),
                    if (widget.activePanel == _EditorPanel.crop &&
                        normalizedRotation != 0)
                      Positioned(
                        bottom: 12,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Reset rotation to edit crop handles',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

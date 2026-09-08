import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/interstitial_tracker.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/models/picked_file.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/notifiers/image_edit_notifier.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/utils/image_saver.dart';
import '../../../shared/widgets/ad_banner_wrapper.dart';
import '../models/social_presets.dart';
import '../services/image_processor_service.dart';

class ImageResizeScreen extends ConsumerStatefulWidget {
  const ImageResizeScreen({super.key});

  @override
  ConsumerState<ImageResizeScreen> createState() => _ImageResizeScreenState();
}

enum _ResizeMode { dimensions, percentage, preset, bestFit, smartCompress }

enum _EditorPanel { resize, crop, rotate, watermark }

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
  final TextEditingController _watermarkTextController =
      TextEditingController(text: '© PixelTools');

  List<Uint8List> _undoStack = <Uint8List>[];
  int _undoIndex = -1;

  Color _watermarkColor = Colors.white;
  double _watermarkOpacity = 0.8;
  WatermarkTextSize _watermarkSize = WatermarkTextSize.medium;
  WatermarkPosition _watermarkPosition = WatermarkPosition.bottomRight;

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

  bool _hasAutoTriggered = false;
  bool _isOneClickOpening = false;
  List<PickedFile> _batchFiles = <PickedFile>[];
  bool _isBatchMode = false;

  @override
  void initState() {
    super.initState();
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
    _widthController.dispose();
    _heightController.dispose();
    _percentageController.dispose();
    _bestFitWidthController.dispose();
    _bestFitHeightController.dispose();
    _cropXController.dispose();
    _cropYController.dispose();
    _cropWidthController.dispose();
    _cropHeightController.dispose();
    _watermarkTextController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({bool allowMultiple = true}) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final service = ref.read(filePickerServiceProvider);
      final picked = await service.pick(
        context: context,
        target: PickTarget.images,
        allowMultiple: allowMultiple,
      );

      if (picked.isEmpty) return;

      _batchFiles = List<PickedFile>.from(picked);
      _isBatchMode = picked.length > 1;

      final file = picked.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        _showSnack('Unable to read that image.');
        return;
      }

      await ref.read(imageEditProvider.notifier).loadImage(file.bytes!, file.name);
      if (!mounted) return;

      final state = ref.read(imageEditProvider);
      if (!state.hasImage) return;

      _syncInputsFromImage(state.width, state.height);
      _undoStack = <Uint8List>[file.bytes!];
      _undoIndex = 0;
      setState(() => _mode = _ResizeMode.dimensions);
      await _refreshEstimate();
      InterstitialTracker.instance.trackAction();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _addMoreImages() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final service = ref.read(filePickerServiceProvider);
      final picked = await service.pick(
        context: context,
        target: PickTarget.images,
        allowMultiple: true,
      );

      if (picked.isEmpty) return;

      final existingNames = _batchFiles.map((f) => f.name).toSet();
      final newFiles = picked.where((f) => !existingNames.contains(f.name)).toList();
      if (newFiles.isNotEmpty) {
        _batchFiles.addAll(newFiles);
      }
      _isBatchMode = _batchFiles.length > 1;

      if (!ref.read(imageEditProvider).hasImage && _batchFiles.isNotEmpty) {
        final first = _batchFiles.first;
        if (first.bytes != null) {
          await ref.read(imageEditProvider.notifier).loadImage(first.bytes!, first.name);
          _syncInputsFromImage(ref.read(imageEditProvider).width, ref.read(imageEditProvider).height);
        }
      }
      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _removeBatchFileAt(int index) async {
    final removed = _batchFiles.removeAt(index);
    if (_batchFiles.isEmpty) {
      _isBatchMode = false;
      ref.read(imageEditProvider.notifier).clear();
      setState(() {});
      return;
    }
    if (_batchFiles.length == 1) {
      _isBatchMode = false;
    }
    if (ref.read(imageEditProvider).fileName == removed.name && _batchFiles.isNotEmpty) {
      final next = _batchFiles.first;
      if (next.bytes != null) {
        await ref.read(imageEditProvider.notifier).loadImage(next.bytes!, next.name);
        _syncInputsFromImage(ref.read(imageEditProvider).width, ref.read(imageEditProvider).height);
      }
    }
    setState(() {});
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

    String? firstSavedPath;
    int successCount = 0;

    try {
      for (int i = 0; i < _batchFiles.length; i++) {
        progressNotifier.value = (current: i + 1, total: _batchFiles.length);
        final file = _batchFiles[i];
        if (file.bytes == null || file.bytes!.isEmpty) continue;

        ImageProcessResult? result;

        if (_mode == _ResizeMode.smartCompress) {
          final targetBytes = _targetSizeKB * 1024;
          result = await ImageProcessorService.compressToTargetSize(
            bytes: file.bytes!,
            targetBytes: targetBytes,
            format: _outputFormat,
            settings: appSettings,
          );
        } else if (_mode == _ResizeMode.preset && _selectedSocialPreset != null) {
          result = await ImageProcessorService.resizeToPreset(
            bytes: file.bytes!,
            preset: _selectedSocialPreset!,
            format: _outputFormat,
            quality: _quality.value,
            settings: appSettings,
          );
        } else if (_mode == _ResizeMode.percentage) {
          final info = await ImageProcessorService.decodeImageInfo(file.bytes!);
          if (info != null) {
            final factor = _percentage / 100;
            final targetWidth = math.max(1, (info.width * factor).round());
            final targetHeight = math.max(1, (info.height * factor).round());
            result = await ImageProcessorService.resize(
              bytes: file.bytes!,
              width: targetWidth,
              height: targetHeight,
              format: _outputFormat,
              quality: _quality.value,
              settings: appSettings,
            );
          }
        } else if (_mode == _ResizeMode.bestFit) {
          final info = await ImageProcessorService.decodeImageInfo(file.bytes!);
          if (info != null) {
            final maxWidth = int.tryParse(_bestFitWidthController.text) ?? info.width;
            final maxHeight = int.tryParse(_bestFitHeightController.text) ?? info.height;
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
              bytes: file.bytes!,
              width: targetWidth,
              height: targetHeight,
              format: _outputFormat,
              quality: _quality.value,
              settings: appSettings,
            );
          }
        } else {
          final state = ref.read(imageEditProvider);
          final target = _resolveTargetSize(state);
          if (target != null) {
            result = await ImageProcessorService.resize(
              bytes: file.bytes!,
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
          final saveResult = await saveImageBytes(result.bytes, fileName: fileName);
          firstSavedPath ??= saveResult.path;
          successCount++;
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
      ref.read(editHistoryProvider.notifier).addGroup(
        toolName: 'Batch Resize',
        toolIcon: Icons.photo_size_select_large_rounded,
        count: successCount,
        filePath: firstSavedPath,
        thumbnailPath: firstSavedPath,
      );
      _showSnack('Batch resize complete. $successCount images saved.');
      InterstitialTracker.instance.trackAction();
    }
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
    if (panel == _EditorPanel.resize) {
      _refreshEstimate();
    }
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

    final target = _resolveTargetSize(state);
    if (target == null) {
      if (mounted) {
        setState(() => _estimatedBytes = null);
      }
      return;
    }

    final requestId = ++_estimateRequestId;
    final estimate = await ref
        .read(imageEditProvider.notifier)
        .estimateResizeBytes(
          width: target.width,
          height: target.height,
          format: _outputFormat,
          quality: _quality.value,
        );

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

    ref.read(imageEditProvider.notifier).setLoading(true);

    final result = _selectedSocialPreset != null && _mode == _ResizeMode.preset
        ? await ref
              .read(imageEditProvider.notifier)
              .resizeToPreset(
                _selectedSocialPreset!.width,
                _selectedSocialPreset!.height,
                _outputFormat,
                _quality.value,
              )
        : await ref
              .read(imageEditProvider.notifier)
              .generateResize(
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

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
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
      final saveResult = await saveImageBytes(result.bytes, fileName: fileName);
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
        EditHistoryItem(
          fileName: fileName,
          toolUsed: 'Image Resizer',
          editedAt: DateTime.now(),
          toolIcon: Icons.photo_size_select_large_rounded,
          filePath: saveResult.path,
          thumbnailPath: saveResult.path,
        ),
      );
      _showSnack('Saved');
      InterstitialTracker.instance.trackAction();
    } catch (error) {
      _showSnack('Resized image is ready, but saving failed: $error');
      InterstitialTracker.instance.trackAction();
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

    ref.read(imageEditProvider.notifier).setLoading(true);

    // Apply rotation first, then flip if needed.
    var result = await ref
        .read(imageEditProvider.notifier)
        .generateRotate(
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
      // Load rotated result temporarily, then flip.
      await ref.read(imageEditProvider.notifier).loadImage(result.bytes, state.fileName ?? 'image.jpg');
      final flipResult = await ref
          .read(imageEditProvider.notifier)
          .generateFlip(
            _flipPreviewH,
            _flipPreviewV,
            format: _outputFormat,
            quality: _quality.value,
          );
      if (!mounted) return;
      result = flipResult ?? result;
    }

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
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
    _showSnack('Rotation applied.');
    InterstitialTracker.instance.trackAction();
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

    ref.read(imageEditProvider.notifier).setLoading(true);
    final result = await ref
        .read(imageEditProvider.notifier)
        .generateFlip(
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

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
    );

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);

    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);
    _showSnack('$label applied.');
    InterstitialTracker.instance.trackAction();
  }

  Future<void> _compressImage() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    final targetBytes = _targetSizeKB * 1024;
    final result = await ref
        .read(imageEditProvider.notifier)
        .compressToTargetSize(targetBytes, _outputFormat);

    if (!mounted) return;

    if (result == null) {
      _showSnack(
        ref.read(imageEditProvider).errorMessage ?? 'Compression failed.',
      );
      return;
    }

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
    );
    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);
    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);

    try {
      final saveResult = await saveImageBytes(result.bytes, fileName: fileName);
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
        EditHistoryItem(
          fileName: fileName,
          toolUsed: 'Image Resizer',
          editedAt: DateTime.now(),
          toolIcon: Icons.compress_rounded,
          filePath: saveResult.path,
          thumbnailPath: saveResult.path,
          compressionLevel: 'Smart',
        ),
      );
      if (result.fileSize > targetBytes) {
        _showSnack('Minimum quality reached. Final size: ${_formatFileSize(result.fileSize)}');
      } else {
        _showSnack('Compressed to ${_formatFileSize(result.fileSize)}.');
      }
    } catch (error) {
      _showSnack('Compression applied, but saving failed: $error');
    }
    InterstitialTracker.instance.trackAction();
  }

  void _rotatePreviewBy(double deltaDegrees) {
    setState(() {
      _rotationPreviewDegrees = _normalizeDegrees(
        _rotationPreviewDegrees + deltaDegrees,
      );
    });
  }

  void _resetRotationPreview() {
    setState(() => _rotationPreviewDegrees = 0);
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
  }

  void _setCropPreset(_CropAspectPreset preset) {
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
  }

  void _handleCropHeightChanged(String value) {
    if (_isSyncingFields) return;
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditProvider);
    final y = int.tryParse(_cropYController.text) ?? 0;
    final safeHeight = math
        .min(parsed, state.height - y)
        .clamp(1, state.height);
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

    ref.read(imageEditProvider.notifier).setLoading(true);
    final result = await ref
        .read(imageEditProvider.notifier)
        .generateCrop(
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

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(
          result: result,
          fileName: state.fileName ?? 'image.jpg',
        );
    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);
    setState(() {});
    _showSnack('Crop applied. Switch to Resize to adjust dimensions.');
    InterstitialTracker.instance.trackAction();
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
    return math.max(1, (width * _aspectHeight + _aspectWidth ~/ 2) ~/ _aspectWidth);
  }

  int _scaledWidthForHeight(int height) {
    if (_aspectWidth == 0 || _aspectHeight == 0) return height;
    // Use integer arithmetic to avoid floating-point drift
    return math.max(1, (height * _aspectWidth + _aspectHeight ~/ 2) ~/ _aspectHeight);
  }

  void _rememberRecentSize(Size size) {
    setState(() {
      _recentSizes = <Size>[
        size,
        ..._recentSizes.where(
          (item) =>
              item.width.round() != size.width.round() ||
              item.height.round() != size.height.round(),
        ),
      ].take(6).toList(growable: false);
    });
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
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveCurrentImage() async {
    final state = ref.read(imageEditProvider);
    final bytes = state.currentBytes;
    if (bytes == null || !state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
    );

    try {
      final saveResult = await saveImageBytes(bytes, fileName: fileName);
      if (!mounted) return;
      ref.read(editHistoryProvider.notifier).addEntry(
        EditHistoryItem(
          fileName: fileName,
          toolUsed: 'Image Resizer',
          editedAt: DateTime.now(),
          toolIcon: Icons.photo_size_select_large_rounded,
          filePath: saveResult.path,
          thumbnailPath: saveResult.path,
        ),
      );
      _showSnack('Saved');
      InterstitialTracker.instance.trackAction();
    } catch (error) {
      _showSnack('Saving failed: $error');
    }
  }

  void _pushUndoState(Uint8List bytes) {
    if (_undoIndex >= 0 && _undoIndex < _undoStack.length - 1) {
      _undoStack = _undoStack.sublist(0, _undoIndex + 1);
    }
    _undoStack.add(bytes);
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

  Future<void> _applyWatermark() async {
    final state = ref.read(imageEditProvider);
    if (!state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    final text = _watermarkTextController.text.trim();
    if (text.isEmpty) {
      _showSnack('Enter watermark text.');
      return;
    }

    ref.read(imageEditProvider.notifier).setLoading(true);

    final result = await ref
        .read(imageEditProvider.notifier)
        .generateWatermark(
          text: text,
          color: _watermarkColor,
          textSize: _watermarkSize,
          opacity: _watermarkOpacity,
          position: _watermarkPosition,
          format: _outputFormat,
          quality: _quality.value,
        );

    if (!mounted) return;

    if (result == null) {
      ref.read(imageEditProvider.notifier).setLoading(false);
      _showSnack(
        ref.read(imageEditProvider).errorMessage ?? 'Watermark failed.',
      );
      return;
    }

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
    );

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);

    _syncInputsFromImage(result.width, result.height);
    _pushUndoState(result.bytes);
    _showSnack('Watermark applied.');
    InterstitialTracker.instance.trackAction();
  }

  Future<void> _applyActiveTool() {
    return switch (_activePanel) {
      _EditorPanel.resize => _resizeImage(),
      _EditorPanel.crop => _applyCrop(),
      _EditorPanel.rotate => _rotateImage(),
      _EditorPanel.watermark => _applyWatermark(),
    };
  }

  Future<void> _applyAndSave() async {
    if (_isBatchMode && _batchFiles.length > 1) {
      await _processBatchResize();
      return;
    }
    if (_activePanel == _EditorPanel.resize) {
      await _resizeImage();
    } else {
      await _applyActiveTool();
    }
  }

  String get _applyButtonLabel {
    if (_isBatchMode && _batchFiles.length > 1) {
      return 'Resize ${_batchFiles.length} Images';
    }
    if (_activePanel == _EditorPanel.resize &&
        _mode == _ResizeMode.smartCompress) {
      return 'Apply Compression';
    }
    return switch (_activePanel) {
      _EditorPanel.resize => 'Apply Resize',
      _EditorPanel.crop => 'Apply Crop',
      _EditorPanel.rotate => 'Apply Rotation',
      _EditorPanel.watermark => 'Apply Watermark',
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageEditProvider);
    final target = state.hasImage ? _resolveTargetSize(state) : null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor:
          theme.brightness == Brightness.dark
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
              onPressed:
                  (_undoIndex >= 0 && _undoIndex < _undoStack.length - 1)
                      ? _redo
                      : null,
            ),
            IconButton(
              icon: const Icon(Icons.save_rounded),
              tooltip: 'Save current image',
              onPressed: _saveCurrentImage,
            ),
          ],
        ],
      ),
      body: AdBannerWrapper(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.hasImage
                ? _buildEditorView(state, target)
                : _isOneClickOpening
                    ? const Center(child: CircularProgressIndicator())
                    : _buildSelectPhotosScreen(),
      ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _pickImage(allowMultiple: true),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Pick Images'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(allowMultiple: true),
                  icon: const Icon(Icons.collections_rounded),
                  label: const Text('Batch Resize'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.errorMessage != null) ...[
            _ErrorBanner(message: state.errorMessage!),
            const SizedBox(height: 8),
          ],
          if (_isBatchMode || _batchFiles.length > 1) ...[
            _buildBatchFilmstrip(),
          ],
          _buildImageCard(state),
          const SizedBox(height: 10),
          _buildEditorCard(state, target),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          if (file.bytes != null) {
                            await ref
                                .read(imageEditProvider.notifier)
                                .loadImage(file.bytes!, file.name);
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
                              color: isSelected ? scheme.primary : scheme.outlineVariant,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: file.bytes != null
                              ? Image.memory(
                                  file.bytes!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 140,
                                )
                              : Container(
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(Icons.image),
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
                watermarkText: _watermarkTextController.text,
                watermarkColor: _watermarkColor,
                watermarkOpacity: _watermarkOpacity,
                watermarkSize: _watermarkSize,
                watermarkPosition: _watermarkPosition,
              ),
              const SizedBox(height: 10),
              _buildPrimaryToolStrip(),
              const SizedBox(height: 6),
              _buildImageMeta(state),
            ],
          ),
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
        _EditorPanel.rotate => _buildRotateEditor(),
        _EditorPanel.watermark => _buildWatermarkEditor(),
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
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _recentSizes = <Size>[]),
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
                selected:
                    target != null &&
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
      ],
    );
  }

  Widget _buildRotateEditor() {
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
              onTap: () => setState(() => _flipPreviewH = !_flipPreviewH),
            ),
            _RotateStepChip(
              label: _flipPreviewV ? '↕ Flip V ✓' : 'Flip V',
              isActive: _flipPreviewV,
              onTap: () => setState(() => _flipPreviewV = !_flipPreviewV),
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
      ],
    );
  }

  Widget _buildWatermarkEditor() {
    final scheme = Theme.of(context).colorScheme;

    final watermarkColorOptions = <Map<String, dynamic>>[
      {'label': 'White', 'color': Colors.white, 'opacity': _watermarkOpacity},
      {'label': 'Black', 'color': Colors.black, 'opacity': _watermarkOpacity},
      {'label': 'Red', 'color': Colors.red, 'opacity': _watermarkOpacity},
      {'label': 'Blue', 'color': Colors.blue, 'opacity': _watermarkOpacity},
      {'label': 'Semi-transparent White', 'color': Colors.white, 'opacity': 0.5},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Watermark Text',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _watermarkTextController,
          onChanged: (_) => setState(() {}),
          decoration: _fieldDecoration('Enter Watermark Text').copyWith(
            suffixIcon: _watermarkTextController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _watermarkTextController.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final suggestion in <String>[
              '© PixelTools',
              'CONFIDENTIAL',
              'SAMPLE',
              'DRAFT',
              'DO NOT COPY',
            ])
              ActionChip(
                label: Text(
                  suggestion,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () {
                  _watermarkTextController.text = suggestion;
                  setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Color',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: watermarkColorOptions.map((opt) {
            final String label = opt['label'] as String;
            final Color color = opt['color'] as Color;
            final double opacity = opt['opacity'] as double;
            final bool isSelected = label == 'Semi-transparent White'
                ? (_watermarkColor.toARGB32() == Colors.white.toARGB32() && _watermarkOpacity == 0.5)
                : (_watermarkColor.toARGB32() == color.toARGB32() && _watermarkOpacity != 0.5);

            return ChoiceChip(
              avatar: CircleAvatar(
                backgroundColor: color.withValues(alpha: opacity),
                radius: 8,
              ),
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _watermarkColor = color;
                  _watermarkOpacity = opacity;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Text Size',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: WatermarkTextSize.values.map((size) {
            return ChoiceChip(
              label: Text(size.label),
              selected: _watermarkSize == size,
              onSelected: (_) {
                setState(() => _watermarkSize = size);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Opacity',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: scheme.onSurface,
              ),
            ),
            Text(
              '${(_watermarkOpacity * 100).round()}%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        Slider(
          min: 0.1,
          max: 1.0,
          divisions: 18,
          value: _watermarkOpacity.clamp(0.1, 1.0),
          activeColor: scheme.primary,
          onChanged: (val) {
            setState(() => _watermarkOpacity = val);
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Position',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: WatermarkPosition.values.map((pos) {
            return ChoiceChip(
              label: Text(pos.label),
              selected: _watermarkPosition == pos,
              onSelected: (_) {
                setState(() => _watermarkPosition = pos);
              },
            );
          }).toList(),
        ),
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
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
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
          if (_activePanel != _EditorPanel.resize) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(Icons.save_rounded, color: scheme.primary),
                tooltip: 'Save without resizing',
                onPressed: _saveCurrentImage,
              ),
            ),
            const SizedBox(width: 8),
          ],
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
              icon: Icon(switch (_activePanel) {
                _EditorPanel.resize => Icons.auto_awesome_rounded,
                _EditorPanel.crop => Icons.crop_rounded,
                _EditorPanel.rotate => Icons.rotate_right_rounded,
                _EditorPanel.watermark => Icons.branding_watermark_rounded,
              }, size: 18),
              label: Text(
                _applyButtonLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
          const SizedBox(width: 6),
          _PreviewToolButton(
            label: 'Watermark',
            icon: Icons.branding_watermark_rounded,
            selected: _activePanel == _EditorPanel.watermark,
            onTap: () => _setActivePanel(_EditorPanel.watermark),
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
                              'Lock',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _lockAspectRatio,
                              onChanged: _toggleAspectLock,
                              activeThumbColor: Colors.white,
                              activeTrackColor: Theme.of(context).colorScheme.primary,
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: _lockAspectRatio,
                          onChanged: _toggleAspectLock,
                          activeThumbColor: Colors.white,
                          activeTrackColor: Theme.of(context).colorScheme.primary,
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
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

    return presets
        .map(
          (preset) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _selectSocialPreset(preset),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedSocialPreset?.name == preset.name
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedSocialPreset?.name == preset.name
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                        : Theme.of(context).colorScheme.outlineVariant,
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
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${preset.width} × ${preset.height}'
                            '${preset.description == null ? '' : ' • ${preset.description}'}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _buildSmartCompressInputs(ImageEditState state) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
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
              Text(
                _targetSizeKB >= 1000
                    ? '${(_targetSizeKB / 1000).toStringAsFixed(1)} MB'
                    : '$_targetSizeKB KB',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: (SocialPresets.targetFileSizeKB.length - 1).toDouble(),
            divisions: SocialPresets.targetFileSizeKB.length - 1,
            value: SocialPresets.targetFileSizeKB
                .indexOf(_targetSizeKB)
                .clamp(0, SocialPresets.targetFileSizeKB.length - 1)
                .toDouble(),
            activeColor: scheme.primary,
            onChanged: (value) {
              setState(() {
                _targetSizeKB =
                    SocialPresets.targetFileSizeKB[value.round()];
              });
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: SocialPresets.targetFileSizeKB
                .map(
                  (size) => Text(
                    size >= 1000 ? '${size ~/ 1000}MB' : '${size}KB',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(growable: false),
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
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: scheme.onSurface,
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.3) : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.primary : scheme.onSurface,
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
    return Material(
      color: selected ? scheme.primary : scheme.primaryContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
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
  const _RotateStepChip({required this.label, required this.onTap, this.isActive = false});

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
    this.flipH = false,
    this.flipV = false,
    this.watermarkText,
    this.watermarkColor,
    this.watermarkOpacity,
    this.watermarkSize,
    this.watermarkPosition,
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
  final String? watermarkText;
  final Color? watermarkColor;
  final double? watermarkOpacity;
  final WatermarkTextSize? watermarkSize;
  final WatermarkPosition? watermarkPosition;
  final void Function({
    required int x,
    required int y,
    required int width,
    required int height,
    bool rebuild,
  })
  onCropUpdate;

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
        final maxPreviewHeight = MediaQuery.of(context).size.height * 0.22;
        final basePreviewHeight = math
            .min(maxWidth * (widget.imageHeight / widget.imageWidth), maxPreviewHeight)
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
        final previewWidth = normalizedRotation == 0
            ? maxWidth
            : rotatedWidth * rotationScale;
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
              scaleEnabled: widget.activePanel == _EditorPanel.crop,
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
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: imageDisplayWidth,
                              height: imageDisplayHeight,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Transform.scale(
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
                                  if (widget.activePanel == _EditorPanel.crop)
                                    _InteractiveCropOverlay(
                                      cropX: widget.cropX,
                                      cropY: widget.cropY,
                                      cropWidth: widget.cropWidth,
                                      cropHeight: widget.cropHeight,
                                      imageWidth: widget.imageWidth,
                                      imageHeight: widget.imageHeight,
                                      cropAspectRatio: widget.cropAspectRatio,
                                      onCropEnd: widget.onCropUpdate,
                                    ),
                                ],
                              ),
                            ),
                          ],
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
                    if (widget.activePanel == _EditorPanel.watermark &&
                        widget.watermarkText != null &&
                        widget.watermarkText!.trim().isNotEmpty)
                      Positioned.fill(
                        child: Align(
                          alignment: switch (widget.watermarkPosition ??
                              WatermarkPosition.bottomRight) {
                            WatermarkPosition.topLeft => Alignment.topLeft,
                            WatermarkPosition.topRight => Alignment.topRight,
                            WatermarkPosition.bottomLeft => Alignment.bottomLeft,
                            WatermarkPosition.bottomRight =>
                              Alignment.bottomRight,
                            WatermarkPosition.center => Alignment.center,
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              widget.watermarkText!,
                              style: TextStyle(
                                color: (widget.watermarkColor ?? Colors.white)
                                    .withValues(
                                  alpha: (widget.watermarkOpacity ?? 0.8)
                                      .clamp(0.1, 1.0),
                                ),
                                fontSize: switch (widget.watermarkSize ??
                                    WatermarkTextSize.medium) {
                                  WatermarkTextSize.small => 12,
                                  WatermarkTextSize.medium => 18,
                                  WatermarkTextSize.large => 24,
                                  WatermarkTextSize.extraLarge => 32,
                                },
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    blurRadius: 4.0,
                                    color: Colors.black.withValues(
                                      alpha: ((widget.watermarkOpacity ?? 0.8) *
                                              0.6)
                                          .clamp(0.0, 1.0),
                                    ),
                                    offset: const Offset(1, 1),
                                  ),
                                ],
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

class _InteractiveCropOverlay extends StatefulWidget {
  const _InteractiveCropOverlay({
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.cropAspectRatio,
    required this.onCropEnd,
  });

  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;
  final int imageWidth;
  final int imageHeight;
  final double? cropAspectRatio;
  final void Function({
    required int x,
    required int y,
    required int width,
    required int height,
    bool rebuild,
  }) onCropEnd;

  @override
  State<_InteractiveCropOverlay> createState() =>
      _InteractiveCropOverlayState();
}

class _InteractiveCropOverlayState extends State<_InteractiveCropOverlay> {
  int _cropX = 0;
  int _cropY = 0;
  int _cropWidth = 0;
  int _cropHeight = 0;
  String? _draggingHandle;

  static const int _minCropSize = 20;
  static const double _touchRadius = 28;

  @override
  void initState() {
    super.initState();
    _cropX = widget.cropX;
    _cropY = widget.cropY;
    _cropWidth = widget.cropWidth;
    _cropHeight = widget.cropHeight;
  }

  @override
  void didUpdateWidget(_InteractiveCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingHandle == null) {
      _cropX = widget.cropX;
      _cropY = widget.cropY;
      _cropWidth = widget.cropWidth;
      _cropHeight = widget.cropHeight;
    }
  }

  String _hitTestHandle(Offset pos, Size container) {
    final sx = container.width / widget.imageWidth;
    final sy = container.height / widget.imageHeight;

    double hx(int v) => v * sx;
    double hy(int v) => v * sy;

    final handles = <String, Offset>{
      'tl': Offset(hx(_cropX), hy(_cropY)),
      'tr': Offset(hx(_cropX + _cropWidth), hy(_cropY)),
      'bl': Offset(hx(_cropX), hy(_cropY + _cropHeight)),
      'br': Offset(hx(_cropX + _cropWidth), hy(_cropY + _cropHeight)),
      't':  Offset(hx(_cropX + _cropWidth ~/ 2), hy(_cropY)),
      'b':  Offset(hx(_cropX + _cropWidth ~/ 2), hy(_cropY + _cropHeight)),
      'l':  Offset(hx(_cropX), hy(_cropY + _cropHeight ~/ 2)),
      'r':  Offset(hx(_cropX + _cropWidth), hy(_cropY + _cropHeight ~/ 2)),
    };

    for (final id in ['tl', 'tr', 'bl', 'br', 't', 'b', 'l', 'r']) {
      if ((pos - handles[id]!).distance <= _touchRadius) return id;
    }

    final r = Rect.fromLTWH(
      hx(_cropX), hy(_cropY),
      hx(_cropX + _cropWidth) - hx(_cropX),
      hy(_cropY + _cropHeight) - hy(_cropY),
    );
    if (r.contains(pos)) return 'move';

    return '';
  }

  void _onPanStart(DragStartDetails d) {
    final handle = _hitTestHandle(d.localPosition, context.size!);
    if (handle.isEmpty) return;
    _draggingHandle = handle;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_draggingHandle == null) return;
    final container = context.size!;
    final sx = widget.imageWidth / container.width;
    final sy = widget.imageHeight / container.height;
    final dx = (d.delta.dx * sx).round();
    final dy = (d.delta.dy * sy).round();

    int left = _cropX, top = _cropY;
    int right = _cropX + _cropWidth, bottom = _cropY + _cropHeight;

    switch (_draggingHandle) {
      case 'move':
        left += dx; top += dy;
        right += dx; bottom += dy;
        break;
      case 'tl': left += dx; top += dy; break;
      case 'tr': right += dx; top += dy; break;
      case 'bl': left += dx; bottom += dy; break;
      case 'br': right += dx; bottom += dy; break;
      case 't': top += dy; break;
      case 'b': bottom += dy; break;
      case 'l': left += dx; break;
      case 'r': right += dx; break;
    }

    left = left.clamp(0, widget.imageWidth);
    right = right.clamp(0, widget.imageWidth);
    top = top.clamp(0, widget.imageHeight);
    bottom = bottom.clamp(0, widget.imageHeight);

    if (right - left < _minCropSize) {
      if (_draggingHandle == 'l' || _draggingHandle == 'tl' || _draggingHandle == 'bl') {
        left = (right - _minCropSize).clamp(0, widget.imageWidth);
      } else {
        right = (left + _minCropSize).clamp(0, widget.imageWidth);
      }
    }
    if (bottom - top < _minCropSize) {
      if (_draggingHandle == 't' || _draggingHandle == 'tl' || _draggingHandle == 'tr') {
        top = (bottom - _minCropSize).clamp(0, widget.imageHeight);
      } else {
        bottom = (top + _minCropSize).clamp(0, widget.imageHeight);
      }
    }

    final ratio = widget.cropAspectRatio;
    if (ratio != null && _draggingHandle != 'move') {
      int w = right - left;
      int h = bottom - top;

      final topEdge = _draggingHandle == 't' || _draggingHandle == 'tl' || _draggingHandle == 'tr';
      final bottomEdge = _draggingHandle == 'b' || _draggingHandle == 'bl' || _draggingHandle == 'br';
      final leftEdge = _draggingHandle == 'l' || _draggingHandle == 'tl' || _draggingHandle == 'bl';
      final rightEdge = _draggingHandle == 'r' || _draggingHandle == 'tr' || _draggingHandle == 'br';

      bool adjusted = false;
      final targetH = (w / ratio).round();
      if (targetH >= _minCropSize) {
        if (topEdge) {
          final newTop = bottom - targetH;
          if (newTop >= 0) { top = newTop; adjusted = true; }
        }
        if (!adjusted && bottomEdge) {
          final newBottom = top + targetH;
          if (newBottom <= widget.imageHeight) { bottom = newBottom; adjusted = true; }
        }
      }

      if (!adjusted) {
        final targetW = (h * ratio).round();
        if (targetW >= _minCropSize) {
          if (leftEdge) {
            final newLeft = right - targetW;
            if (newLeft >= 0) { left = newLeft; }
          } else if (rightEdge) {
            final newRight = left + targetW;
            if (newRight <= widget.imageWidth) { right = newRight; }
          }
        }
      }
    }

    _cropX = left;
    _cropY = top;
    _cropWidth = right - left;
    _cropHeight = bottom - top;
    setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    if (_draggingHandle != null) {
      widget.onCropEnd(
        x: _cropX, y: _cropY,
        width: _cropWidth, height: _cropHeight,
        rebuild: true,
      );
    }
    _draggingHandle = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: RepaintBoundary(
            child: CustomPaint(
              size: constraints.biggest,
              painter: _CropPainter(
                x: _cropX,
                y: _cropY,
                width: _cropWidth,
                height: _cropHeight,
                imageWidth: widget.imageWidth,
                imageHeight: widget.imageHeight,
                containerSize: constraints.biggest,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.imageWidth,
    required this.imageHeight,
    required this.containerSize,
  });

  final int x, y, width, height;
  final int imageWidth, imageHeight;
  final Size containerSize;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = containerSize.width / imageWidth;
    final sy = containerSize.height / imageHeight;

    final cropRect = Rect.fromLTWH(x * sx, y * sy, width * sx, height * sy);
    final fullRect = Offset.zero & containerSize;

    // Dimmed overlay
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(fullRect),
        Path()..addRect(cropRect),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // White border
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Rule-of-thirds grid
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final fx in [cropRect.width / 3, 2 * cropRect.width / 3]) {
      canvas.drawLine(
        Offset(cropRect.left + fx, cropRect.top),
        Offset(cropRect.left + fx, cropRect.bottom),
        grid,
      );
    }
    for (final fy in [cropRect.height / 3, 2 * cropRect.height / 3]) {
      canvas.drawLine(
        Offset(cropRect.left, cropRect.top + fy),
        Offset(cropRect.right, cropRect.top + fy),
        grid,
      );
    }

    // Corner circles
    final corners = [
      cropRect.topLeft, cropRect.topRight,
      cropRect.bottomLeft, cropRect.bottomRight,
    ];
    for (final c in corners) {
      canvas.drawCircle(c, 12, Paint()..color = Colors.white);
      canvas.drawCircle(
        c, 12,
        Paint()
          ..color = const Color(0xFF8B1BFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Edge bars
    final edgeData = [
      (cropRect.center.dx, cropRect.top, 40.0, 16.0),
      (cropRect.center.dx, cropRect.bottom, 40.0, 16.0),
      (cropRect.left, cropRect.center.dy, 16.0, 40.0),
      (cropRect.right, cropRect.center.dy, 16.0, 40.0),
    ];
    for (final (cx, cy, ew, eh) in edgeData) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: ew, height: eh),
        const Radius.circular(8),
      );
      canvas.drawRRect(r, Paint()..color = Colors.white);
      canvas.drawRRect(
        r,
        Paint()
          ..color = const Color(0xFF8B1BFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) {
    return x != oldDelegate.x || y != oldDelegate.y ||
        width != oldDelegate.width || height != oldDelegate.height ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight ||
        containerSize != oldDelegate.containerSize;
  }
}

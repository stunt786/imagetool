import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../shared/notifiers/image_edit_notifier.dart';
import '../../../shared/utils/image_saver.dart';
import '../../../shared/widgets/ad_banner_wrapper.dart';
import '../models/social_presets.dart';

class ImageResizeScreen extends ConsumerStatefulWidget {
  const ImageResizeScreen({super.key});

  @override
  ConsumerState<ImageResizeScreen> createState() => _ImageResizeScreenState();
}

enum _ResizeMode { dimensions, percentage, preset, bestFit }

enum _EditorPanel { resize, crop, rotate }

enum _CropAspectPreset {
  free('Free', null),
  square('1:1', 1),
  landscape('4:3', 4 / 3),
  widescreen('16:9', 16 / 9);

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

  _EditorPanel _activePanel = _EditorPanel.resize;
  _ResizeMode _mode = _ResizeMode.dimensions;
  _CropAspectPreset _cropPreset = _CropAspectPreset.free;
  OutputImageFormat _outputFormat = OutputImageFormat.jpg;
  _QualityOption _quality = _qualityOptions[1];
  bool _lockAspectRatio = true;
  double _aspectRatio = 1;
  double _percentage = 100;
  int? _estimatedBytes;
  bool _isPicking = false;
  bool _isSyncingFields = false;
  List<Size> _recentSizes = <Size>[
    const Size(1280, 960),
    const Size(1024, 768),
    const Size(800, 600),
    const Size(1920, 1080),
  ];
  int _estimateRequestId = 0;
  double _rotationPreviewDegrees = 0;

  final ImagePicker _imagePicker = ImagePicker();

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
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack('Unable to read that image.');
        return;
      }

      await ref.read(imageEditProvider.notifier).loadImage(bytes, image.name);
      if (!mounted) return;

      final state = ref.read(imageEditProvider);
      if (!state.hasImage) return;

      _syncInputsFromImage(state.width, state.height);
      await _refreshEstimate();
      InterstitialTracker.instance.trackAction();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _syncInputsFromImage(int width, int height) {
    _isSyncingFields = true;
    _aspectRatio = height == 0 ? 1 : width / height;
    _mode = _ResizeMode.dimensions;
    _activePanel = _EditorPanel.resize;
    _cropPreset = _CropAspectPreset.free;
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
    setState(() => _mode = mode);
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
    setState(() => _mode = _ResizeMode.preset);
    _refreshEstimate();
  }

  void _applyRecentSize(Size size) {
    _isSyncingFields = true;
    _widthController.text = size.width.round().toString();
    _heightController.text = size.height.round().toString();
    _isSyncingFields = false;
    setState(() => _mode = _ResizeMode.dimensions);
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

    final target = _resolveTargetSize(state);
    if (target == null) {
      _showSnack('Enter a valid target size.');
      return;
    }

    ref.read(imageEditProvider.notifier).setLoading(true);

    final result = await ref
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

    try {
      await saveImageBytes(result.bytes, fileName: fileName);
      if (!mounted) return;
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

    ref.read(imageEditProvider.notifier).setLoading(true);

    final result = await ref
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

    final fileName = _buildOutputFileName(
      baseName: state.fileName ?? 'image',
      format: _outputFormat,
    );

    ref
        .read(imageEditProvider.notifier)
        .replaceWithResult(result: result, fileName: fileName);

    _syncInputsFromImage(result.width, result.height);
    setState(() => _rotationPreviewDegrees = 0);
    _showSnack('Rotation applied.');
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
        .generateCrop(x: x, y: y, width: width, height: height);

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
    _activePanel = _EditorPanel.crop;
    setState(() {});
    _showSnack('Crop applied.');
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
    }
  }

  int _scaledHeightForWidth(int width) {
    if (_aspectRatio == 0) return width;
    return math.max(1, (width / _aspectRatio).round());
  }

  int _scaledWidthForHeight(int height) {
    return math.max(1, (_aspectRatio * height).round());
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

  void _showHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resize image'),
        content: const Text(
          'Use the crop and resize buttons beside the image to switch the editor below. Crop first if needed, then resize and save the final file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
      await saveImageBytes(bytes, fileName: fileName);
      if (!mounted) return;
      _showSnack('Saved');
      InterstitialTracker.instance.trackAction();
    } catch (error) {
      _showSnack('Saving failed: $error');
    }
  }

  Future<void> _applyActiveTool() {
    return switch (_activePanel) {
      _EditorPanel.resize => _resizeImage(),
      _EditorPanel.crop => _applyCrop(),
      _EditorPanel.rotate => _rotateImage(),
    };
  }

  String get _applyButtonLabel {
    return switch (_activePanel) {
      _EditorPanel.resize => 'Apply Resize',
      _EditorPanel.crop => 'Apply Crop',
      _EditorPanel.rotate => 'Apply Rotation',
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageEditProvider);
    final target = state.hasImage ? _resolveTargetSize(state) : null;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F7FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _CircleActionButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => context.pop(),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Resize Image',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Resize by pixels, percentage or custom dimensions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7B7F95),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _CircleActionButton(
              icon: Icons.question_mark_rounded,
              onTap: _showHelpDialog,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AdBannerWrapper(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    8,
                    14,
                    state.hasImage ? 120 : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.errorMessage != null) ...[
                        _ErrorBanner(message: state.errorMessage!),
                        const SizedBox(height: 12),
                      ],
                      _buildImageCard(state),
                      const SizedBox(height: 14),
                      if (state.hasImage) _buildEditorCard(state, target),
                    ],
                  ),
                ),
        ),
      ),
      bottomNavigationBar: _buildBottomActionBar(state),
    );
  }

  Widget _buildImageCard(ImageEditState state) {
    final hasImage = state.hasImage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDE9FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120C1234),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: hasImage
          ? Column(
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
                  onCropUpdate: _updateCropFromDrag,
                ),
                const SizedBox(height: 16),
                _buildPrimaryToolStrip(),
                const SizedBox(height: 12),
                _buildImageMeta(state),
              ],
            )
          : Column(
              children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF3EEFF), Color(0xFFE8F4FF)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFD8D4F0),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.image_search_rounded,
                          size: 52,
                          color: Color(0xFF8B1BFF),
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Select an image to start editing',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF30334A),
                            fontSize: 17,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Supports JPG, PNG, WebP, GIF, BMP, HEIC & more',
                          style: TextStyle(
                            color: Color(0xFF7A7F9A),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _pickImage,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B1BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.upload_rounded),
                    label: Text(_isPicking ? 'Opening…' : 'Choose Image'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEditorCard(ImageEditState state, _ResizeTarget? target) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: switch (_activePanel) {
        _EditorPanel.resize => _buildResizeEditor(state, target),
        _EditorPanel.crop => _buildCropEditor(state),
        _EditorPanel.rotate => _buildRotateEditor(),
      },
    );
  }

  Widget _buildResizeEditor(ImageEditState state, _ResizeTarget? target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Resize Mode',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF1D2033),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 560;
            return GridView.count(
              shrinkWrap: true,
              crossAxisCount: wide ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: wide ? 1.0 : 1.15,
              children: [
                _ModeCard(
                  title: 'By Dimensions',
                  subtitle: 'Set custom width\nand height',
                  icon: Icons.crop_free_rounded,
                  selected: _mode == _ResizeMode.dimensions,
                  onTap: () => _setMode(_ResizeMode.dimensions),
                ),
                _ModeCard(
                  title: 'By Percentage',
                  subtitle: 'Scale image by\npercentage',
                  icon: Icons.percent_rounded,
                  selected: _mode == _ResizeMode.percentage,
                  onTap: () => _setMode(_ResizeMode.percentage),
                ),
                _ModeCard(
                  title: 'Preset Sizes',
                  subtitle: 'Choose from\npopular sizes',
                  icon: Icons.copy_all_rounded,
                  selected: _mode == _ResizeMode.preset,
                  onTap: () => _setMode(_ResizeMode.preset),
                ),
                _ModeCard(
                  title: 'Best Fit',
                  subtitle: 'Fit image to\nspecific size',
                  icon: Icons.fit_screen_rounded,
                  selected: _mode == _ResizeMode.bestFit,
                  onTap: () => _setMode(_ResizeMode.bestFit),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _buildModePanel(state, target),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DropdownField<OutputImageFormat>(
                label: 'Output Format',
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
            const SizedBox(width: 12),
            Expanded(
              child: _DropdownField<_QualityOption>(
                label: 'Image Quality',
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
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E9FF)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insert_chart_outlined_rounded,
                  color: Color(0xFF6A39F9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated File Size',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3A3F5B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatEstimateComparison(state),
                      style: const TextStyle(
                        color: Color(0xFF5B63C7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Sizes',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF1D2033),
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _recentSizes = <Size>[]),
              child: const Text(
                'Clear All',
                style: TextStyle(
                  color: Color(0xFF8B1BFF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Crop Image',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Color(0xFF1D2033),
              ),
            ),
            TextButton.icon(
              onPressed: _resetCropValues,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B1BFF),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Drag the handles on the image to adjust the crop area, or enter values below.',
          style: TextStyle(color: Color(0xFF6F748C), height: 1.35),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6F8FF), Color(0xFFFAFCFF)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E9FF)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _DimensionField(
                  controller: _cropXController,
                  label: 'X Position',
                  onChanged: _handleCropXChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DimensionField(
                  controller: _cropYController,
                  label: 'Y Position',
                  onChanged: _handleCropYChanged,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _cropWidthController,
                label: 'Width',
                onChanged: _handleCropWidthChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DimensionField(
                controller: _cropHeightController,
                label: 'Height',
                onChanged: _handleCropHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E9FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF7A3FF8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Image: ${state.width} × ${state.height} px',
                    style: const TextStyle(
                      color: Color(0xFF4A4F69),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.aspect_ratio_rounded,
                    size: 16,
                    color: Color(0xFF7A3FF8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Aspect ratio: $aspectText',
                    style: const TextStyle(
                      color: Color(0xFF5B63C7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        const Text(
          'Rotate Preview',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF1D2033),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Preview updates live while you rotate. Apply only when the angle looks right.',
          style: TextStyle(color: Color(0xFF6F748C), height: 1.35),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _RotateStepChip(label: '-90°', onTap: () => _rotatePreviewBy(-90)),
            _RotateStepChip(label: '-15°', onTap: () => _rotatePreviewBy(-15)),
            _RotateStepChip(label: '+15°', onTap: () => _rotatePreviewBy(15)),
            _RotateStepChip(label: '+90°', onTap: () => _rotatePreviewBy(90)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Slider(
                min: -180,
                max: 180,
                divisions: 360,
                value: signedAngle,
                activeColor: const Color(0xFF8B1BFF),
                onChanged: (value) {
                  setState(() {
                    _rotationPreviewDegrees = _normalizeDegrees(value);
                  });
                },
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${signedAngle.round()}°',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: Color(0xFF5B63C7),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E9FF)),
          ),
          child: Text(
            _rotationPreviewDegrees == 0
                ? 'Preview is aligned to the original image.'
                : 'Rotation ready: ${_normalizedRotationDegrees.toStringAsFixed(1)}°',
            style: const TextStyle(
              color: Color(0xFF4A4F69),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _rotationPreviewDegrees == 0
                ? null
                : _resetRotationPreview,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset Preview'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              side: const BorderSide(color: Color(0xFFD9DDF5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageMeta(ImageEditState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.fileName ?? 'Image',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Color(0xFF1D2033),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetaPill(
              icon: Icons.image_rounded,
              label: '${state.width} × ${state.height}',
            ),
            _MetaPill(
              icon: Icons.folder_rounded,
              label: _formatFileSize(state.fileSize),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1EEFF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _outputFormat.label,
            style: const TextStyle(
              color: Color(0xFF6A39F9),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar(ImageEditState state) {
    if (!state.hasImage) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: FilledButton.icon(
            onPressed: _pickImage,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B1BFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(_isPicking ? 'Opening…' : 'Add Image'),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE9E5FF))),
          boxShadow: [
            BoxShadow(
              color: Color(0x140C1234),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Add'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: Color(0xFFD9DDF5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _applyActiveTool,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B1BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(switch (_activePanel) {
                  _EditorPanel.resize => Icons.auto_awesome_rounded,
                  _EditorPanel.crop => Icons.crop_rounded,
                  _EditorPanel.rotate => Icons.rotate_right_rounded,
                }),
                label: Text(
                  _applyButtonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saveCurrentImage,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1F9D6A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
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
          const SizedBox(width: 10),
          _PreviewToolButton(
            label: 'Crop',
            icon: Icons.crop_rounded,
            selected: _activePanel == _EditorPanel.crop,
            onTap: () => _setActivePanel(_EditorPanel.crop),
          ),
          const SizedBox(width: 10),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                switch (_mode) {
                  _ResizeMode.dimensions => 'Dimensions (px)',
                  _ResizeMode.percentage => 'Resize Percentage',
                  _ResizeMode.preset => 'Preset Sizes',
                  _ResizeMode.bestFit => 'Best Fit Bounds',
                },
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Color(0xFF1D2033),
                ),
              ),
            ),
            Row(
              children: [
                const Text(
                  'Lock Aspect Ratio',
                  style: TextStyle(
                    color: Color(0xFF8B1BFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: Color(0xFF8B1BFF),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _lockAspectRatio,
                  onChanged: _toggleAspectLock,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF8B1BFF),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        switch (_mode) {
          _ResizeMode.dimensions => _buildDimensionsInputs(),
          _ResizeMode.percentage => _buildPercentageInputs(state),
          _ResizeMode.preset => _buildPresetGrid(),
          _ResizeMode.bestFit => _buildBestFitInputs(state),
        },
        const SizedBox(height: 10),
        Text(
          'Aspect Ratio: ${_aspectRatioLabel(target)}',
          style: const TextStyle(
            color: Color(0xFF7A3FF8),
            fontWeight: FontWeight.w800,
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.link_rounded,
              color: Color(0xFF8B1BFF),
              size: 20,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9E5FF)),
        color: Colors.white,
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
              const SizedBox(width: 10),
              const Text(
                '%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF30334A),
                ),
              ),
            ],
          ),
          Slider(
            min: 10,
            max: 200,
            divisions: 19,
            value: _percentage.clamp(10, 200),
            activeColor: const Color(0xFF8B1BFF),
            onChanged: _handlePercentageSlider,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Result: $width × $height px',
              style: const TextStyle(
                color: Color(0xFF6F748C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in _presetSizes)
          GestureDetector(
            onTap: () => _applyPreset(
              Size(preset.width.toDouble(), preset.height.toDouble()),
            ),
            child: Container(
              width: 146,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E4FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2D3148),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${preset.width} × ${preset.height}',
                    style: const TextStyle(
                      color: Color(0xFF6F748C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
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
            const SizedBox(width: 12),
            Expanded(
              child: _DimensionField(
                controller: _bestFitHeightController,
                label: 'Max Height',
                onChanged: _handleBestFitHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            target == null
                ? 'Enter bounds to fit the image.'
                : 'Output will fit inside ${target.width} × ${target.height} px.',
            style: const TextStyle(
              color: Color(0xFF6F748C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFEDE9FF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120C1234),
          blurRadius: 30,
          offset: Offset(0, 12),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFFDFDFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E8F5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E8F5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF8B1BFF), width: 1.4),
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

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: const Color(0xFF3D4159)),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7F3FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF8B1BFF) : const Color(0xFFE9E5FF),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            if (selected)
              const Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFF8B1BFF),
                  child: Icon(Icons.check, size: 13, color: Colors.white),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 30,
                    color: selected
                        ? const Color(0xFF8B1BFF)
                        : const Color(0xFF6471FF),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF252A40),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7B8096),
                      height: 1.35,
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
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'px',
        filled: true,
        fillColor: const Color(0xFFFDFDFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E8F5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E8F5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF8B1BFF), width: 1.4),
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
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFFDFDFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E8F5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E8F5)),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1E6FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFFD9B7FF) : const Color(0xFFE8EAF3),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0E0F172A),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF8B1BFF) : const Color(0xFF31364F),
            fontWeight: FontWeight.w700,
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
    return Material(
      color: selected ? const Color(0xFF8B1BFF) : const Color(0xFFF4F0FF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : const Color(0xFF7A54F8),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF3A3F5B),
                  fontWeight: FontWeight.w700,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF70758C)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF70758C),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RotateStepChip extends StatelessWidget {
  const _RotateStepChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EAF3)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF31364F),
            fontWeight: FontWeight.w700,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD3D0)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9C2D23),
          fontWeight: FontWeight.w600,
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
  late int _cropX;
  late int _cropY;
  late int _cropWidth;
  late int _cropHeight;
  Size? _containerSize;

  String? _draggingHandle;
  int? _startCropX;
  int? _startCropY;
  int? _startCropWidth;
  int? _startCropHeight;
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;

  @override
  void didUpdateWidget(_InteractiveImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingHandle != null) return;
    if (oldWidget.cropX != widget.cropX ||
        oldWidget.cropY != widget.cropY ||
        oldWidget.cropWidth != widget.cropWidth ||
        oldWidget.cropHeight != widget.cropHeight) {
      setState(() {
        _cropX = widget.cropX;
        _cropY = widget.cropY;
        _cropWidth = widget.cropWidth;
        _cropHeight = widget.cropHeight;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _cropX = widget.cropX;
    _cropY = widget.cropY;
    _cropWidth = widget.cropWidth;
    _cropHeight = widget.cropHeight;
  }

  void _onPanStart(DragStartDetails details, String handle) {
    if (widget.activePanel != _EditorPanel.crop) return;
    _draggingHandle = handle;
    _startCropX = _cropX;
    _startCropY = _cropY;
    _startCropWidth = _cropWidth;
    _startCropHeight = _cropHeight;
    _dragOffsetX = 0;
    _dragOffsetY = 0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingHandle == null ||
        widget.activePanel != _EditorPanel.crop ||
        _containerSize == null) {
      return;
    }
    _dragOffsetX += details.delta.dx;
    _dragOffsetY += details.delta.dy;
    final scaleX = widget.imageWidth / _containerSize!.width;
    final scaleY = widget.imageHeight / _containerSize!.height;
    final dx = (_dragOffsetX * scaleX).round();
    final dy = (_dragOffsetY * scaleY).round();

    int newX = _startCropX!;
    int newY = _startCropY!;
    int newWidth = _startCropWidth!;
    int newHeight = _startCropHeight!;

    switch (_draggingHandle) {
      case 'move':
        newX = (_startCropX! + dx).clamp(
          0,
          widget.imageWidth - _startCropWidth!,
        );
        newY = (_startCropY! + dy).clamp(
          0,
          widget.imageHeight - _startCropHeight!,
        );
        break;
      case 'tl':
        newX = (_startCropX! + dx).clamp(
          0,
          _startCropX! + _startCropWidth! - 10,
        );
        newY = (_startCropY! + dy).clamp(
          0,
          _startCropY! + _startCropHeight! - 10,
        );
        newWidth = (_startCropWidth! - dx).clamp(
          10,
          _startCropWidth! + _startCropX! - newX,
        );
        newHeight = (_startCropHeight! - dy).clamp(
          10,
          _startCropHeight! + _startCropY! - newY,
        );
        break;
      case 'tr':
        newY = (_startCropY! + dy).clamp(
          0,
          _startCropY! + _startCropHeight! - 10,
        );
        newWidth = (_startCropWidth! + dx).clamp(
          10,
          widget.imageWidth - _startCropX!,
        );
        newHeight = (_startCropHeight! - dy).clamp(
          10,
          _startCropHeight! + _startCropY! - newY,
        );
        break;
      case 'bl':
        newX = (_startCropX! + dx).clamp(
          0,
          _startCropX! + _startCropWidth! - 10,
        );
        newWidth = (_startCropWidth! - dx).clamp(10, widget.imageWidth - newX);
        newHeight = (_startCropHeight! + dy).clamp(
          10,
          widget.imageHeight - _startCropY!,
        );
        break;
      case 'br':
        newWidth = (_startCropWidth! + dx).clamp(
          10,
          widget.imageWidth - _startCropX!,
        );
        newHeight = (_startCropHeight! + dy).clamp(
          10,
          widget.imageHeight - _startCropY!,
        );
        break;
      case 't':
        newY = (_startCropY! + dy).clamp(
          0,
          _startCropY! + _startCropHeight! - 10,
        );
        newHeight = (_startCropHeight! - dy).clamp(
          10,
          _startCropHeight! + _startCropY! - newY,
        );
        break;
      case 'b':
        newHeight = (_startCropHeight! + dy).clamp(
          10,
          widget.imageHeight - _startCropY!,
        );
        break;
      case 'l':
        newX = (_startCropX! + dx).clamp(
          0,
          _startCropX! + _startCropWidth! - 10,
        );
        newWidth = (_startCropWidth! - dx).clamp(10, widget.imageWidth - newX);
        break;
      case 'r':
        newWidth = (_startCropWidth! + dx).clamp(
          10,
          widget.imageWidth - _startCropX!,
        );
        break;
    }

    final adjusted = _adjustCropRect(
      x: newX,
      y: newY,
      width: newWidth,
      height: newHeight,
      handle: _draggingHandle!,
    );

    setState(() {
      _cropX = adjusted.$1;
      _cropY = adjusted.$2;
      _cropWidth = adjusted.$3;
      _cropHeight = adjusted.$4;
    });

    widget.onCropUpdate(
      x: adjusted.$1,
      y: adjusted.$2,
      width: adjusted.$3,
      height: adjusted.$4,
      rebuild: false,
    );
  }

  (int, int, int, int) _adjustCropRect({
    required int x,
    required int y,
    required int width,
    required int height,
    required String handle,
  }) {
    var nextX = x;
    var nextY = y;
    var nextWidth = width;
    var nextHeight = height;

    final ratio = widget.cropAspectRatio;
    if (ratio != null && handle != 'move') {
      if (handle == 't' || handle == 'b') {
        nextWidth = math.max(10, (nextHeight * ratio).round());
      } else {
        nextHeight = math.max(10, (nextWidth / ratio).round());
      }

      if (handle == 'tl' || handle == 'l' || handle == 'bl') {
        nextX = (_startCropX! + _startCropWidth! - nextWidth).clamp(
          0,
          widget.imageWidth - 10,
        );
      }
      if (handle == 'tl' || handle == 't' || handle == 'tr') {
        nextY = (_startCropY! + _startCropHeight! - nextHeight).clamp(
          0,
          widget.imageHeight - 10,
        );
      }
    } else if (ratio == null) {
      final snapped = _snapCropRect(
        x: nextX,
        y: nextY,
        width: nextWidth,
        height: nextHeight,
      );
      nextX = snapped.$1;
      nextY = snapped.$2;
      nextWidth = snapped.$3;
      nextHeight = snapped.$4;
    }

    nextX = nextX.clamp(0, math.max(0, widget.imageWidth - 1));
    nextY = nextY.clamp(0, math.max(0, widget.imageHeight - 1));
    nextWidth = nextWidth.clamp(10, widget.imageWidth - nextX);
    nextHeight = nextHeight.clamp(10, widget.imageHeight - nextY);

    if (ratio != null) {
      final preferredHeight = math.max(10, (nextWidth / ratio).round());
      if (preferredHeight <= widget.imageHeight - nextY) {
        nextHeight = preferredHeight;
      } else {
        nextHeight = widget.imageHeight - nextY;
        nextWidth = math
            .max(10, (nextHeight * ratio).round())
            .clamp(10, widget.imageWidth - nextX);
      }
    }

    return (nextX, nextY, nextWidth, nextHeight);
  }

  (int, int, int, int) _snapCropRect({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    const threshold = 12;
    var nextX = x;
    var nextY = y;
    var nextWidth = width;
    var nextHeight = height;
    final right = nextX + nextWidth;
    final bottom = nextY + nextHeight;
    final centerX = nextX + (nextWidth / 2).round();
    final centerY = nextY + (nextHeight / 2).round();

    if (nextX.abs() <= threshold) nextX = 0;
    if (nextY.abs() <= threshold) nextY = 0;
    if ((widget.imageWidth - right).abs() <= threshold) {
      nextWidth = widget.imageWidth - nextX;
    }
    if ((widget.imageHeight - bottom).abs() <= threshold) {
      nextHeight = widget.imageHeight - nextY;
    }

    final imageCenterX = widget.imageWidth ~/ 2;
    final imageCenterY = widget.imageHeight ~/ 2;
    if ((centerX - imageCenterX).abs() <= threshold) {
      nextX = (imageCenterX - nextWidth / 2).round().clamp(
        0,
        widget.imageWidth - nextWidth,
      );
    }
    if ((centerY - imageCenterY).abs() <= threshold) {
      nextY = (imageCenterY - nextHeight / 2).round().clamp(
        0,
        widget.imageHeight - nextHeight,
      );
    }

    return (nextX, nextY, nextWidth, nextHeight);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_draggingHandle != null) {
      widget.onCropUpdate(
        x: _cropX,
        y: _cropY,
        width: _cropWidth,
        height: _cropHeight,
        rebuild: true,
      );
    }
    _draggingHandle = null;
    _startCropX = null;
    _startCropY = null;
    _startCropWidth = null;
    _startCropHeight = null;
    _dragOffsetX = 0;
    _dragOffsetY = 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.toDouble();
        final normalizedRotation = widget.rotationDegrees % 360;
        final basePreviewHeight = math
            .min(maxWidth * (widget.imageHeight / widget.imageWidth), 340)
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
                340 / math.max(rotatedHeight, 1),
              );
        final previewWidth = normalizedRotation == 0
            ? maxWidth
            : rotatedWidth * rotationScale;
        final previewHeight = normalizedRotation == 0
            ? basePreviewHeight
            : rotatedHeight * rotationScale;
        final imageDisplayWidth = widget.imageWidth * rotationScale;
        final imageDisplayHeight = widget.imageHeight * rotationScale;
        _containerSize = Size(imageDisplayWidth, imageDisplayHeight);

        return Center(
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
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
                              Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                              if (widget.activePanel == _EditorPanel.crop)
                                _InteractiveCropOverlay(
                                  cropX: _cropX,
                                  cropY: _cropY,
                                  cropWidth: _cropWidth,
                                  cropHeight: _cropHeight,
                                  imageWidth: widget.imageWidth,
                                  imageHeight: widget.imageHeight,
                                  onPanStart: _onPanStart,
                                  onPanUpdate: _onPanUpdate,
                                  onPanEnd: _onPanEnd,
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
                    child: SizedBox(
                      width: imageDisplayWidth,
                      height: imageDisplayHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        ],
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
        );
      },
    );
  }
}

class _InteractiveCropOverlay extends StatelessWidget {
  const _InteractiveCropOverlay({
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;
  final int imageWidth;
  final int imageHeight;
  final void Function(DragStartDetails details, String handle) onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final void Function(DragEndDetails details) onPanEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = constraints.biggest;
        return CustomPaint(
          painter: _InteractiveCropPainter(
            x: cropX,
            y: cropY,
            width: cropWidth,
            height: cropHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            containerSize: containerSize,
          ),
          size: Size.infinite,
          child: Stack(
            children: [
              Positioned(
                left: (cropX / imageWidth) * containerSize.width,
                top: (cropY / imageHeight) * containerSize.height,
                width: (cropWidth / imageWidth) * containerSize.width,
                height: (cropHeight / imageHeight) * containerSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) => onPanStart(details, 'move'),
                  onPanUpdate: onPanUpdate,
                  onPanEnd: onPanEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              _PositionedHandle(
                xRatio: cropX / imageWidth,
                yRatio: cropY / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'tl'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _PositionedHandle(
                xRatio: (cropX + cropWidth) / imageWidth,
                yRatio: cropY / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'tr'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _PositionedHandle(
                xRatio: cropX / imageWidth,
                yRatio: (cropY + cropHeight) / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'bl'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _PositionedHandle(
                xRatio: (cropX + cropWidth) / imageWidth,
                yRatio: (cropY + cropHeight) / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'br'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _EdgeHandle(
                edge: 't',
                xRatio: (cropX + cropWidth / 2) / imageWidth,
                yRatio: cropY / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 't'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _EdgeHandle(
                edge: 'b',
                xRatio: (cropX + cropWidth / 2) / imageWidth,
                yRatio: (cropY + cropHeight) / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'b'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _EdgeHandle(
                edge: 'l',
                xRatio: cropX / imageWidth,
                yRatio: (cropY + cropHeight / 2) / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'l'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
              _EdgeHandle(
                edge: 'r',
                xRatio: (cropX + cropWidth) / imageWidth,
                yRatio: (cropY + cropHeight / 2) / imageHeight,
                containerSize: containerSize,
                onPanStart: (d) => onPanStart(d, 'r'),
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PositionedHandle extends StatelessWidget {
  const _PositionedHandle({
    required this.xRatio,
    required this.yRatio,
    required this.containerSize,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final double xRatio;
  final double yRatio;
  final Size containerSize;
  final void Function(DragStartDetails details) onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final void Function(DragEndDetails details) onPanEnd;

  @override
  Widget build(BuildContext context) {
    const handleTouchSize = 40.0;
    return Positioned(
      left: xRatio * containerSize.width - (handleTouchSize / 2),
      top: yRatio * containerSize.height - (handleTouchSize / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: SizedBox(
          width: handleTouchSize,
          height: handleTouchSize,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8B1BFF), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeHandle extends StatelessWidget {
  const _EdgeHandle({
    required this.edge,
    required this.xRatio,
    required this.yRatio,
    required this.containerSize,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final String edge;
  final double xRatio;
  final double yRatio;
  final Size containerSize;
  final void Function(DragStartDetails details) onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final void Function(DragEndDetails details) onPanEnd;

  @override
  Widget build(BuildContext context) {
    final isVertical = edge == 't' || edge == 'b';
    final touchWidth = isVertical ? 56.0 : 36.0;
    final touchHeight = isVertical ? 28.0 : 36.0;
    return Positioned(
      left: isVertical ? xRatio * containerSize.width - (touchWidth / 2) : null,
      right: isVertical
          ? null
          : xRatio * containerSize.width - (touchWidth / 2),
      top: isVertical
          ? yRatio * containerSize.height - (touchHeight / 2)
          : null,
      bottom: isVertical
          ? null
          : yRatio * containerSize.height - (touchHeight / 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: SizedBox(
          width: touchWidth,
          height: touchHeight,
          child: Center(
            child: Container(
              width: isVertical ? 40 : 20,
              height: isVertical ? 16 : 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8B1BFF), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InteractiveCropPainter extends CustomPainter {
  _InteractiveCropPainter({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.imageWidth,
    required this.imageHeight,
    required this.containerSize,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final int imageWidth;
  final int imageHeight;
  final Size containerSize;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = containerSize.width / imageWidth;
    final scaleY = containerSize.height / imageHeight;

    final rect = Rect.fromLTWH(
      x * scaleX,
      y * scaleY,
      width * scaleX,
      height * scaleY,
    );

    final fullRect = Offset.zero & containerSize;

    final outsidePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..blendMode = BlendMode.dstOut;

    final path = Path()..addRect(fullRect);
    final cropPath = Path()..addRect(rect);
    path.addPath(cropPath, Offset.zero);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, outsidePaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final v1 = rect.left + rect.width / 3;
    final v2 = rect.left + 2 * rect.width / 3;
    canvas.drawLine(Offset(v1, rect.top), Offset(v1, rect.bottom), gridPaint);
    canvas.drawLine(Offset(v2, rect.top), Offset(v2, rect.bottom), gridPaint);

    final h1 = rect.top + rect.height / 3;
    final h2 = rect.top + 2 * rect.height / 3;
    canvas.drawLine(Offset(rect.left, h1), Offset(rect.right, h1), gridPaint);
    canvas.drawLine(Offset(rect.left, h2), Offset(rect.right, h2), gridPaint);
  }

  @override
  bool shouldRepaint(covariant _InteractiveCropPainter oldDelegate) {
    return x != oldDelegate.x ||
        y != oldDelegate.y ||
        width != oldDelegate.width ||
        height != oldDelegate.height ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight ||
        containerSize != oldDelegate.containerSize;
  }
}

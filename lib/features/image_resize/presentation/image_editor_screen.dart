import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../core/services/storage_service.dart';
import '../../../shared/widgets/ad_banner_wrapper.dart';
import '../models/social_presets.dart';
import '../state/image_editor_state.dart';

class ImageEditorScreen extends ConsumerStatefulWidget {
  const ImageEditorScreen({super.key});

  @override
  ConsumerState<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

enum _EditorTab { crop, resize, rotate, preset }

enum _PresetCategory { profile, banner }

enum _CropAspectPreset {
  free('Free', null),
  square('1:1', 1.0),
  portrait('4:5', 4 / 5),
  landscape('4:3', 4 / 3),
  widescreen('16:9', 16 / 9);

  const _CropAspectPreset(this.label, this.ratio);
  final String label;
  final double? ratio;
}

class _ImageEditorScreenState extends ConsumerState<ImageEditorScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  _EditorTab _activeTab = _EditorTab.resize;
  bool _lockAspectRatio = true;
  int _aspectWidth = 1;
  int _aspectHeight = 1;
  double _rotationAngle = 0;
  bool _flipHorizontal = false;
  bool _flipVertical = false;
  int _quality = 80;
  int _targetSizeKB = 500;
  _PresetCategory _presetCategory = _PresetCategory.profile;
  SocialPreset? _selectedPreset;
  _CropAspectPreset _cropPreset = _CropAspectPreset.free;

  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _cropXController = TextEditingController(text: '0');
  final TextEditingController _cropYController = TextEditingController(text: '0');
  final TextEditingController _cropWidthController = TextEditingController();
  final TextEditingController _cropHeightController = TextEditingController();

  bool _isPicking = false;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
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

      if (!mounted) return;
      await ref.read(imageEditorProvider.notifier).loadImage(bytes, image.name);
      if (!mounted) return;

      final state = ref.read(imageEditorProvider).value;
      if (state != null && state.hasImage) {
        _syncInputsFromImage(state.width, state.height);
      }
      InterstitialTracker.instance.trackAction();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _syncInputsFromImage(int width, int height) {
    _aspectWidth = width;
    _aspectHeight = height;
    _widthController.text = width.toString();
    _heightController.text = height.toString();
    _cropXController.text = '0';
    _cropYController.text = '0';
    _cropWidthController.text = width.toString();
    _cropHeightController.text = height.toString();
    _rotationAngle = 0;
    _flipHorizontal = false;
    _flipVertical = false;
    _cropPreset = _CropAspectPreset.free;
    setState(() {});
  }

  void _handleWidthChanged(String value) {
    if (!_lockAspectRatio) return;
    final width = int.tryParse(value);
    if (width == null || width <= 0) return;
    if (_aspectWidth == 0 || _aspectHeight == 0) return;
    final height = (width * _aspectHeight + _aspectWidth ~/ 2) ~/ _aspectWidth;
    _heightController.text = height.toString();
  }

  void _handleHeightChanged(String value) {
    if (!_lockAspectRatio) return;
    final height = int.tryParse(value);
    if (height == null || height <= 0) return;
    if (_aspectWidth == 0 || _aspectHeight == 0) return;
    final width = (height * _aspectWidth + _aspectHeight ~/ 2) ~/ _aspectHeight;
    _widthController.text = width.toString();
  }

  void _handleCropWidthChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) return;
    final x = int.tryParse(_cropXController.text) ?? 0;
    if (x + parsed > state.width) {
      _cropWidthController.text = (state.width - x).clamp(1, state.width).toString();
    }
    if (_cropPreset.ratio != null) {
      _cropHeightController.text = (parsed / _cropPreset.ratio!).round().clamp(1, state.height).toString();
    }
    setState(() {});
  }

  void _handleCropHeightChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) return;
    final y = int.tryParse(_cropYController.text) ?? 0;
    if (y + parsed > state.height) {
      _cropHeightController.text = (state.height - y).clamp(1, state.height).toString();
    }
    if (_cropPreset.ratio != null) {
      _cropWidthController.text = (parsed * _cropPreset.ratio!).round().clamp(1, state.width).toString();
    }
    setState(() {});
  }

  void _setCropPreset(_CropAspectPreset preset) {
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) return;
    setState(() => _cropPreset = preset);
    if (preset.ratio != null) {
      final width = int.tryParse(_cropWidthController.text) ?? state.width;
      _cropHeightController.text = (width / preset.ratio!).round().clamp(1, state.height).toString();
    }
  }

  Future<void> _applyCrop() async {
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) return;

    final x = int.tryParse(_cropXController.text) ?? 0;
    final y = int.tryParse(_cropYController.text) ?? 0;
    final width = int.tryParse(_cropWidthController.text) ?? state.width;
    final height = int.tryParse(_cropHeightController.text) ?? state.height;

    if (width <= 0 || height <= 0 || x + width > state.width || y + height > state.height) {
      _showSnack('Enter a valid crop area.');
      return;
    }

    await ref.read(imageEditorProvider.notifier).crop(
          x: x,
          y: y,
          width: width,
          height: height,
          format: OutputImageFormat.jpg,
          quality: 95,
        );

    if (!mounted) return;
    final newState = ref.read(imageEditorProvider).value;
    if (newState != null && newState.hasImage) {
      _syncInputsFromImage(newState.width, newState.height);
      _showSnack('Image cropped.');
      InterstitialTracker.instance.trackAction();
    }
  }

  Future<void> _applyResize() async {
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      _showSnack('Enter valid dimensions.');
      return;
    }

    await ref.read(imageEditorProvider.notifier).resize(
          width: width,
          height: height,
          format: OutputImageFormat.jpg,
          quality: _quality,
        );

    if (!mounted) return;
    final newState = ref.read(imageEditorProvider).value;
    if (newState != null && newState.hasImage) {
      _syncInputsFromImage(newState.width, newState.height);
      _showSnack('Image resized.');
      InterstitialTracker.instance.trackAction();
    }
  }

  Future<void> _applyRotate() async {
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) {
      _showSnack('Pick an image first.');
      return;
    }

    await ref.read(imageEditorProvider.notifier).rotate(
          angle: _rotationAngle,
          format: OutputImageFormat.jpg,
          quality: _quality,
        );

    if (!mounted) return;
    final newState = ref.read(imageEditorProvider).value;
    if (newState != null && newState.hasImage) {
      _syncInputsFromImage(newState.width, newState.height);
      _showSnack('Image rotated.');
      InterstitialTracker.instance.trackAction();
    }
  }

  Future<void> _applyFlip() async {
    await ref.read(imageEditorProvider.notifier).flip(
          horizontal: _flipHorizontal,
          vertical: _flipVertical,
          format: OutputImageFormat.jpg,
          quality: _quality,
        );

    if (!mounted) return;
    _showSnack('Image flipped.');
    InterstitialTracker.instance.trackAction();
  }

  Future<void> _applyPreset() async {
    final preset = _selectedPreset;
    if (preset == null) {
      _showSnack('Select a preset.');
      return;
    }

    await ref.read(imageEditorProvider.notifier).resizeToPreset(
          preset: preset,
          format: OutputImageFormat.jpg,
          quality: _quality,
        );

    if (!mounted) return;
    final newState = ref.read(imageEditorProvider).value;
    if (newState != null && newState.hasImage) {
      _syncInputsFromImage(newState.width, newState.height);
      _showSnack('Applied preset: ${preset.name}');
      InterstitialTracker.instance.trackAction();
    }
  }

  Future<void> _saveImage() async {
    final state = ref.read(imageEditorProvider).value;
    if (state == null || !state.hasImage) {
      _showSnack('No image to save.');
      return;
    }

    try {
      final result = await StorageService.saveImage(
        bytes: state.currentBytes!,
        extension: OutputImageFormat.jpg.extension,
      );

      if (!mounted) return;

      final comparison = StorageService.formatSizeComparison(
        state.fileSize,
        result.fileSize,
      );

      _showSnack('Saved: $comparison');
      await _showSaveSnackBar(result);
      InterstitialTracker.instance.trackAction();
    } catch (error) {
      _showSnack('Saving failed: $error');
    }
  }

  Future<void> _showSaveSnackBar(dynamic result) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to ${result.fileName}'),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () async {
            await Share.shareXFiles([XFile(result.filePath)]);
          },
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(imageEditorProvider);
    final state = asyncState.value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Resize'),
        actions: [
          if (state != null && state.hasImage)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => _showClearDialog(context),
              tooltip: 'Clear',
            ),
        ],
      ),
      body: state == null || !state.hasImage
          ? AdBannerWrapper(child: _buildEmptyState(context))
          : _buildEditorContent(context, state, theme, asyncState),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.tertiary.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_size_select_large_rounded,
                size: 60,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Resize & Compress Images',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Resize by dimensions, compress to target file size, rotate, flip, or apply social media presets',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isPicking ? null : _pickImage,
              icon: _isPicking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate),
              label: Text(_isPicking ? 'Selecting...' : 'Select Image'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Supports: JPG, PNG, WebP, GIF, BMP, HEIC, AVIF',
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

  Widget _buildEditorContent(
    BuildContext context,
    ImageEditorState state,
    ThemeData theme,
    AsyncValue<ImageEditorState> asyncState,
  ) {
    return Column(
      children: [
        if (asyncState.isLoading)
          LinearProgressIndicator(
            value: state.progress > 0 ? state.progress : null,
          ),
        _buildImagePreview(context, state, theme),
        _buildImageInfoRow(context, state, theme),
        _buildTabSelector(context, theme),
        Expanded(child: _buildActiveTabContent(context, state, theme)),
        _buildBottomBar(context, state, theme),
      ],
    );
  }

  Widget _buildImagePreview(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.35,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Center(
              child: Image.memory(
                state.currentBytes!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.broken_image,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageInfoRow(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.image_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            state.fileName ?? 'Image',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          _buildInfoChip(
            context,
            '${state.width}×${state.height}',
            theme.colorScheme.secondaryContainer,
            theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            StorageService.formatFileSize(state.fileSize),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildTabSelector(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: _EditorTab.values
            .map(
              (tab) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _TabButton(
                    label: _tabLabel(tab),
                    icon: _tabIcon(tab),
                    selected: _activeTab == tab,
                    onTap: () => setState(() => _activeTab = tab),
                    theme: theme,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  String _tabLabel(_EditorTab tab) {
    return switch (tab) {
      _EditorTab.crop => 'Crop',
      _EditorTab.resize => 'Resize',
      _EditorTab.rotate => 'Rotate',
      _EditorTab.preset => 'Presets',
    };
  }

  IconData _tabIcon(_EditorTab tab) {
    return switch (tab) {
      _EditorTab.crop => Icons.crop_rounded,
      _EditorTab.resize => Icons.tune_rounded,
      _EditorTab.rotate => Icons.rotate_right_rounded,
      _EditorTab.preset => Icons.grid_view_rounded,
    };
  }

  Widget _buildActiveTabContent(
    BuildContext context,
    ImageEditorState state,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: switch (_activeTab) {
        _EditorTab.crop => _buildCropTab(context, state, theme),
        _EditorTab.resize => _buildResizeTab(context, state, theme),
        _EditorTab.rotate => _buildRotateTab(context, state, theme),
        _EditorTab.preset => _buildPresetTab(context, state, theme),
      },
    );
  }

  Widget _buildCropTab(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Crop Image',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
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
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _cropXController,
                label: 'X',
                onChanged: (_) => setState(() {}),
                theme: theme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DimensionField(
                controller: _cropYController,
                label: 'Y',
                onChanged: (_) => setState(() {}),
                theme: theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _cropWidthController,
                label: 'Width',
                onChanged: _handleCropWidthChanged,
                theme: theme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DimensionField(
                controller: _cropHeightController,
                label: 'Height',
                onChanged: _handleCropHeightChanged,
                theme: theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Image: ${state.width} × ${state.height} px',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Crop area: ${_cropWidthController.text} × ${_cropHeightController.text} px',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResizeTab(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dimensions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Lock Aspect Ratio',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Switch(
              value: _lockAspectRatio,
              onChanged: (value) => setState(() => _lockAspectRatio = value),
              activeTrackColor: theme.colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DimensionField(
                controller: _widthController,
                label: 'Width',
                onChanged: _handleWidthChanged,
                theme: theme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DimensionField(
                controller: _heightController,
                label: 'Height',
                onChanged: _handleHeightChanged,
                theme: theme,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildQualitySlider(context, theme),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Compress to Target Size',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Compress image to approximately the target size by adjusting quality',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Target Size',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              _targetSizeKB >= 1000
                  ? '${(_targetSizeKB / 1000).toStringAsFixed(1)} MB'
                  : '$_targetSizeKB KB',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: _targetSizeKB.toDouble(),
          min: 100,
          max: 2000,
          divisions: 19,
          label: _targetSizeKB >= 1000
              ? '${(_targetSizeKB / 1000).toStringAsFixed(1)} MB'
              : '$_targetSizeKB KB',
          onChanged: (value) {
            setState(() => _targetSizeKB = value.round());
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('100 KB', style: TextStyle(fontSize: 11)),
            Text('500 KB', style: TextStyle(fontSize: 11)),
            Text('1 MB', style: TextStyle(fontSize: 11)),
            Text('2 MB', style: TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildRotateTab(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotate & Flip',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ActionIconButton(
              icon: const Icon(Icons.rotate_left_rounded),
              label: 'Left 90°',
              onPressed: () {
                setState(() => _rotationAngle -= 90);
                _applyRotate();
              },
              theme: theme,
            ),
            _ActionIconButton(
              icon: const Icon(Icons.rotate_right_rounded),
              label: 'Right 90°',
              onPressed: () {
                setState(() => _rotationAngle += 90);
                _applyRotate();
              },
              theme: theme,
            ),
            _ActionIconButton(
              icon: const Icon(Icons.flip_rounded),
              label: 'Flip H',
              onPressed: () {
                setState(() => _flipHorizontal = !_flipHorizontal);
                _applyFlip();
              },
              theme: theme,
            ),
            _ActionIconButton(
              icon: const Icon(Icons.flip_rounded),
              label: 'Flip V',
              onPressed: () {
                setState(() => _flipVertical = !_flipVertical);
                _applyFlip();
              },
              theme: theme,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Free Rotation',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _rotationAngle,
                min: 0,
                max: 360,
                divisions: 36,
                label: '${_rotationAngle.round()}°',
                onChanged: (value) {
                  setState(() => _rotationAngle = value);
                },
              ),
            ),
            Text(
              '${_rotationAngle.round()}°',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetTab(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Social Media Presets',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<_PresetCategory>(
          segments: const <ButtonSegment<_PresetCategory>>[
            ButtonSegment(
              value: _PresetCategory.profile,
              label: Text('Profile'),
              icon: Icon(Icons.person_rounded),
            ),
            ButtonSegment(
              value: _PresetCategory.banner,
              label: Text('Banner'),
              icon: Icon(Icons.image_rounded),
            ),
          ],
          selected: {_presetCategory},
          onSelectionChanged: (Set<_PresetCategory> selection) {
            setState(() => _presetCategory = selection.first);
          },
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _presetCategory == _PresetCategory.profile
              ? SocialPresets.profilePresets.length
              : SocialPresets.bannerPresets.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final presets = _presetCategory == _PresetCategory.profile
                ? SocialPresets.profilePresets
                : SocialPresets.bannerPresets;
            final preset = presets[index];
            return _PresetListItem(
              preset: preset,
              selected: _selectedPreset?.name == preset.name,
              onTap: () {
                setState(() => _selectedPreset = preset);
              },
              theme: theme,
            );
          },
        ),
      ],
    );
  }

  Widget _buildQualitySlider(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quality',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '$_quality%',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: _quality.toDouble(),
          min: 10,
          max: 100,
          divisions: 9,
          label: '$_quality%',
          onChanged: (value) {
            setState(() => _quality = value.round());
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, ImageEditorState state, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _ActionIconButton(
              icon: _isPicking
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: 'Add',
              onPressed: _isPicking ? null : _pickImage,
              theme: theme,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildApplyButton(context, state, theme),
            ),
            const SizedBox(width: 10),
            _ActionIconButton(
              icon: const Icon(Icons.save_alt_rounded),
              label: 'Save',
              onPressed: _saveImage,
              theme: theme,
              backgroundColor: theme.colorScheme.secondary,
              foregroundColor: theme.colorScheme.onSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyButton(
    BuildContext context,
    ImageEditorState state,
    ThemeData theme,
  ) {
    final isProcessing = state.isLoading;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 52,
      decoration: BoxDecoration(
        gradient: isProcessing
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  Color.lerp(
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                    0.3,
                  )!,
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isProcessing
            ? null
            : [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isProcessing ? null : _handleApplyAction,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: isProcessing
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(state.progress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_applyIcon, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        _applyLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  IconData get _applyIcon {
    return switch (_activeTab) {
      _EditorTab.crop => Icons.crop_rounded,
      _EditorTab.resize => Icons.tune_rounded,
      _EditorTab.rotate => Icons.rotate_right_rounded,
      _EditorTab.preset => Icons.grid_view_rounded,
    };
  }

  String get _applyLabel {
    return switch (_activeTab) {
      _EditorTab.crop => 'Crop',
      _EditorTab.resize => 'Apply',
      _EditorTab.rotate => 'Rotate',
      _EditorTab.preset => 'Apply',
    };
  }

  void _handleApplyAction() {
    switch (_activeTab) {
      case _EditorTab.crop:
        _applyCrop();
      case _EditorTab.resize:
        _applyResize();
      case _EditorTab.rotate:
        _applyRotate();
      case _EditorTab.preset:
        _applyPreset();
    }
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Image'),
        content: const Text('Remove the current image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(imageEditorProvider.notifier).clear();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
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
    required this.theme,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final ThemeData theme;

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
        fillColor: theme.colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final ThemeData theme;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _ActionIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.theme,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = foregroundColor ?? theme.colorScheme.onSurface;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(
                color: fg,
                size: 20,
              ),
              child: icon,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetListItem extends StatelessWidget {
  const _PresetListItem({
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final SocialPreset preset;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (preset.description != null)
                    Text(
                      preset.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '${preset.width}×${preset.height}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

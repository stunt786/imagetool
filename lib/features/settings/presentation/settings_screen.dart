import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/app_review_service.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/settings/app_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canPop = Navigator.of(context).canPop();
    final topPadding = MediaQuery.of(context).padding.top + (canPop ? 14 : 24);
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surface,
              scheme.surfaceContainer,
              scheme.surface,
            ],
          ),
        ),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, topPadding, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  Row(
                    children: [
                      if (canPop) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'Settings',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ── Storage ──────────────────────────────────────────────
                  _buildSection(
                    context,
                    title: 'Storage',
                    children: [
                      FutureBuilder<String>(
                        future: _resolveSaveLocation(),
                        builder: (context, snapshot) {
                          final actualPath = snapshot.data ?? 'Loading...';
                          return ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: const Text('Save Location'),
                            subtitle: Text(
                              actualPath,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _pickFolder(context, ref),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Appearance ───────────────────────────────────────────
                  _buildSection(
                    context,
                    title: 'Appearance',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.brightness_6_outlined,
                                    size: 20),
                                const SizedBox(width: 12),
                                Text('Theme', style: theme.textTheme.bodyLarge),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto_rounded),
                                  label: Text('System'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.wb_sunny_rounded),
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.nightlight_round),
                                  label: Text('Dark'),
                                ),
                              ],
                              selected: {settings.themeMode},
                              onSelectionChanged: (modes) {
                                if (modes.isNotEmpty) {
                                  ref
                                      .read(appSettingsProvider.notifier)
                                      .setThemeMode(modes.first);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── General ──────────────────────────────────────────────
                  _buildSection(
                    context,
                    title: 'General',
                    children: [
                      StatefulBuilder(
                        builder: (context, setLocalState) {
                          final oneClick =
                              ref.watch(appSettingsProvider).oneClickOpen;
                          return SwitchListTile(
                            secondary: const Icon(Icons.touch_app_outlined),
                            title: const Text('One Click Open'),
                            subtitle: const Text(
                                'Open picker directly on tool launch'),
                            value: oneClick,
                            onChanged: (value) {
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setOneClickOpen(value);
                            },
                          );
                        },
                      ),
                      const Divider(height: 1),
                      StatefulBuilder(
                        builder: (context, setLocalState) {
                          final stripExif =
                              ref.watch(appSettingsProvider).stripExif;
                          return SwitchListTile(
                            secondary:
                                const Icon(Icons.no_photography_outlined),
                            title: const Text('Strip EXIF Data'),
                            subtitle: const Text(
                              'Remove camera metadata & location when saving images',
                            ),
                            value: stripExif,
                            onChanged: (value) {
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setStripExif(value);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Watermark ────────────────────────────────────────────
                  _buildSection(
                    context,
                    title: 'Watermark',
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.subtitles_outlined),
                        title: const Text('Global Watermark'),
                        subtitle: const Text(
                          'Apply watermark automatically to all saved images & PDFs',
                        ),
                        value: settings.enableGlobalWatermark,
                        onChanged: (value) {
                          ref
                              .read(appSettingsProvider.notifier)
                              .setEnableGlobalWatermark(value);
                        },
                      ),
                      if (settings.enableGlobalWatermark) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _WatermarkLivePreview(settings: settings),
                              const SizedBox(height: 16),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.asset(
                                    'assets/icons/icon.png',
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.image_outlined),
                                  ),
                                ),
                                title: const Text('Include App Logo'),
                                subtitle: const Text(
                                  'Add icon.png alongside watermark text',
                                ),
                                value: settings.useWatermarkLogo,
                                onChanged: (val) {
                                  ref
                                      .read(appSettingsProvider.notifier)
                                      .setUseWatermarkLogo(val);
                                },
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary:
                                    const Icon(Icons.view_sidebar_outlined),
                                title: const Text(
                                    'Right Vertical Sidebar for Images'),
                                subtitle: const Text(
                                  'Apply vertical sidebar watermark with low opacity along the right side on exported images',
                                ),
                                value: settings.useImageVerticalSidebar,
                                onChanged: (val) {
                                  ref
                                      .read(appSettingsProvider.notifier)
                                      .setUseImageVerticalSidebar(val);
                                },
                              ),
                              const SizedBox(height: 12),
                              _WatermarkTextField(
                                initialValue: settings.watermarkText,
                                onChanged: (val) {
                                  ref
                                      .read(appSettingsProvider.notifier)
                                      .setWatermarkText(val);
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Color',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (final c in const [
                                    (
                                      hex: 0xFFFFFFFF,
                                      name: 'White',
                                      color: Colors.white
                                    ),
                                    (
                                      hex: 0xFF000000,
                                      name: 'Black',
                                      color: Colors.black
                                    ),
                                    (
                                      hex: 0xFFF44336,
                                      name: 'Red',
                                      color: Colors.red
                                    ),
                                    (
                                      hex: 0xFFFFEB3B,
                                      name: 'Yellow',
                                      color: Colors.yellow
                                    ),
                                    (
                                      hex: 0xFF2196F3,
                                      name: 'Blue',
                                      color: Colors.blue
                                    ),
                                    (
                                      hex: 0xFF4CAF50,
                                      name: 'Green',
                                      color: Colors.green
                                    ),
                                  ])
                                    GestureDetector(
                                      onTap: () {
                                        ref
                                            .read(appSettingsProvider.notifier)
                                            .setWatermarkColorHex(c.hex);
                                      },
                                      child: Tooltip(
                                        message: c.name,
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: c.color,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color:
                                                  settings.watermarkColorHex ==
                                                          c.hex
                                                      ? scheme.primary
                                                      : scheme.outlineVariant,
                                              width:
                                                  settings.watermarkColorHex ==
                                                          c.hex
                                                      ? 3
                                                      : 1,
                                            ),
                                          ),
                                          child: settings.watermarkColorHex ==
                                                  c.hex
                                              ? Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: c.hex == 0xFFFFFFFF ||
                                                          c.hex == 0xFFFFEB3B
                                                      ? Colors.black
                                                      : Colors.white,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Opacity',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '${(settings.watermarkOpacity * 100).round()}%',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: settings.watermarkOpacity,
                                min: 0.1,
                                max: 1.0,
                                divisions: 18,
                                label:
                                    '${(settings.watermarkOpacity * 100).round()}%',
                                onChanged: (val) {
                                  ref
                                      .read(appSettingsProvider.notifier)
                                      .setWatermarkOpacity(val);
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Position',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final pos in const [
                                    (index: 0, label: 'Top-Left'),
                                    (index: 1, label: 'Top-Right'),
                                    (index: 2, label: 'Center'),
                                    (index: 3, label: 'Bottom-Left'),
                                    (index: 4, label: 'Bottom-Right'),
                                  ])
                                    ChoiceChip(
                                      label: Text(pos.label),
                                      selected:
                                          settings.watermarkPositionIndex ==
                                              pos.index,
                                      onSelected: (selected) {
                                        if (selected) {
                                          ref
                                              .read(
                                                  appSettingsProvider.notifier)
                                              .setWatermarkPositionIndex(
                                                  pos.index);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Feedback & Support ───────────────────────────────────
                  _buildSection(
                    context,
                    title: 'Spread the Word',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.star_rate_rounded, color: Colors.amber),
                        title: const Text('Rate the App'),
                        subtitle: const Text('Review and rate on Google Play Store'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => AppReviewService.instance.showRatingDialog(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.share_rounded),
                        title: const Text('Share the App'),
                        subtitle: const Text('Share download link with friends & family'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => AppReviewService.instance.shareApp(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── App & Updates ────────────────────────────────────────
                  _buildSection(
                    context,
                    title: 'App & Updates',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.system_update_rounded),
                        title: const Text('Check for Updates'),
                        subtitle: const Text('Check and download available updates'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _checkForUpdates(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy Policy'),
                        subtitle: const Text('100% offline & on-device processing'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/privacy'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('About & Developer Info'),
                        subtitle: const Text('${AppStrings.appName} by bnbKio'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/about'),
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.tag_outlined),
                        title: Text('Version'),
                        subtitle: Text(AppUpdateService.currentAppVersion),
                      ),
                    ],
                  ),
                  const SizedBox(height: 120),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 14),
            Text('Checking for updates...'),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    final info = await AppUpdateService.instance.checkForUpdate(force: true);
    if (!context.mounted) return;

    if (info.hasUpdate) {
      await AppUpdateService.instance.showUpdateDialog(context, info);
    } else {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 10),
              Text('Latest Version'),
            ],
          ),
          content: Text(
            'You are using the latest version of ${AppStrings.appName} (v${AppUpdateService.currentAppVersion}).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Resolves the destination shown under Save Location: the SAF folder the
  /// user picked on Android, or the concrete directory on other platforms.
  Future<String> _resolveSaveLocation() async {
    if (Platform.isAndroid) {
      final customLabel = await PublicStorage.loadTreeLabel();
      if (customLabel != null && customLabel.isNotEmpty) {
        return customLabel;
      }
      return 'Pictures/PixelTools (images)\nDownload/PixelTools (PDFs)';
    }
    final dir = await ref.read(appSettingsProvider.notifier).getSaveDirectory();
    return dir.path;
  }

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    if (Platform.isAndroid) {
      await _pickAndroidSaveLocation(context);
      return;
    }

    final result = await FilePicker.getDirectoryPath();
    if (result != null && result.isNotEmpty) {
      final dir = Directory(result);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await ref.read(appSettingsProvider.notifier).setSavePath(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save location updated'), duration: Duration(seconds: 2)),
        );
      }
      if (mounted) setState(() {});
    }
  }

  /// Android: shared storage is only writable through MediaStore or a
  /// persisted SAF grant, so the custom folder is picked with the system
  /// folder picker and stored as a tree URI — no storage permission needed.
  Future<void> _pickAndroidSaveLocation(BuildContext context) async {
    final currentLabel = await PublicStorage.loadTreeLabel();
    final hasCustom = currentLabel != null && currentLabel.isNotEmpty;
    if (!context.mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save location'),
        content: Text(
          hasCustom
              ? 'New images and PDFs are saved to:\n$currentLabel'
              : 'Images are saved to Pictures/PixelTools and PDFs to '
                  'Download/PixelTools.\n\nChoose a folder to save '
                  'everything to one place instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Cancel'),
          ),
          if (hasCustom)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('default'),
              child: const Text('Use default'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('choose'),
            child: const Text('Choose folder'),
          ),
        ],
      ),
    );

    if (action == 'choose') {
      final picked = await PublicStorage.pickFolder();
      if (picked != null) {
        await PublicStorage.setSaveTree(uri: picked.uri, label: picked.label);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Save location updated'), duration: Duration(seconds: 2)),
          );
        }
      }
    } else if (action == 'default') {
      await PublicStorage.clearSaveTree();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save location reset to default'), duration: Duration(seconds: 2)),
        );
      }
    }

    if (mounted) setState(() {});
  }
}

class _WatermarkTextField extends StatefulWidget {
  const _WatermarkTextField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_WatermarkTextField> createState() => _WatermarkTextFieldState();
}

class _WatermarkTextFieldState extends State<_WatermarkTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _WatermarkTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Watermark Text',
        hintText: 'PixelTools',
        prefixIcon: const Icon(Icons.title),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        isDense: true,
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _WatermarkLivePreview extends StatefulWidget {
  final AppSettingsState settings;

  const _WatermarkLivePreview({required this.settings});

  @override
  State<_WatermarkLivePreview> createState() => _WatermarkLivePreviewState();
}

class _WatermarkLivePreviewState extends State<_WatermarkLivePreview> {
  int _previewTab = 0; // 0: Image Export, 1: PDF Export

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = widget.settings;

    Alignment alignment;
    switch (settings.watermarkPositionIndex) {
      case 0:
        alignment = Alignment.topLeft;
        break;
      case 1:
        alignment = Alignment.topRight;
        break;
      case 2:
        alignment = Alignment.center;
        break;
      case 3:
        alignment = Alignment.bottomLeft;
        break;
      case 4:
      default:
        alignment = Alignment.bottomRight;
        break;
    }

    final isImageTab = _previewTab == 0;
    final contentOpacity = isImageTab && settings.useImageVerticalSidebar
        ? (settings.watermarkOpacity * 0.50).clamp(0.20, 0.40)
        : settings.watermarkOpacity.clamp(0.10, 1.0);

    final textColor =
        Color(settings.watermarkColorHex).withValues(alpha: contentOpacity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Live Preview',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Image'),
                  icon: Icon(Icons.image_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('PDF'),
                  icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                ),
              ],
              selected: {_previewTab},
              onSelectionChanged: (set) {
                setState(() => _previewTab = set.first);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isImageTab
                ? (isDark ? const Color(0xFF192231) : const Color(0xFFE2E8F0))
                : (isDark ? const Color(0xFF1E1E2C) : const Color(0xFFF3F4F8)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Stack(
            children: [
              if (isImageTab) ...[
                // Simulated photo content with subtle landscape graphic
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Opacity(
                      opacity: isDark ? 0.25 : 0.18,
                      child: Row(
                        children: [
                          Icon(
                            Icons.landscape_rounded,
                            size: 64,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  height: 8,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 6,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Simulated PDF document mockup lines
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 10,
                        width: 80,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 8,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 8,
                        width: 160,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 8,
                        width: 220,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Format indicator badge
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    isImageTab
                        ? (settings.useImageVerticalSidebar
                            ? 'Image • Vertical Sidebar'
                            : 'Image • Corner')
                        : 'PDF • Corner Watermark',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              // Watermark overlay
              if (isImageTab && settings.useImageVerticalSidebar)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (settings.useWatermarkLogo) ...[
                              Opacity(
                                opacity: contentOpacity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: Image.asset(
                                    'assets/icons/icon.png',
                                    width: 12,
                                    height: 12,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.diamond_outlined,
                                      size: 12,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (settings.watermarkText.isNotEmpty)
                              Text(
                                settings.watermarkText,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Align(
                  alignment: alignment,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (settings.useWatermarkLogo) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: Image.asset(
                              'assets/icons/icon.png',
                              width: 14,
                              height: 14,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.diamond_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (settings.watermarkText.isNotEmpty)
                          Flexible(
                            child: Text(
                              settings.watermarkText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/settings/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topPadding = MediaQuery.of(context).padding.top + 72;
    final settings = ref.watch(appSettingsProvider);

    return DecoratedBox(
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
                Text(
                  'Settings',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 24),
                // ── Storage ──────────────────────────────────────────────
                _buildSection(
                  context,
                  title: 'Storage',
                  children: [
                    FutureBuilder<Directory>(
                      future: ref.read(appSettingsProvider.notifier).getSaveDirectory(),
                      builder: (context, snapshot) {
                        final actualPath = snapshot.data?.path ?? 'Loading...';
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.brightness_6_outlined, size: 20),
                              const SizedBox(width: 12),
                              Text('Theme', style: theme.textTheme.bodyLarge),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<ThemeMode>(
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
                        final oneClick = ref.watch(appSettingsProvider).oneClickOpen;
                        return SwitchListTile(
                          secondary: const Icon(Icons.touch_app_outlined),
                          title: const Text('One Click Open'),
                          subtitle: const Text('Open picker directly on tool launch'),
                          value: oneClick,
                          onChanged: (value) {
                            ref.read(appSettingsProvider.notifier).setOneClickOpen(value);
                          },
                        );
                      },
                    ),
                    const Divider(height: 1),
                    StatefulBuilder(
                      builder: (context, setLocalState) {
                        final stripExif = ref.watch(appSettingsProvider).stripExif;
                        return SwitchListTile(
                          secondary: const Icon(Icons.no_photography_outlined),
                          title: const Text('Strip EXIF Data'),
                          subtitle: const Text(
                            'Remove camera metadata & location when saving images',
                          ),
                          value: stripExif,
                          onChanged: (value) {
                            ref.read(appSettingsProvider.notifier).setStripExif(value);
                          },
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: const Text('Rate the App'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Rate us on the App Store!')),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.share_outlined),
                      title: const Text('Share App'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Share.share(
                          'Edit images and PDFs offline with ${AppStrings.appName}.',
                          subject: AppStrings.appName,
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: const Text('Contact Us'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showContactDialog(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('Help'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showHelpDialog(context),
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (final c in const [
                                  (hex: 0xFFFFFFFF, name: 'White', color: Colors.white),
                                  (hex: 0xFF000000, name: 'Black', color: Colors.black),
                                  (hex: 0xFFF44336, name: 'Red', color: Colors.red),
                                  (hex: 0xFFFFEB3B, name: 'Yellow', color: Colors.yellow),
                                  (hex: 0xFF2196F3, name: 'Blue', color: Colors.blue),
                                  (hex: 0xFF4CAF50, name: 'Green', color: Colors.green),
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
                                            color: settings.watermarkColorHex == c.hex
                                                ? scheme.primary
                                                : scheme.outlineVariant,
                                            width: settings.watermarkColorHex == c.hex ? 3 : 1,
                                          ),
                                        ),
                                        child: settings.watermarkColorHex == c.hex
                                            ? Icon(
                                                Icons.check,
                                                size: 20,
                                                color: c.hex == 0xFFFFFFFF || c.hex == 0xFFFFEB3B
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Opacity',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${(settings.watermarkOpacity * 100).round()}%',
                                  style: theme.textTheme.labelMedium?.copyWith(
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
                              label: '${(settings.watermarkOpacity * 100).round()}%',
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
                                    selected: settings.watermarkPositionIndex == pos.index,
                                    onSelected: (selected) {
                                      if (selected) {
                                        ref
                                            .read(appSettingsProvider.notifier)
                                            .setWatermarkPositionIndex(pos.index);
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
                // ── About ────────────────────────────────────────────────
                _buildSection(
                  context,
                  title: 'About',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy'),
                      subtitle: const Text('All processing stays on-device.'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('App'),
                      subtitle: const Text(AppStrings.appName),
                    ),
                    ListTile(
                      leading: const Icon(Icons.tag_outlined),
                      title: const Text('Version'),
                      subtitle: const Text('1.0.0'),
                    ),
                  ],
                ),
                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
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

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.getDirectoryPath();
    if (result != null && result.isNotEmpty) {
      final dir = Directory(result);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await ref.read(appSettingsProvider.notifier).setSavePath(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save location updated')),
        );
      }
    }
  }

  void _showContactDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Us'),
        content: const Text(
          'Reach us at support@pixeltools.app for feedback, feature requests, or bug reports.',
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

  void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help'),
        content: const Text(
          'Use the tools grid for quick actions. My Files tab shows your saved work. Tap any history item to preview it again.',
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
        hintText: '© PixelTools',
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

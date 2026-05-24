import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/widgets/premium_banner.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topPadding = MediaQuery.of(context).padding.top + 72;

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
                const SizedBox(height: 16),
                const PremiumBanner(),
                const SizedBox(height: 24),
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
                          subtitle: const Text('Skip tool home screens and directly open gallery or file picker'),
                          value: oneClick,
                          onChanged: (value) {
                            ref.read(appSettingsProvider.notifier).setOneClickOpen(value);
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
          SnackBar(content: Text('Save location changed to $result')),
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
          'Use Quick Tools for fast actions, the Images tab for visual workflows, and Recent History to reopen your latest work.',
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

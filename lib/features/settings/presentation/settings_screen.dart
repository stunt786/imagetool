import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/services/permission_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                    title: const Text('Default Save Location'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getLocationLabel(settings.saveLocation)),
                        if (snapshot.hasData)
                          Text(
                            actualPath,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showLocationPicker(context, ref),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'Permissions',
            children: [
              FutureBuilder<bool>(
                future: const AppPermissionService().hasStoragePermission(),
                builder: (context, snapshot) {
                  final granted = snapshot.data ?? false;
                  return ListTile(
                    leading: Icon(
                      granted ? Icons.check_circle : Icons.warning_amber_outlined,
                      color: granted ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    title: const Text('Photos & Storage'),
                    subtitle: Text(granted ? 'Granted' : 'Not granted'),
                    trailing: granted
                        ? null
                        : FilledButton.tonal(
                            onPressed: () => const AppPermissionService().requestAllPermissions(),
                            child: const Text('Grant'),
                          ),
                    onTap: granted
                        ? null
                        : () => const AppPermissionService().requestAllPermissions(),
                  );
                },
              ),
              FutureBuilder<bool>(
                future: const AppPermissionService().hasCameraPermission(),
                builder: (context, snapshot) {
                  final granted = snapshot.data ?? false;
                  return ListTile(
                    leading: Icon(
                      granted ? Icons.check_circle : Icons.warning_amber_outlined,
                      color: granted ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    title: const Text('Camera'),
                    subtitle: Text(granted ? 'Granted' : 'Not granted'),
                    trailing: granted
                        ? null
                        : FilledButton.tonal(
                            onPressed: () => const AppPermissionService().requestAllPermissions(),
                            child: const Text('Grant'),
                          ),
                    onTap: granted
                        ? null
                        : () => const AppPermissionService().requestAllPermissions(),
                  );
                },
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
                title: const Text('About'),
                subtitle: const Text(AppStrings.appName),
              ),
            ],
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

  String _getLocationLabel(String location) {
    switch (location) {
      case 'downloads':
        return 'Downloads';
      case 'external':
        return 'External Storage';
      case 'app_documents':
      default:
        return 'App Documents';
    }
  }

  void _showLocationPicker(BuildContext context, WidgetRef ref) {
    final settings = ref.read(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LocationOption(
              label: 'App Documents',
              description: 'Private app folder (no permission needed)',
              value: 'app_documents',
              isSelected: settings.saveLocation == 'app_documents',
              onTap: () {
                notifier.setSaveLocation('app_documents');
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
            _LocationOption(
              label: 'Downloads',
              description: 'Save to device Downloads folder',
              value: 'downloads',
              isSelected: settings.saveLocation == 'downloads',
              onTap: () {
                notifier.setSaveLocation('downloads');
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
            _LocationOption(
              label: 'External Storage',
              description: 'Save to external SD card or storage',
              value: 'external',
              isSelected: settings.saveLocation == 'external',
              onTap: () {
                notifier.setSaveLocation('external');
                Navigator.of(context).pop();
              },
            ),
          ],
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

class _LocationOption extends StatelessWidget {
  const _LocationOption({
    required this.label,
    required this.description,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String description;
  final String value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerLowest,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: value,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

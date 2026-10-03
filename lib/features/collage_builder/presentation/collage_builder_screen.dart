import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../notifiers/collage_notifier.dart';
import '../widgets/collage_canvas.dart';
import '../widgets/collage_toolbar.dart';
import '../widgets/layout_selector.dart';

class CollageBuilderScreen extends ConsumerStatefulWidget {
  const CollageBuilderScreen({super.key});

  @override
  ConsumerState<CollageBuilderScreen> createState() =>
      _CollageBuilderScreenState();
}

class _CollageBuilderScreenState extends ConsumerState<CollageBuilderScreen> {
  bool _hasAutoTriggered = false;
  bool _isOneClickOpening = false;

  @override
  void initState() {
    super.initState();
    _isOneClickOpening = ref.read(appSettingsProvider).oneClickOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(collageProvider.notifier).reset();
      if (_isOneClickOpening && !_hasAutoTriggered) {
        _hasAutoTriggered = true;
        setState(() => _isOneClickOpening = false);
        final state = ref.read(collageProvider);
        if (state.imageCount == 0) {
          ref.read(collageProvider.notifier).pickImages(context);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collage Builder'),
        actions: [
          if (state.imageCount > 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(collageProvider.notifier).reset(),
              tooltip: 'Reset',
            ),
        ],
      ),
      body: state.imageCount == 0
          ? _isOneClickOpening
              ? const Center(child: CircularProgressIndicator())
              : _buildSelectPhotosScreen(context)
          : _buildCollageEditor(context),
    );
  }

  Widget _buildSelectPhotosScreen(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library,
                size: 60,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Collage Builder',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Create stunning collages with up to 9 photos, customizable grid layouts, spacing, and text.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                ref.read(collageProvider.notifier).pickImages(context);
              },
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Select Photos (up to 9)'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollageEditor(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: const CollageCanvas(),
                  ),
                ),
                const SizedBox(height: 12),
                const LayoutSelector(),
              ],
            ),
          ),
        ),
        const CollageToolbar(),
      ],
    );
  }
}

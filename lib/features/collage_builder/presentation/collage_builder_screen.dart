import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/utils/deferred_clear.dart';
import '../../../shared/widgets/centered_scrollable.dart';
import '../models/collage_state.dart';
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

  late final CollageNotifier _collageNotifier;

  @override
  void initState() {
    super.initState();
    _collageNotifier = ref.read(collageProvider.notifier);
    _isOneClickOpening = ref.read(appSettingsProvider).oneClickOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_isOneClickOpening && !_hasAutoTriggered) {
        _hasAutoTriggered = true;
        final state = ref.read(collageProvider);
        if (state.imageCount == 0) {
          try {
            await ref.read(collageProvider.notifier).pickImages(context);
          } finally {
            if (mounted) {
              setState(() => _isOneClickOpening = false);
            }
          }
        } else {
          setState(() => _isOneClickOpening = false);
        }
      }
    });
  }

  @override
  void dispose() {
    // Release slot bytes and the secondary preview cache when the tool closes;
    // deferred so listener notification never runs during tree teardown.
    runDeferredClear(_collageNotifier.reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collageProvider);
    final showLoading =
        state.isLoading || (_isOneClickOpening && state.imageCount == 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collage Builder'),
        actions: [
          if (state.imageCount > 0 && !showLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(collageProvider.notifier).reset(),
              tooltip: 'Reset',
            ),
        ],
      ),
      body: showLoading
          ? _buildLoadingScreen(context, state)
          : state.imageCount == 0
              ? _buildSelectPhotosScreen(context)
              : _buildCollageEditor(context),
    );
  }

  Widget _buildLoadingScreen(BuildContext context, CollageState state) {
    final theme = Theme.of(context);
    final countText = state.totalCount > 0
        ? '${state.loadedCount} of ${state.totalCount}'
        : null;
    final message = state.loadingMessage ?? 'Loading images...';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading Photos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (countText != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  countText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectPhotosScreen(BuildContext context) {
    return CenteredScrollable(
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

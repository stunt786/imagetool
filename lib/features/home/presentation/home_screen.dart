import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../camera/presentation/camera_screen.dart';
import '../../files/notifiers/operation_library_notifier.dart';
import '../../files/presentation/file_preview_screen.dart';
import '../../files/presentation/operation_folder_screen.dart';
import '../../files/services/file_actions.dart';
import '../../files/widgets/file_thumbnail.dart';
import '../../files/widgets/selection_action_bar.dart';
import '../../onboarding/presentation/feature_highlight_overlay.dart';

final _imageTools = <_ToolData>[
  _ToolData(
    title: 'Scan Docs',
    subtitle: 'Scan documents to PDF',
    icon: Icons.document_scanner_rounded,
    route: '/camera',
    accent: const Color(0xFF0891B2),
    gradient: const [Color(0xFF06B6D4), Color(0xFF0891B2)],
    onTap: (context) {
      try {
        ProviderScope.containerOf(context, listen: false)
            .read(cameraLaunchTriggerProvider.notifier)
            .state++;
      } catch (_) {}
      final shell = StatefulNavigationShell.of(context);
      shell.goBranch(1, initialLocation: true);
    },
  ),
  _ToolData(
    title: 'Resize',
    subtitle: 'Pixels, ratio, or presets',
    icon: Icons.aspect_ratio_rounded,
    route: '/images/resizer',
    accent: const Color(0xFF2563EB),
    gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
  ),
  _ToolData(
    title: 'Collage',
    subtitle: 'Multi-photo layouts',
    icon: Icons.grid_view_rounded,
    route: '/images/collage',
    accent: const Color(0xFF9333EA),
    gradient: const [Color(0xFFA855F7), Color(0xFF9333EA)],
  ),
  _ToolData(
    title: 'Convert',
    subtitle: 'JPG, PNG, WEBP & more',
    icon: Icons.sync_rounded,
    route: '/images/convert',
    accent: const Color(0xFF15803D),
    gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
  ),
  _ToolData(
    title: 'Image → PDF',
    subtitle: 'Photos to PDF',
    icon: Icons.picture_as_pdf_rounded,
    route: '/images/to-pdf',
    accent: const Color(0xFFE64A19),
    gradient: const [Color(0xFFF97316), Color(0xFFEA580C)],
  ),
];

const _pdfTools = <_ToolData>[
  _ToolData(
    title: 'Compress',
    subtitle: 'Reduce PDF size',
    icon: Icons.compress_rounded,
    route: '/pdfs/compress',
    accent: Color(0xFF5B4DFF),
    gradient: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
  ),
  _ToolData(
    title: 'Merge',
    subtitle: 'Combine documents',
    icon: Icons.call_merge_rounded,
    route: '/pdfs/merge',
    accent: Color(0xFF0F9D9A),
    gradient: [Color(0xFF14B8A6), Color(0xFF0D9488)],
  ),
  _ToolData(
    title: 'Split',
    subtitle: 'Extract pages',
    icon: Icons.call_split_rounded,
    route: '/pdfs/split',
    accent: Color(0xFFEA580C),
    gradient: [Color(0xFFFB923C), Color(0xFFF97316)],
  ),
  _ToolData(
    title: 'Extract',
    subtitle: 'PDF to images or text',
    icon: Icons.crop_rotate_rounded,
    route: '/pdfs/convert',
    accent: Color(0xFF15803D),
    gradient: [Color(0xFF10B981), Color(0xFF059669)],
  ),
];

final _allTools = [..._imageTools, ..._pdfTools];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.instance.checkAndPromptAutoUpdate(context);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_ToolData> get _filteredTools {
    if (_searchQuery.isEmpty) return _allTools;
    final query = _searchQuery.toLowerCase().replaceAll(' ', '');
    return _allTools
        .where((t) =>
            t.title.toLowerCase().replaceAll(' ', '').contains(query) ||
            t.subtitle.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  final Set<String> _selectedOperations = <String>{};
  bool _busy = false;

  void _toggleOperation(String id) {
    setState(() {
      if (_selectedOperations.contains(id)) {
        _selectedOperations.remove(id);
      } else {
        _selectedOperations.add(id);
      }
    });
  }

  void _clearOperationSelection() {
    if (!mounted) return;
    setState(_selectedOperations.clear);
  }

  List<OperationFolder> _selectedOpsList(List<OperationFolder> all) {
    return all.where((op) => _selectedOperations.contains(op.id)).toList();
  }

  List<AppFileItem> _filesForOps(List<OperationFolder> operations) {
    return [
      for (final op in operations)
        ...ref.read(operationStoreProvider).filesFor(op.id),
    ];
  }

  Future<void> _deleteSelectedOps(List<OperationFolder> all) async {
    final ops = _selectedOpsList(all);
    if (ops.isEmpty) return;
    final files = _filesForOps(ops);
    final confirmed = await FileActions.confirmDelete(
      context,
      title: ops.length == 1
          ? 'Delete this operation?'
          : 'Delete ${ops.length} operations?',
      message: '${files.length} file(s) will be removed from this app.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(operationLibraryProvider.notifier);
      for (final op in ops) {
        await notifier.deleteOperation(op.id);
      }
      _clearOperationSelection();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameOp(OperationFolder operation) async {
    final name = await FileActions.promptForName(
      context,
      title: 'Rename Operation',
      initialValue: operation.displayName,
    );
    if (name == null) return;
    await ref
        .read(operationLibraryProvider.notifier)
        .renameOperation(operation.id, name);
  }

  String? _thumbnailFor(OperationFolder op) {
    if (op.thumbnailPath != null) return op.thumbnailPath;
    final files = ref.read(operationStoreProvider).filesFor(op.id);
    return files.isEmpty ? null : files.first.path;
  }

  List<EditHistoryItem> _filteredHistory(List<EditHistoryItem> history) {
    if (_searchQuery.isEmpty) return [];
    return history
        .where((item) =>
            item.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            item.toolUsed.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final library = ref.watch(operationLibraryProvider);
    final operations = library.operations;
    final history = ref.watch(editHistoryProvider);
    final width = MediaQuery.sizeOf(context).width;
    final contentPadding = width >= 1200
        ? 28.0
        : width >= 700
            ? 24.0
            : 18.0;
    final topPadding = MediaQuery.of(context).padding.top + 12;

    final filteredTools = _filteredTools;
    final filteredHistory = _filteredHistory(history);
    final isSearching = _searchQuery.isNotEmpty;

    return Scaffold(
      bottomNavigationBar: _selectedOperations.isNotEmpty
          ? SelectionActionBar(
              actions: [
                SelectionAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _busy
                      ? null
                      : () {
                          final ops = _selectedOpsList(operations);
                          final files = _filesForOps(ops);
                          FileActions.share(context, files);
                        },
                ),
                SelectionAction(
                  icon: Icons.download_outlined,
                  label: 'Save',
                  onTap: _busy
                      ? null
                      : () {
                          final ops = _selectedOpsList(operations);
                          final files = _filesForOps(ops);
                          FileActions.save(context, files);
                        },
                ),
                if (_selectedOperations.length == 1)
                  SelectionAction(
                    icon: Icons.drive_file_rename_outline,
                    label: 'Rename',
                    onTap: _busy
                        ? null
                        : () {
                            final ops = _selectedOpsList(operations);
                            if (ops.isNotEmpty) _renameOp(ops.first);
                          },
                  ),
                SelectionAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  destructive: true,
                  onTap: _busy ? null : () => _deleteSelectedOps(operations),
                ),
              ],
            )
          : null,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [
                    Color(0xFF070B14),
                    Color(0xFF0A101F),
                    Color(0xFF070B14)
                  ]
                : const [
                    Color(0xFFFDF7FF),
                    Color(0xFFF9FBFF),
                    Color(0xFFFFFCF8)
                  ],
          ),
        ),
        child: Stack(
          children: [
            if (!isDark) ...[
              const Positioned(
                top: -80,
                left: -40,
                child: _AmbientOrb(
                  size: 220,
                  colors: [Color(0xFFC9D9FF), Color(0x00C9D9FF)],
                ),
              ),
              const Positioned(
                top: 220,
                right: -70,
                child: _AmbientOrb(
                  size: 250,
                  colors: [Color(0xFFFFD7F4), Color(0x00FFD7F4)],
                ),
              ),
              const Positioned(
                bottom: 120,
                left: -60,
                child: _AmbientOrb(
                  size: 210,
                  colors: [Color(0xFFD9FFD9), Color(0x00D9FFD9)],
                ),
              ),
            ],
            Column(
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                      contentPadding, topPadding, contentPadding, 0),
                  child: Column(
                    children: [
                      const _HomeTopBar(),
                      const SizedBox(height: 16),
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          color: isDark
                              ? const Color(0xFF131D31)
                              : scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          style: TextStyle(
                            color: isDark ? Colors.white : scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search tools...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? const Color(0xFF8E9BB0)
                                  : scheme.onSurfaceVariant,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 22,
                              color: isDark
                                  ? const Color(0xFF8E9BB0)
                                  : scheme.onSurfaceVariant,
                            ),
                            suffixIcon: isSearching
                                ? IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                      color: isDark
                                          ? const Color(0xFF8E9BB0)
                                          : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : Icon(
                                    Icons.tune_rounded,
                                    size: 22,
                                    color: isDark
                                        ? const Color(0xFF8E9BB0)
                                        : scheme.onSurfaceVariant,
                                  ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (isSearching &&
                          filteredTools.isEmpty &&
                          filteredHistory.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 48,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              Text(
                                'No results found for "$_searchQuery"',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: isSearching
                      ? ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                              contentPadding, 16, contentPadding, 110),
                          children: [
                            if (filteredTools.isNotEmpty) ...[
                              _SectionHeader(title: 'Tools'),
                              const SizedBox(height: 12),
                              ...filteredTools.map(
                                (tool) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SearchToolRow(data: tool),
                                ),
                              ),
                            ],
                            if (filteredHistory.isNotEmpty) ...[
                              if (filteredTools.isNotEmpty)
                                const SizedBox(height: 8),
                              _SectionHeader(title: 'Files'),
                              const SizedBox(height: 12),
                              ...filteredHistory.asMap().entries.map(
                                    (entry) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _HistoryRow(
                                        item: entry.value,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => FilePreviewScreen(
                                              items: filteredHistory,
                                              initialIndex: entry.key,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        )
                      : CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                contentPadding,
                                16,
                                contentPadding,
                                0,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate.fixed([
                                  const _HomeHeroBanner(),
                                  const SizedBox(height: 18),
                                  _ToolsGrid(
                                    key: (!ref.watch(appSettingsProvider.select(
                                                (s) => s.hasCompletedOnboarding)) &&
                                            (ModalRoute.of(context)?.isCurrent ?? true))
                                        ? ref
                                            .watch(featureHighlightKeysProvider)
                                            .toolsKey
                                        : null,
                                    tools: _allTools,
                                  ),
                                  const SizedBox(height: 22),
                                  _SectionHeader(
                                    title: 'Recent History',
                                    showClockIcon: true,
                                    actionLabel: (operations.isNotEmpty ||
                                            history.isNotEmpty)
                                        ? 'See All'
                                        : null,
                                    onActionTap: (operations.isNotEmpty ||
                                            history.isNotEmpty)
                                        ? () => context.push('/history')
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  if (operations.isNotEmpty)
                                    ...operations.take(10).map(
                                          (op) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12),
                                            child: _OperationHistoryRow(
                                              operation: op,
                                              thumbnailPath: _thumbnailFor(op),
                                              selected: _selectedOperations
                                                  .contains(op.id),
                                              selectionMode: _selectedOperations
                                                  .isNotEmpty,
                                              onTap: () {
                                                if (_selectedOperations
                                                    .isNotEmpty) {
                                                  _toggleOperation(op.id);
                                                } else {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          OperationFolderScreen(
                                                              operationId:
                                                                  op.id),
                                                    ),
                                                  );
                                                }
                                              },
                                              onLongPress: () =>
                                                  _toggleOperation(op.id),
                                              onToggleSelected: () =>
                                                  _toggleOperation(op.id),
                                            ),
                                          ),
                                        )
                                  else if (history.isNotEmpty)
                                    ...history
                                        .take(10)
                                        .toList()
                                        .asMap()
                                        .entries
                                        .map(
                                          (entry) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 14),
                                            child: _HistoryRow(
                                              item: entry.value,
                                              onTap: () =>
                                                  Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      FilePreviewScreen(
                                                    items: history,
                                                    initialIndex: history
                                                        .indexOf(entry.value),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                  else
                                    const _EmptyHistoryCard(),
                                  const SizedBox(height: 110),
                                ]),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        // Settings button on top left
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/settings'),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isDark
                    ? const Color(0xFF131D31)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                Icons.settings_outlined,
                size: 22,
                color: isDark ? Colors.white : scheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // Title: "PixelTools"
        Expanded(
          child: Text(
            'PixelTools',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: isDark ? Colors.white : scheme.onSurface,
            ),
          ),
        ),
        // App logo to right side
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : scheme.shadow.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/icons/icon.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeHeroBanner extends StatelessWidget {
  const _HomeHeroBanner();

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 380;

    return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2856),
                Color(0xFF0A1B38),
                Color(0xFF08142B),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF2563EB).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Positioned(
                  right: 20,
                  top: -20,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.14),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 14 : 18,
                    16,
                    isCompact ? 10 : 14,
                    16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.handyman_rounded,
                                    size: 15,
                                    color: Color(0xFF60A5FA),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Work Smarter',
                                    style: TextStyle(
                                      color: Color(0xFF60A5FA),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Convert, Edit, Create',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                  fontSize: 18.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'All in ',
                                    style: TextStyle(color: Color(0xFF38BDF8)),
                                  ),
                                  TextSpan(
                                    text: 'One Place',
                                    style: TextStyle(color: Color(0xFFE879F9)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Simple tools for your daily digital tasks.',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: isCompact ? 92 : 125,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: const _BannerIllustration(),
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

class _BannerIllustration extends StatelessWidget {
  const _BannerIllustration();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 105,
          height: 90,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Blue image card (back left)
              Positioned(
                left: 6,
                top: 8,
                child: Transform.rotate(
                  angle: -0.18,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.image_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
              // Red/Pink PDF card (back right)
              Positioned(
                right: 20,
                top: 4,
                child: Transform.rotate(
                  angle: 0.15,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF43F5E), Color(0xFFE11D48)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
              // Green Excel card (front left)
              Positioned(
                left: 36,
                bottom: 4,
                child: Transform.rotate(
                  angle: 0.08,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'X',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Light blue document card (front right)
              Positioned(
                right: 4,
                bottom: 12,
                child: Transform.rotate(
                  angle: -0.12,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.menu_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
              // Sparkle star
              const Positioned(
                left: 2,
                bottom: 14,
                child: Icon(Icons.auto_awesome,
                    color: Color(0xFF38BDF8), size: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        // Forward circular button >
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          child: const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  const _ToolsGrid({super.key, required this.tools});

  final List<_ToolData> tools;

  static int calculateCrossAxisCount(double width) {
    if (width >= 900) return 6;
    if (width >= 620) return 5;
    if (width >= 470) return 4;
    return 3;
  }

  static double calculateMainAxisExtent(double width) {
    if (width < 340) return 92.0;
    if (width < 600) return 98.0;
    return 102.0;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = calculateCrossAxisCount(width);
    final mainAxisExtent = calculateMainAxisExtent(width);
    final spacing = width < 360 ? 8.0 : 10.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) => _ToolCard(data: tools[index]),
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.data});

  final _ToolData data;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final data = widget.data;
    final gradient = data.effectiveGradient;
    final width = MediaQuery.sizeOf(context).width;
    final isVeryCompact = width < 340;
    final isCompact = width < 370;

    final iconBoxSize = isVeryCompact
        ? 32.0
        : isCompact
            ? 35.0
            : 38.0;
    final iconSize = isVeryCompact
        ? 17.0
        : isCompact
            ? 18.5
            : 20.0;
    final chevronSize = isVeryCompact
        ? 14.0
        : isCompact
            ? 15.5
            : 17.0;
    final horizontalPadding = isVeryCompact
        ? 7.0
        : isCompact
            ? 8.5
            : 10.0;
    final verticalPadding = isVeryCompact
        ? 7.0
        : isCompact
            ? 8.0
            : 9.0;
    final titleFontSize = isVeryCompact
        ? 12.0
        : isCompact
            ? 12.5
            : 13.5;
    final subtitleFontSize = isVeryCompact
        ? 9.5
        : isCompact
            ? 10.0
            : 11.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color:
                isDark ? const Color(0xFF0F172A) : scheme.surfaceContainerLow,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : scheme.shadow.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (data.onTap != null) {
                  data.onTap!(context);
                } else {
                  context.push(data.route);
                }
              },
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top row: rounded icon container on left, chevron on right
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: iconBoxSize,
                            height: iconBoxSize,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(isCompact ? 10 : 12),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: gradient,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: gradient.first.withValues(alpha: 0.3),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              data.icon,
                              size: iconSize,
                              color: Colors.white,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: chevronSize,
                            color: isDark
                                ? const Color(0xFF64748B)
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                          ),
                        ],
                      ),
                      // Bottom: title and subtitle, left-aligned
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              data.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : scheme.onSurface,
                                fontSize: titleFontSize,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 1.5),
                            Text(
                              data.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : scheme.onSurfaceVariant,
                                fontSize: subtitleFontSize,
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
          ),
        ),
      ),
    );
  }
}

class _SearchToolRow extends StatelessWidget {
  const _SearchToolRow({required this.data});

  final _ToolData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gradient = data.effectiveGradient;

    return GestureDetector(
      onTap: () {
        if (data.onTap != null) {
          data.onTap!(context);
        } else {
          context.push(data.route);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? const Color(0xFF131D31)
              : scheme.surfaceContainerLowest.withValues(alpha: 0.84),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradient.first.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(data.icon, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : scheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark
                  ? const Color(0xFF64748B)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, this.onTap});

  final EditHistoryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isPdf = item.fileName.toLowerCase().endsWith('.pdf') ||
        item.toolUsed.toLowerCase().contains('pdf');
    final dateLabel = DateFormat('MMM d, yyyy').format(item.editedAt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color:
              isDark ? const Color(0xFF131D31) : scheme.surfaceContainerLowest,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            _HistoryThumbnail(item: item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : scheme.onSurface,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF64748B)
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.toolUsed,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Pill badge: Image / PDF
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isPdf
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : const Color(0xFF6366F1).withValues(alpha: 0.15),
              ),
              child: Text(
                isPdf ? 'PDF' : 'Image',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      isPdf ? const Color(0xFFF87171) : const Color(0xFF818CF8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark
                  ? const Color(0xFF64748B)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryThumbnail extends StatelessWidget {
  const _HistoryThumbnail({required this.item});

  final EditHistoryItem item;

  @override
  Widget build(BuildContext context) {
    if (item.thumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(item.thumbnailPath!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildGradientFallback(),
        ),
      );
    }
    return _buildGradientFallback();
  }

  Widget _buildGradientFallback() {
    final gradient = _historyGradient(item.toolUsed);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Center(
        child: Icon(item.toolIcon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark
            ? const Color(0xFF131D31)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: Color(0xFF38BDF8),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Recent edits will appear here after you start using the tools.',
              style: TextStyle(
                color:
                    isDark ? const Color(0xFF94A3B8) : scheme.onSurfaceVariant,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.showClockIcon = false,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final bool showClockIcon;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        if (showClockIcon) ...[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.access_time_rounded,
              size: 16,
              color: Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : scheme.onSurface,
              fontSize: 18,
            ),
          ),
        ),
        if (actionLabel != null && onActionTap != null)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onActionTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFF38BDF8),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class _ToolData {
  const _ToolData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.accent,
    this.gradient,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color accent;
  final List<Color>? gradient;
  final void Function(BuildContext context)? onTap;

  List<Color> get effectiveGradient =>
      gradient ?? [accent, Color.lerp(accent, Colors.white, 0.25)!];
}

List<Color> _historyGradient(String tool) {
  if (tool.contains('Resize')) {
    return const [Color(0xFF4F9CFF), Color(0xFF7BD5FF)];
  }
  if (tool.contains('Collage')) {
    return const [Color(0xFF8B5CFF), Color(0xFFE252FF)];
  }
  if (tool.contains('PDF')) {
    return const [Color(0xFFFF6B5D), Color(0xFFFFA85B)];
  }
  if (tool.contains('Format')) {
    return const [Color(0xFF11B67A), Color(0xFF69D66E)];
  }

  final hue = tool.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % 360;
  final color = HSVColor.fromAHSV(1, hue.toDouble(), 0.65, 0.9).toColor();

  return [color, Color.lerp(color, Colors.white, 0.35)!];
}

class _OperationHistoryRow extends StatelessWidget {
  const _OperationHistoryRow({
    required this.operation,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelected,
    this.selectionMode = false,
    this.thumbnailPath,
  });

  final OperationFolder operation;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;
  final String? thumbnailPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isPdf = operation.kind == OperationKind.imageToPdf ||
        operation.kind == OperationKind.pdfMerge ||
        operation.kind == OperationKind.pdfSplit ||
        operation.kind == OperationKind.pdfCompress ||
        operation.displayName.toLowerCase().endsWith('.pdf');
    final dateLabel = DateFormat('MMM d, yyyy').format(operation.createdAt);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.35)
              : isDark
                  ? const Color(0xFF131D31)
                  : scheme.surfaceContainerLowest,
          border: Border.all(
            color: selected
                ? scheme.secondary
                : isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : scheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            FileThumbnail(
              path: thumbnailPath ?? '',
              isPdf: isPdf,
              size: 48,
              borderRadius: 12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    operation.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : scheme.onSurface,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF64748B)
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${operation.itemCount} ${operation.itemCount == 1 ? 'file' : 'files'}',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Pill badge: Image / PDF
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isPdf
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : const Color(0xFF6366F1).withValues(alpha: 0.15),
              ),
              child: Text(
                isPdf ? 'PDF' : 'Image',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      isPdf ? const Color(0xFFF87171) : const Color(0xFF818CF8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (selectionMode)
              Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelected(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark
                    ? const Color(0xFF64748B)
                    : scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }
}

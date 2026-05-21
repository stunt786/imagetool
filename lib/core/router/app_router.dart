import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/camera/presentation/camera_screen.dart';
import '../../features/collage_builder/presentation/collage_builder_screen.dart';
import '../../features/format_converter/presentation/format_converter_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/images_hub/presentation/images_hub_screen.dart';
import '../../features/image_resize/presentation/image_editor_screen.dart';
import '../../features/image_to_pdf/presentation/image_to_pdf_screen.dart';
import '../../features/pdf_compress/presentation/pdf_compress_screen.dart';
import '../../features/pdfs_hub/presentation/pdfs_hub_screen.dart';
import '../../features/pdf_merge/presentation/pdf_merge_screen.dart';
import '../../features/pdf_split/presentation/pdf_split_screen.dart';
import '../../features/pdf_convert/presentation/pdf_convert_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/tools',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/tools',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/camera',
                builder: (context, state) => const CameraScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/images',
                builder: (context, state) => const ImagesHubScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'resizer',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: ImageEditorScreen()),
                  ),
                  GoRoute(
                    path: 'collage',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: CollageBuilderScreen()),
                  ),
                  GoRoute(
                    path: 'convert',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: FormatConverterScreen()),
                  ),
                  GoRoute(
                    path: 'to-pdf',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: ImageToPdfScreen()),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/pdfs',
                builder: (context, state) => const PdfsHubScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'compress',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: PdfCompressScreen()),
                  ),
                  GoRoute(
                    path: 'merge',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: PdfMergeScreen()),
                  ),
                  GoRoute(
                    path: 'split',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: PdfSplitScreen()),
                  ),
                  GoRoute(
                    path: 'convert',
                    pageBuilder: (context, state) =>
                        const _MaterialPage(child: PdfConvertScreen()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            const _MaterialPage(child: SettingsScreen()),
      ),

      // Backwards-compatible deep links from the earlier scaffold.
      GoRoute(path: '/', redirect: (context, state) => '/tools'),
      GoRoute(
        path: '/image-resizer',
        redirect: (context, state) => '/images/resizer',
      ),
      GoRoute(
        path: '/collage-builder',
        redirect: (context, state) => '/images/collage',
      ),
      GoRoute(
        path: '/format-converter',
        redirect: (context, state) => '/images/convert',
      ),
      GoRoute(
        path: '/pdf-compressor',
        redirect: (context, state) => '/pdfs/compress',
      ),
      GoRoute(path: '/pdf-merger', redirect: (context, state) => '/pdfs/merge'),
      GoRoute(
        path: '/pdf-splitter',
        redirect: (context, state) => '/pdfs/split',
      ),
      GoRoute(
        path: '/pdf-converter',
        redirect: (context, state) => '/pdfs/convert',
      ),
      GoRoute(
        path: '/image-to-pdf',
        redirect: (context, state) => '/images/to-pdf',
      ),
    ],
    errorBuilder: (context, state) {
      return _RouterErrorScreen(error: state.error);
    },
  );
});

class _MaterialPage extends Page<void> {
  const _MaterialPage({required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) {
    return MaterialPageRoute<void>(builder: (context) => child, settings: this);
  }
}

class _RouterErrorScreen extends StatelessWidget {
  const _RouterErrorScreen({required this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error?.toString() ?? 'Unknown routing error'),
      ),
    );
  }
}

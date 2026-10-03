import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/camera/presentation/camera_screen.dart';
import '../../features/camera/presentation/screens/document_review_screen.dart';
import '../../features/camera/presentation/screens/document_filter_screen.dart';
import '../../features/camera/presentation/screens/magic_remove_screen.dart';
import '../../features/camera/presentation/screens/perspective_correction_screen.dart';
import '../../features/collage_builder/presentation/collage_builder_screen.dart';
import '../../features/format_converter/presentation/format_converter_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/image_resize/presentation/image_resize_screen.dart';
import '../../features/image_to_pdf/presentation/image_to_pdf_screen.dart';
import '../../features/pdf_compress/presentation/pdf_compress_screen.dart';
import '../../features/files/presentation/files_screen.dart';
import '../../features/files/presentation/history_screen.dart';
import '../../features/pdf_merge/presentation/pdf_merge_screen.dart';
import '../../features/pdf_split/presentation/pdf_split_screen.dart';
import '../../features/pdf_viewer/presentation/pdf_viewer_screen.dart';
import '../../features/pdf_convert/presentation/pdf_convert_screen.dart';
// import '../../features/premium/presentation/premium_screen.dart'; // TODO: Re-enable in upcoming version with premium features
import '../../features/settings/presentation/about_screen.dart';
import '../../features/settings/presentation/privacy_policy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../services/app_review_service.dart';
import '../settings/app_settings.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');
  AppReviewService.instance.rootNavigatorKey = rootNavigatorKey;
  final refreshNotifier = ValueNotifier<int>(0);

  // Re-evaluate GoRouter redirects when settings finish loading
  ref.listen(appSettingsProvider, (previous, next) {
    refreshNotifier.value++;
  });

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/tools',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      if (state.matchedLocation == '/onboarding') {
        return '/tools';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        redirect: (context, state) => '/tools',
      ),
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
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const SettingsScreen()),
              ),
              GoRoute(
                path: '/settings/privacy',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const PrivacyPolicyScreen()),
              ),
              GoRoute(
                path: '/settings/about',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const AboutScreen()),
              ),
              GoRoute(
                path: '/images/resizer',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const ImageResizeScreen()),
              ),
              GoRoute(
                path: '/images/collage',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const CollageBuilderScreen()),
              ),
              GoRoute(
                path: '/images/convert',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const FormatConverterScreen()),
              ),
              GoRoute(
                path: '/images/to-pdf',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const ImageToPdfScreen()),
              ),
              // PDF tools located in Branch 0 for seamless push/swap-back to HomeScreen
              GoRoute(
                path: '/pdfs/compress',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const PdfCompressScreen()),
              ),
              GoRoute(
                path: '/pdfs/merge',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const PdfMergeScreen()),
              ),
              GoRoute(
                path: '/pdfs/split',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const PdfSplitScreen()),
              ),
              GoRoute(
                path: '/pdfs/convert',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const PdfConvertScreen()),
              ),
              GoRoute(
                path: '/history',
                pageBuilder: (context, state) =>
                    _MaterialPage(key: state.pageKey, child: const HistoryScreen()),
              ),
              // In-app PDF viewer. The file is passed through `extra` so any screen can
              // deep-link into it without a second lookup.
              GoRoute(
                path: '/pdf/viewer',
                pageBuilder: (context, state) {
                  final extra = state.extra;
                  final args = extra is Map ? extra : const <String, dynamic>{};
                  return _MaterialPage(
                    key: state.pageKey,
                    child: PdfViewerScreen(
                      filePath: args['path'] as String? ?? '',
                      title: args['title'] as String?,
                      initialPage: (args['page'] as num?)?.toInt() ?? 1,
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/camera',
                builder: (context, state) => const CameraScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'review',
                    pageBuilder: (context, state) =>
                        _MaterialPage(key: state.pageKey, child: const DocumentReviewScreen()),
                  ),
                  GoRoute(
                    path: 'filter',
                    pageBuilder: (context, state) =>
                        _MaterialPage(key: state.pageKey, child: const DocumentFilterScreen()),
                  ),
                  GoRoute(
                    path: 'crop',
                    pageBuilder: (context, state) => _MaterialPage(
                        key: state.pageKey,
                        child: const PerspectiveCorrectionScreen()),
                  ),
                  GoRoute(
                    path: 'perspective',
                    pageBuilder: (context, state) => _MaterialPage(
                        key: state.pageKey,
                        child: const PerspectiveCorrectionScreen()),
                  ),
                  GoRoute(
                    path: 'magic-remove',
                    pageBuilder: (context, state) => _MaterialPage(
                      key: state.pageKey,
                      child: MagicRemoveScreen(
                        imageBytes: (state.extra is Uint8List
                                ? state.extra as Uint8List
                                : null) ??
                            Uint8List(0),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/pdfs',
                builder: (context, state) => const FilesScreen(),
              ),
            ],
          ),
        ],
      ),

      // TODO: Re-enable premium route in upcoming version with premium features
      // GoRoute(
      //   path: '/premium',
      //   parentNavigatorKey: rootNavigatorKey,
      //   pageBuilder: (context, state) =>
      //       const _MaterialPage(child: PremiumScreen()),
      // ),

      // Backwards-compatible deep links from the earlier scaffold.
      GoRoute(
        path: '/',
        redirect: (context, state) => '/tools',
      ),
      GoRoute(path: '/home', redirect: (context, state) => '/tools'),
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
  const _MaterialPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) {
    return CupertinoPageRoute<void>(builder: (context) => child, settings: this);
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

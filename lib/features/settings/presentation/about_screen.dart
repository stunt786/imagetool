import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/app_review_service.dart';
import '../../../core/services/app_update_service.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String developerAboutUsText =
      'At bnbKio, we are passionate about leveraging technology to solve complex business challenges. Our team of skilled developers, designers, and strategists works collaboratively to deliver innovative solutions that drive growth and create lasting value. We believe in the power of technology to transform businesses and improve lives. Our client-centric approach ensures that we understand your unique needs and deliver tailored solutions that exceed expectations. Main Areas, Mobile App development, web development, cloud services, UI/UX design, AI & Machine Learning, etc...';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // ── App Information Header ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/icons/icon.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: scheme.primary,
                        child: const Icon(Icons.image_outlined, color: Colors.white, size: 36),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppStrings.appName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Image & PDF Editor • Version 1.0.0',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A privacy-first, 100% offline toolkit for converting, resizing, merging, splitting, and scanning images and PDFs without third-party tracking.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.system_update_rounded, size: 18),
                        label: const Text('Check for Updates'),
                        onPressed: () => _handleCheckForUpdates(context),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Share App'),
                        onPressed: () => AppReviewService.instance.shareApp(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Developer Information Section ────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.business_rounded, color: scheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Developer Information',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'About Us • bnbKio',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    developerAboutUsText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Main Areas:',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _AreaChip(label: 'Mobile App Development', icon: Icons.phone_android_rounded),
                      _AreaChip(label: 'Web Development', icon: Icons.language_rounded),
                      _AreaChip(label: 'Cloud Services', icon: Icons.cloud_outlined),
                      _AreaChip(label: 'UI/UX Design', icon: Icons.palette_outlined),
                      _AreaChip(label: 'AI & Machine Learning', icon: Icons.smart_toy_outlined),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Quick Links ──────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('Read our full offline privacy commitment'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/privacy'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.star_rate_rounded, color: Colors.amber),
                    title: const Text('Rate on Google Play'),
                    subtitle: const Text('Support the development of PixelTools'),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => AppReviewService.instance.openPlayStore(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            Center(
              child: Text(
                '© 2026 bnbKio. All rights reserved.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCheckForUpdates(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
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
}

class _AreaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _AreaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

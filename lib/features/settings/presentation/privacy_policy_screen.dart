import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Privacy Highlight Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.12),
                    scheme.secondary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '100% Offline & Privacy-First',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${AppStrings.appName} operates entirely on your device. We do not collect, transmit, profile, or sell your documents, images, or personal data.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildSection(
              context,
              icon: Icons.lock_outline_rounded,
              title: '1. On-Device Local Processing',
              body:
                  'Every operation provided by ${AppStrings.appName}—including image resizing, format conversion, PDF creation, compression, merging, splitting, and collage building—is performed entirely on your device. None of your files or edit outputs are uploaded to remote servers or cloud storage.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.smart_toy_outlined,
              title: '2. On-Device Machine Learning (ML Kit)',
              body:
                  'Document edge detection, perspective correction, and text recognition (OCR) features run solely via on-device Google ML Kit models. Image data and recognized text never leave your smartphone and are processed solely in temporary volatile device memory.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.security_rounded,
              title: '3. Device Permissions & Usage',
              body:
                  '• Camera: Required only when you actively use the "Scan Docs" or photo capture tool to photograph physical documents. The camera stream is never recorded in the background.\n\n'
                  '• Storage & Media Access: Used exclusively to load images or PDFs you select and to save your resulting files into your chosen device directory (e.g. Pictures or Downloads). ${AppStrings.appName} never scans or reads unrelated files on your storage.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.do_not_disturb_on_outlined,
              title: '4. No Analytics or Tracking',
              body:
                  'We respect your digital privacy. ${AppStrings.appName} does NOT integrate third-party ad networks, telemetry trackers, analytics suites, or user behavior tracking libraries. We do not gather or store device identifiers, advertising IDs, or location data.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.open_in_new_rounded,
              title: '5. External Links',
              body:
                  'If you choose to rate the app or check for updates, you will be directed to Google Play Store using your system browser or the official Play Store app. These external platforms are governed by Google\'s privacy policies.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.business_rounded,
              title: '6. Developer & Contact',
              body:
                  '${AppStrings.appName} is developed and maintained by bnbKio. If you have questions regarding this privacy policy or suggestions for the application, please contact our support team at bnbKio.',
            ),
            const SizedBox(height: 36),

            Center(
              child: Text(
                'Last updated: October 2026 • Developed by bnbKio',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

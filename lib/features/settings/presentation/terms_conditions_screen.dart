import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Terms Highlight Card
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
                      Icons.gavel_rounded,
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
                          'Simple & Fair Terms',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${AppStrings.appName} is a 100% offline toolkit. These terms describe how you may use the app and what you can expect from us—nothing more, nothing less.',
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
              icon: Icons.check_circle_outline_rounded,
              title: '1. Acceptance of Terms',
              body:
                  'By downloading, installing, or using ${AppStrings.appName}, you agree to be bound by these Terms & Conditions and our Privacy Policy. If you do not agree with any part of these terms, please discontinue use of the application.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.phone_android_rounded,
              title: '2. License to Use',
              body:
                  '${AppStrings.appName} is licensed, not sold, to you for personal and commercial document workflows on your own device. You may use the app to process your own files and outputs. You may not reverse-engineer, redistribute, resell, or rebrand the application without prior written permission from the developer.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.folder_copy_outlined,
              title: '3. Your Files & Responsibilities',
              body:
                  'All images and PDFs you process remain yours. You are solely responsible for the content you import and for the outputs you create. Since ${AppStrings.appName} runs entirely on-device, files are never uploaded anywhere—please keep your own backups, as deleted files cannot be recovered by us.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.copyright_rounded,
              title: '4. Intellectual Property',
              body:
                  'The ${AppStrings.appName} name, icon, user interface, and source code are the intellectual property of bnbKio. Third-party open-source packages remain under their respective licenses. Any feedback you send may be used to improve the app without obligation to you.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.open_in_new_rounded,
              title: '5. External Services',
              body:
                  'Optional actions such as checking for updates or rating the app open Google Play or your system browser. Those external platforms are governed by their own terms of service. ${AppStrings.appName} itself works fully offline and requires no account.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.warning_amber_rounded,
              title: '6. Disclaimer & Liability',
              body:
                  'The app is provided "as is" without warranties of any kind. To the maximum extent permitted by law, bnbKio is not liable for any indirect or incidental damages arising from the use of the app, including loss of data or files. Always verify important outputs before relying on them.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.refresh_rounded,
              title: '7. Changes to These Terms',
              body:
                  'These terms may be updated in future releases of the app. Continued use of ${AppStrings.appName} after an update constitutes acceptance of the revised terms. The "Last updated" date below reflects the latest revision.',
            ),
            const SizedBox(height: 20),

            _buildSection(
              context,
              icon: Icons.business_rounded,
              title: '8. Developer & Contact',
              body:
                  '${AppStrings.appName} is developed and maintained by bnbKio. If you have questions about these terms or suggestions for the application, please contact our support team at bnbKio.',
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

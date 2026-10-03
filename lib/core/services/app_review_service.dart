import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_strings.dart';

/// Manages app rating, Play Store redirection, sharing, and recurring prompts.
class AppReviewService {
  AppReviewService._();

  static final AppReviewService instance = AppReviewService._();

  static const String _keyHasRated = 'app_review_has_rated';
  static const String _keyLastPrompt = 'app_review_last_prompt_ms';
  static const String _keyOperationCount = 'app_review_operation_count';

  /// Launches the Play Store page to rate the app.
  Future<bool> openPlayStore() async {
    final marketUri = Uri.parse(AppStrings.playStoreMarketUri);
    final webUri = Uri.parse(AppStrings.playStoreUrl);

    try {
      if (Platform.isAndroid && await canLaunchUrl(marketUri)) {
        return await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    try {
      if (await canLaunchUrl(webUri)) {
        return await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    return false;
  }

  /// Opens the system share sheet with the app's Play Store link.
  Future<void> shareApp({Rect? sharePositionOrigin}) async {
    const text = 'Check out ${AppStrings.appName}: Image & PDF Editor on Google Play:\n'
        '${AppStrings.playStoreUrl}';
    await Share.share(
      text,
      subject: 'Download ${AppStrings.appName}',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Sets that the user has rated the app, preventing any future popup prompts.
  Future<void> markAsRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasRated, true);
  }

  /// Checks whether the user has already rated the app.
  Future<bool> hasRated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasRated) ?? false;
  }

  /// Whether review prompts should be shown in flutter test environment.
  bool enableInTest = false;

  /// Records an operation completion and displays the rating dialog if eligible:
  /// 1. The user has not rated yet.
  /// 2. At least 1 operation has been completed.
  /// 3. At least 2 days (48 hours) have passed since the previous prompt (or it's the first time).
  Future<void> notifyOperationCompleted(BuildContext context) async {
    if (Platform.environment.containsKey('FLUTTER_TEST') && !enableInTest) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final alreadyRated = prefs.getBool(_keyHasRated) ?? false;
    if (alreadyRated) return;

    final currentCount = (prefs.getInt(_keyOperationCount) ?? 0) + 1;
    await prefs.setInt(_keyOperationCount, currentCount);

    final lastPromptMs = prefs.getInt(_keyLastPrompt);
    final now = DateTime.now();

    var shouldPrompt = false;
    if (lastPromptMs == null) {
      // First operation completed: show after 1 operation
      if (currentCount >= 1) {
        shouldPrompt = true;
      }
    } else {
      // Recurring interval: every 2 days
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastPromptMs);
      if (now.difference(lastPrompt).inHours >= 48) {
        shouldPrompt = true;
      }
    }

    if (!shouldPrompt || !context.mounted) return;

    // Delay slightly so save snackbars/transitions finish cleanly
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;

    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.mounted) return;

    final route = ModalRoute.of(context);
    if (route != null && !route.isActive) return;

    await prefs.setInt(_keyLastPrompt, now.millisecondsSinceEpoch);
    if (!context.mounted) return;
    await showRatingDialog(context);
  }

  /// Shows the "Rate this app" dialog.
  Future<void> showRatingDialog(BuildContext context) async {
    if (!context.mounted) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.mounted) return;

    final route = ModalRoute.of(context);
    if (route != null && !route.isActive) return;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.star_rounded,
              color: scheme.onPrimaryContainer,
              size: 32,
            ),
          ),
          title: Text(
            'Enjoying ${AppStrings.appName}?',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'If you enjoy using ${AppStrings.appName}, please take a moment to rate us on Google Play. Your feedback helps us keep improving!',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => const Icon(
                    Icons.star_rounded,
                    color: Colors.amber,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowButtonSpacing: 8.0,
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            TextButton(
              onPressed: () {
                if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(
                'Remind Later',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
                await markAsRated();
                await openPlayStore();
              },
              icon: const Icon(Icons.thumb_up_alt_rounded, size: 16),
              label: const Text('Rate Now'),
            ),
          ],
        );
      },
    );
  }
}

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

  /// Optional root navigator key to fallback to if the calling context is unmounted
  GlobalKey<NavigatorState>? rootNavigatorKey;

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
  /// 2. If it's the first time: prompts after 1st operation.
  /// 3. If previously prompted: prompts on the first operation of a new calendar day.
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
      // Recurring interval: first operation of each new day
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastPromptMs);
      final isDifferentDay = lastPrompt.year != now.year ||
          lastPrompt.month != now.month ||
          lastPrompt.day != now.day;
      if (isDifferentDay) {
        shouldPrompt = true;
      }
    }

    if (!shouldPrompt) return;

    // Delay slightly so save snackbars/transitions finish cleanly
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final navContext = rootNavigatorKey?.currentContext;
    final BuildContext? targetContext;
    if (context.mounted) {
      targetContext = context;
    } else if (navContext != null && navContext.mounted) {
      targetContext = navContext;
    } else {
      targetContext = null;
    }
    if (targetContext == null) return;

    // ignore: use_build_context_synchronously
    final navigator = Navigator.maybeOf(targetContext);
    if (navigator == null || !navigator.mounted) return;

    // ignore: use_build_context_synchronously
    final route = ModalRoute.of(targetContext);
    if (route != null && !route.isActive) return;

    await prefs.setInt(_keyLastPrompt, now.millisecondsSinceEpoch);
    if (!targetContext.mounted) return;
    // ignore: use_build_context_synchronously
    await showRatingDialog(targetContext);
  }

  /// Shows the "Rate this app" dialog with interactive stars.
  Future<void> showRatingDialog(BuildContext context) async {
    if (!context.mounted) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.mounted) return;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    int selectedStars = 5;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final ratingLabels = [
                'Needs improvement',
                'Could be better',
                'Good',
                'Very good!',
                'Loved it!',
              ];
              final currentLabel = ratingLabels[(selectedStars - 1).clamp(0, 4)];

              return AlertDialog(
                scrollable: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                icon: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFB800), Color(0xFFF59E0B)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                title: Text(
                  'Enjoying ${AppStrings.appName}?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'If you enjoy using ${AppStrings.appName}, please take a moment to rate us on Google Play. Your feedback helps us keep improving!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final starValue = index + 1;
                          final isSelected = starValue <= selectedStars;
                          return IconButton(
                            iconSize: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              isSelected
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: isSelected ? const Color(0xFFFFB800) : scheme.outlineVariant,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                selectedStars = starValue;
                              });
                            },
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        currentLabel,
                        key: ValueKey(selectedStars),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: scheme.primary,
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
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Rate Later',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
                        Navigator.of(dialogContext).pop();
                      }
                      await markAsRated();
                      final launched = await openPlayStore();
                      if (!launched && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you for your rating and feedback!'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.star_rate_rounded, size: 18),
                    label: const Text('Rate Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

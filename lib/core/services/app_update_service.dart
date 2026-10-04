import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_strings.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final List<String> releaseNotes;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes = const [],
  });

  factory AppUpdateInfo.upToDate({String? currentVersion}) {
    final ver = currentVersion ?? AppUpdateService.currentAppVersion;
    return AppUpdateInfo(
      hasUpdate: false,
      currentVersion: ver,
      latestVersion: ver,
      downloadUrl: AppStrings.playStoreUrl,
    );
  }
}

/// Service handling in-app update checks, auto-check postponed intervals (2 days),
/// update dialog prompts, and store redirections.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String keyPostponedTime = 'app_update_postponed_time_ms';
  static const Duration postponeDuration = Duration(days: 2);
  static String currentAppVersion = '1.0.1';
  static String currentBuildNumber = '2';

  /// Optional remote manifest URL if hosting an update JSON manifest.
  String? remoteManifestUrl;

  /// Custom checker for testing or custom backend integration.
  Future<AppUpdateInfo> Function()? customUpdateChecker;

  /// Compares semantic versions (e.g., '1.1.0' > '1.0.0').
  static bool isNewerVersion(String latest, String current) {
    try {
      final latestClean = latest.split('+').first.trim();
      final currentClean = current.split('+').first.trim();

      final latestParts = latestClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = currentClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
      while (latestParts.length < maxLen) {
        latestParts.add(0);
      }
      while (currentParts.length < maxLen) {
        currentParts.add(0);
      }

      for (var i = 0; i < maxLen; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if the auto-update check should run based on the 2-day deferral rule.
  Future<bool> shouldCheckAutoUpdate({SharedPreferences? testPrefs}) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final postponedMs = prefs.getInt(keyPostponedTime);
    if (postponedMs == null) return true;

    final postponedDate = DateTime.fromMillisecondsSinceEpoch(postponedMs);
    final elapsed = DateTime.now().difference(postponedDate);
    return elapsed >= postponeDuration;
  }

  /// Postpones update notification for 2 days.
  Future<void> postponeUpdate({SharedPreferences? testPrefs}) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(keyPostponedTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// Clears postponement record so update checks immediately.
  Future<void> clearPostponedUpdate({SharedPreferences? testPrefs}) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    await prefs.remove(keyPostponedTime);
  }

  /// Checks if a newer version of the application is available.
  Future<AppUpdateInfo> checkForUpdate({bool force = false}) async {
    if (customUpdateChecker != null) {
      return await customUpdateChecker!();
    }

    // If remote manifest URL is configured, fetch JSON:
    if (remoteManifestUrl != null && remoteManifestUrl!.isNotEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 6);
        final request = await client.getUrl(Uri.parse(remoteManifestUrl!));
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final map = jsonDecode(body) as Map<String, dynamic>;
          final latestVer = (map['latest_version'] ?? map['version'] ?? currentAppVersion).toString();
          final dlUrl = (map['download_url'] ?? AppStrings.playStoreUrl).toString();
          final rawNotes = map['release_notes'];
          final notes = <String>[];
          if (rawNotes is List) {
            notes.addAll(rawNotes.map((e) => e.toString()));
          }

          final hasUpdate = isNewerVersion(latestVer, currentAppVersion);
          return AppUpdateInfo(
            hasUpdate: hasUpdate,
            currentVersion: currentAppVersion,
            latestVersion: latestVer,
            downloadUrl: dlUrl,
            releaseNotes: notes,
          );
        }
      } catch (_) {}
    }

    // Default return: current version is up to date
    return AppUpdateInfo.upToDate(currentVersion: currentAppVersion);
  }

  /// Launches Play Store or browser URL to download the update.
  Future<bool> startUpdate({String? downloadUrl}) async {
    final target = downloadUrl ?? AppStrings.playStoreUrl;
    final marketUri = Uri.parse(AppStrings.playStoreMarketUri);
    final webUri = Uri.parse(target);

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

  /// Shows the update popup dialog offering "Update Now" and "Update Later".
  Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info, {
    bool isAutoCheck = false,
  }) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isAutoCheck,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.system_update_rounded, color: scheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update Available',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Version ${info.latestVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version of ${AppStrings.appName} is ready to download. '
                'Update now to enjoy the latest performance improvements, standard A4 PDF tools, and bug fixes.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  "What's New:",
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                for (final note in info.releaseNotes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(
                            note,
                            style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await postponeUpdate();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Update Later'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Update Now'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                startUpdate(downloadUrl: info.downloadUrl);
              },
            ),
          ],
        );
      },
    );
  }

  /// Automatically checks for updates on launch. If available and not postponed within 2 days,
  /// immediately displays the update popup.
  Future<void> checkAndPromptAutoUpdate(BuildContext context) async {
    final shouldCheck = await shouldCheckAutoUpdate();
    if (!shouldCheck) return;

    final info = await checkForUpdate();
    if (info.hasUpdate && context.mounted) {
      await showUpdateDialog(context, info, isAutoCheck: true);
    }
  }
}

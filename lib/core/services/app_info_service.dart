import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_strings.dart';
import 'app_update_service.dart';

class AppInfo {
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  const AppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  /// Formatted version with build number, e.g. "1.0.1+2" (or "1.0.1" if no build number)
  String get versionWithBuild =>
      buildNumber.isNotEmpty ? '$version+$buildNumber' : version;

  /// User-friendly version, e.g. "1.0.1 (2)"
  String get displayVersion =>
      buildNumber.isNotEmpty ? '$version ($buildNumber)' : version;

  /// Formatted with leading "v", e.g. "v1.0.1+2"
  String get fullVersionString => 'v$versionWithBuild';
}

final appInfoProvider = FutureProvider<AppInfo>((ref) async {
  return AppInfoService.instance.getAppInfo();
});

class AppInfoService {
  AppInfoService._();
  static final AppInfoService instance = AppInfoService._();

  static const String fallbackVersion = '1.0.1';
  static const String fallbackBuildNumber = '2';

  AppInfo? _cachedInfo;

  AppInfo get cachedInfo =>
      _cachedInfo ??
      const AppInfo(
        appName: AppStrings.appName,
        packageName: 'com.bnbkio.pixeltools',
        version: fallbackVersion,
        buildNumber: fallbackBuildNumber,
      );

  Future<AppInfo> getAppInfo() async {
    if (_cachedInfo != null) return _cachedInfo!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedInfo = AppInfo(
        appName: info.appName.isNotEmpty ? info.appName : AppStrings.appName,
        packageName: info.packageName.isNotEmpty
            ? info.packageName
            : 'com.bnbkio.pixeltools',
        version: info.version.isNotEmpty ? info.version : fallbackVersion,
        buildNumber:
            info.buildNumber.isNotEmpty ? info.buildNumber : fallbackBuildNumber,
      );
      AppUpdateService.currentAppVersion = _cachedInfo!.version;
      AppUpdateService.currentBuildNumber = _cachedInfo!.buildNumber;
    } catch (_) {
      _cachedInfo = const AppInfo(
        appName: AppStrings.appName,
        packageName: 'com.bnbkio.pixeltools',
        version: fallbackVersion,
        buildNumber: fallbackBuildNumber,
      );
      AppUpdateService.currentAppVersion = fallbackVersion;
      AppUpdateService.currentBuildNumber = fallbackBuildNumber;
    }
    return _cachedInfo!;
  }
}

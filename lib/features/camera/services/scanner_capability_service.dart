import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Decides whether the Google ML Kit document scanner can be used *before* the
/// scanner UI is opened, so unsupported devices go straight to the built-in
/// camera instead of opening a scanner that cannot work.
abstract class ScannerCapabilityService {
  Future<bool> isGoogleDocumentScannerAvailable();
}

/// Provider so screens and tests can swap the implementation.
final scannerCapabilityProvider = Provider<ScannerCapabilityService>((ref) {
  return MlKitScannerCapability();
});

/// ML Kit implementation.
///
/// The plugin does not expose a Play-services availability query, so the check
/// is deliberately honest about what it can know:
///
///  * the ML Kit document scanner is an Android-only component, so every other
///    platform reports `false`;
///  * on Android the first launch is optimistic (the scanner is part of the
///    normal Play-services install base) and a failed launch demotes the
///    capability for the rest of the session, which routes the user to the
///    built-in camera without any further failed attempts.
class MlKitScannerCapability implements ScannerCapabilityService {
  MlKitScannerCapability({Future<bool> Function()? probe})
      : _probe = probe ?? _defaultProbe;

  final Future<bool> Function() _probe;

  static bool? _sessionResult;

  @override
  Future<bool> isGoogleDocumentScannerAvailable() async {
    final cached = _sessionResult;
    if (cached != null) return cached;
    bool result;
    try {
      result = await _probe();
    } catch (_) {
      result = false;
    }
    _sessionResult = result;
    return result;
  }

  /// Called when a launch failed even though the capability said "available".
  static void markUnavailable() {
    _sessionResult = false;
  }

  /// Clears the session cache (used by tests).
  @visibleForTesting
  static void resetCache() {
    _sessionResult = null;
  }

  static Future<bool> _defaultProbe() async {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ad_service.dart';

/// Tracks user interactions across the app and automatically shows an
/// interstitial ad every 3–5 events (randomized for a natural feel).
///
/// Two helper methods are provided so call sites are self-documenting:
///  - [trackNavigation] — call before every route push to a tool screen.
///  - [trackAction]     — call after meaningful in-tool actions (pick, save,
///                        convert, etc.).
///
/// Both increment the same shared counter, so any combination of navigations
/// and actions triggers the ad threshold at 3–5 interactions.
class InterstitialTracker {
  InterstitialTracker._();

  static final InterstitialTracker instance = InterstitialTracker._();

  int _actionCount = 0;
  int _nextAdAt = _randomInterval();

  /// Records a navigation event (route push to a tool screen) and shows an
  /// interstitial ad when the 3–5 navigation threshold is reached.
  /// Returns true if an ad was shown.
  bool trackNavigation() => trackAction();

  /// Records a user action and shows an interstitial ad when the threshold
  /// is reached. Returns true if an ad was shown.
  bool trackAction() {
    _actionCount++;

    if (_actionCount >= _nextAdAt) {
      debugPrint(
        '[InterstitialTracker] Event $_actionCount reached threshold '
        '$_nextAdAt — showing interstitial',
      );
      _reset();
      AdService.instance.showInterstitialAd();
      return true;
    }

    debugPrint(
      '[InterstitialTracker] Event $_actionCount (next ad at $_nextAdAt)',
    );
    return false;
  }

  /// Resets the counter. Useful when navigating away from a tool screen
  /// so the count doesn't carry over unexpectedly.
  void reset() {
    _actionCount = 0;
    _nextAdAt = _randomInterval();
    debugPrint('[InterstitialTracker] Counter reset');
  }

  void _reset() {
    _actionCount = 0;
    _nextAdAt = _randomInterval();
  }

  /// Returns a random interval between 3 and 5 (inclusive).
  static int _randomInterval() {
    return Random().nextInt(3) + 3;
  }
}

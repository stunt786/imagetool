import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Centralized AdMob service managing Banner, Interstitial, and Rewarded ads.
///
/// Uses official Google TEST ad unit IDs by default.
/// Replace [isTestMode] = false and update IDs for production.
///
/// Per the official guide:
/// https://developers.google.com/admob/flutter/test-ads
/// Android and iOS use DIFFERENT test ad unit IDs.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  /// Set to false and replace test IDs with production IDs before release.
  static const bool isTestMode = true;

  // ---------------------------------------------------------------------------
  // Test Ad Unit IDs — official Google demo units (platform-specific)
  // https://developers.google.com/admob/android/test-ads#demo_ad_units
  // https://developers.google.com/admob/ios/test-ads#demo_ad_units
  // ---------------------------------------------------------------------------

  // Android test ad unit IDs
  static const String _testBannerAdUnitIdAndroid =
      'ca-app-pub-3940256099942544/9214589741';
  static const String _testInterstitialAdUnitIdAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewardedAdUnitIdAndroid =
      'ca-app-pub-3940256099942544/5224354917';

  // iOS test ad unit IDs
  static const String _testBannerAdUnitIdIOS =
      'ca-app-pub-3940256099942544/2435281174';
  static const String _testInterstitialAdUnitIdIOS =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testRewardedAdUnitIdIOS =
      'ca-app-pub-3940256099942544/1712485313';

  // ---------------------------------------------------------------------------
  // Production Ad Unit IDs — REPLACE THESE before releasing to production
  // ---------------------------------------------------------------------------
  static const String _prodBannerAdUnitId = 'YOUR_BANNER_AD_UNIT_ID';
  static const String _prodInterstitialAdUnitId =
      'YOUR_INTERSTITIAL_AD_UNIT_ID';
  static const String _prodRewardedAdUnitId = 'YOUR_REWARDED_AD_UNIT_ID';

  // ---------------------------------------------------------------------------
  // Resolved ad unit IDs (test vs production, platform-aware)
  // ---------------------------------------------------------------------------
  static String get bannerAdUnitId {
    if (kIsWeb) return ''; // Ads not supported on web
    if (isTestMode) {
      return Platform.isAndroid
          ? _testBannerAdUnitIdAndroid
          : _testBannerAdUnitIdIOS;
    }
    return _prodBannerAdUnitId;
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (isTestMode) {
      return Platform.isAndroid
          ? _testInterstitialAdUnitIdAndroid
          : _testInterstitialAdUnitIdIOS;
    }
    return _prodInterstitialAdUnitId;
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return '';
    if (isTestMode) {
      return Platform.isAndroid
          ? _testRewardedAdUnitIdAndroid
          : _testRewardedAdUnitIdIOS;
    }
    return _prodRewardedAdUnitId;
  }

  // ---------------------------------------------------------------------------
  // Interstitial Ad state
  // ---------------------------------------------------------------------------
  InterstitialAd? _interstitialAd;
  int _interstitialRetryCount = 0;
  static const int _maxInterstitialRetries = 3;

  // ---------------------------------------------------------------------------
  // Rewarded Ad state
  // ---------------------------------------------------------------------------
  RewardedAd? _rewardedAd;
  int _rewardedRetryCount = 0;
  static const int _maxRewardedRetries = 3;

  // ---------------------------------------------------------------------------
  // Initialize the Mobile Ads SDK
  // ---------------------------------------------------------------------------

  /// Initializes the Google Mobile Ads SDK.
  /// Call this once at app startup before loading any ads.
  ///
  /// Optionally pass [testDeviceIds] to enable test mode on physical devices
  /// when using production ad unit IDs.
  /// See: https://developers.google.com/admob/flutter/test-ads#enable_test_devices
  Future<void> initialize({List<String>? testDeviceIds}) async {
    // google_mobile_ads is not supported on web.
    if (kIsWeb) {
      debugPrint('[AdService] Skipping AdMob init on web');
      return;
    }

    await MobileAds.instance.initialize();
    debugPrint('[AdService] MobileAds SDK initialized');

    // Configure test devices if provided (for production ad unit testing)
    if (testDeviceIds != null && testDeviceIds.isNotEmpty) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: testDeviceIds),
      );
      debugPrint('[AdService] Test device IDs configured: $testDeviceIds');
    }

    // Pre-load full-screen ads so they are ready when needed
    loadInterstitialAd();
    loadRewardedAd();
  }

  // ===========================================================================
  // Interstitial Ad
  // ===========================================================================

  /// Loads an interstitial ad. Automatically retries on failure (up to max).
  void loadInterstitialAd() {
    if (kIsWeb) return;
    debugPrint('[AdService] Loading interstitial ad…');
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdService] Interstitial ad loaded successfully');
          _interstitialAd = ad;
          _interstitialRetryCount = 0;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('[AdService] Interstitial dismissed');
              ad.dispose();
              _interstitialAd = null;
              // Reload for next time
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdService] Interstitial failed to show: $error');
              ad.dispose();
              _interstitialAd = null;
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdService] Interstitial failed to load: $error');
          _interstitialRetryCount++;
          if (_interstitialRetryCount < _maxInterstitialRetries) {
            debugPrint(
              '[AdService] Retrying interstitial load '
              '($_interstitialRetryCount/$_maxInterstitialRetries)',
            );
            loadInterstitialAd();
          }
        },
      ),
    );
  }

  /// Shows the pre-loaded interstitial ad if available.
  /// Returns true if the ad was shown, false otherwise.
  bool showInterstitialAd() {
    if (kIsWeb) return false;
    if (_interstitialAd != null) {
      debugPrint('[AdService] Showing interstitial ad');
      _interstitialAd!.show();
      return true;
    }
    debugPrint('[AdService] No interstitial ad ready — loading one now');
    loadInterstitialAd();
    return false;
  }

  /// Disposes the current interstitial ad.
  void disposeInterstitial() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }

  // ===========================================================================
  // Rewarded Ad
  // ===========================================================================

  /// Loads a rewarded ad. Automatically retries on failure (up to max).
  void loadRewardedAd() {
    if (kIsWeb) return;
    debugPrint('[AdService] Loading rewarded ad…');
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdService] Rewarded ad loaded successfully');
          _rewardedAd = ad;
          _rewardedRetryCount = 0;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('[AdService] Rewarded dismissed');
              ad.dispose();
              _rewardedAd = null;
              // Reload for next time
              loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdService] Rewarded failed to show: $error');
              ad.dispose();
              _rewardedAd = null;
              loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdService] Rewarded failed to load: $error');
          _rewardedRetryCount++;
          if (_rewardedRetryCount < _maxRewardedRetries) {
            debugPrint(
              '[AdService] Retrying rewarded load '
              '($_rewardedRetryCount/$_maxRewardedRetries)',
            );
            loadRewardedAd();
          }
        },
      ),
    );
  }

  /// Shows the pre-loaded rewarded ad if available.
  /// [onUserEarnedReward] is called when the user earns the reward.
  /// Returns true if the ad was shown, false otherwise.
  bool showRewardedAd({void Function()? onUserEarnedReward}) {
    if (kIsWeb) return false;
    if (_rewardedAd != null) {
      debugPrint('[AdService] Showing rewarded ad');
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          debugPrint(
            '[AdService] User earned reward: ${reward.amount} ${reward.type}',
          );
          onUserEarnedReward?.call();
        },
      );
      return true;
    }
    debugPrint('[AdService] No rewarded ad ready — loading one now');
    loadRewardedAd();
    return false;
  }

  /// Disposes the current rewarded ad.
  void disposeRewarded() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }

  // ===========================================================================
  // Cleanup
  // ===========================================================================

  /// Disposes all loaded ads. Call when the app is shutting down.
  void disposeAll() {
    disposeInterstitial();
    disposeRewarded();
    debugPrint('[AdService] All ads disposed');
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/services/ad_service.dart';

/// A reusable widget that displays an adaptive-size banner ad pinned to the
/// bottom of the screen.
///
/// Fix summary (v2):
/// • `_loadAd()` is now called from a post-frame callback so that
///   `MediaQuery` is fully available before we ask for an adaptive size.
/// • Falls back to the standard `AdSize.banner` (320 × 50) when the
///   adaptive-size API returns null (common on first frame / web stub).
/// • Skips loading entirely on web since `google_mobile_ads` is mobile-only.
/// • Auto-reloads on failure with a 5-second back-off.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so MediaQuery is fully wired up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAd());
  }

  Future<void> _loadAd() async {
    // google_mobile_ads does not support web.
    if (kIsWeb) return;
    if (!mounted) return;
    if (_loadStarted) return;
    _loadStarted = true;

    // Attempt to get an adaptive banner size that fills the screen width.
    final double screenWidth = MediaQuery.of(context).size.width;

    AdSize adSize;
    try {
      final AnchoredAdaptiveBannerAdSize? adaptiveSize =
          await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        screenWidth.truncate(),
      );
      // Use adaptive size if available, otherwise fall back to standard banner.
      adSize = adaptiveSize ?? AdSize.banner;
      debugPrint(
        '[BannerAdWidget] Using ad size: ${adSize.width}×${adSize.height}',
      );
    } catch (_) {
      // Fallback for any platform-level error.
      adSize = AdSize.banner;
      debugPrint('[BannerAdWidget] Adaptive size failed — using standard banner');
    }

    if (!mounted) return;

    _bannerAd = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('[BannerAdWidget] Banner ad loaded ✓');
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[BannerAdWidget] Banner ad failed to load: $error');
          ad.dispose();
          _bannerAd = null;
          _loadStarted = false;
          if (mounted) {
            setState(() => _isLoaded = false);
            // Retry after 5 seconds.
            Future.delayed(const Duration(seconds: 5), _loadAd);
          }
        },
      ),
    );

    await _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

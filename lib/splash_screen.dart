import 'dart:async';

import 'package:flutter/material.dart';

import 'shared/services/watermark_helper.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onSplashComplete;

  const SplashScreen({super.key, required this.onSplashComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late final AnimationController _progressController;

  late final Animation<double> _iconScaleAnimation;
  late final Animation<double> _iconFadeAnimation;
  late final Animation<double> _pulseScaleAnimation;
  late final Animation<double> _pulseGlowAnimation;
  late final Animation<double> _progressAnimation;

  String _loadingStatus = 'Initializing...';
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();

    // 1. Initial Scale & Fade In
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _iconScaleAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
    );
    _iconFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );

    // 2. Continuous subtle breathing pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseGlowAnimation = Tween<double>(begin: 0.25, end: 0.55).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController.forward().then((_) {
      if (!_isDisposed) {
        _pulseController.repeat(reverse: true);
      }
    });

    // 3. Loading progress animation (from 0 to 1 over ~2.1 seconds)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOutCubic,
    );

    _progressController.addListener(() {
      final value = _progressController.value;
      final newStatus = switch (value) {
        < 0.35 => 'Initializing...',
        < 0.75 => 'Loading tools...',
        _ => 'Almost ready...',
      };
      if (newStatus != _loadingStatus && mounted) {
        setState(() => _loadingStatus = newStatus);
      }
    });
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animDone = true;
        _checkComplete();
      }
    });
    _progressController.forward();

    _initializeApp();
  }

  bool _initDone = false;
  bool _animDone = false;

  void _checkComplete() {
    if (_initDone && _animDone && mounted && !_isDisposed) {
      widget.onSplashComplete();
    }
  }

  Future<void> _initializeApp() async {
    try {
      try {
        await WatermarkHelper.loadIconBytes();
      } catch (_) {}
    } finally {
      _initDone = true;
      _checkComplete();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _entryController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background ambient gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF0A101D),
                    Color(0xFF060A12),
                  ],
                ),
              ),
            ),
          ),

          // Center: Animated App Icon + Branding + Loading Progress
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _entryController,
                _pulseController,
                _progressController,
              ]),
              builder: (context, _) {
                final scale =
                    _iconScaleAnimation.value * _pulseScaleAnimation.value;
                final opacity = _iconFadeAnimation.value;
                final glow = _pulseGlowAnimation.value;

                return Opacity(
                  opacity: opacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zoomed, uncropped app icon with layered ambient glow
                      Transform.scale(
                        scale: scale,
                        child: SizedBox(
                          width: 136,
                          height: 136,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Radial ambient glow blooming behind the uncropped logo
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF38BDF8)
                                          .withValues(alpha: glow * 0.5),
                                      blurRadius: 36,
                                      spreadRadius: 8,
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF6366F1)
                                          .withValues(alpha: glow * 0.4),
                                      blurRadius: 52,
                                      spreadRadius: 14,
                                    ),
                                  ],
                                ),
                              ),
                              // Zoomed, 100% uncropped crisp app logo
                              Image.asset(
                                'assets/icons/icon.png',
                                width: 136,
                                height: 136,
                                fit: BoxFit.contain,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App Name
                      const Text(
                        'PixelTools',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Tagline
                      const Text(
                        'Convert · Edit · Create',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 38),

                      // Sleek Loading Indicator Bar
                      SizedBox(
                        width: 170,
                        child: Column(
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor:
                                      _progressAnimation.value.clamp(0.05, 1.0),
                                  child: Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF38BDF8),
                                          Color(0xFF6366F1),
                                          Color(0xFFC084FC),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF38BDF8)
                                              .withValues(alpha: 0.6),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _loadingStatus,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Centre: "bnbkio"
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'from',
                      style: TextStyle(
                        color: const Color(0xFF64748B).withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'bnbkio',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

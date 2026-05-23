import 'package:flutter/material.dart';

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  static const _features = <_FeatureRow>[
    _FeatureRow('Ads', '✗', '✓'),
    _FeatureRow('No limits', '✗', '✓'),
    _FeatureRow('EXIF data', '✗', '✓'),
    _FeatureRow('Adjust size', '✗', '✓'),
    _FeatureRow('Unlimited edits', '✗', '✓'),
    _FeatureRow('Support', '✗', '✓'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [scheme.surface, scheme.surfaceContainer, scheme.surface]
                : const [Color(0xFFF8FAFF), Color(0xFFFCFAFF), Color(0xFFFFFCF8)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              children: [
                _HeaderRow(),
                const SizedBox(height: 20),
                _PremiumHero(theme: theme),
                const SizedBox(height: 28),
                _ComparisonTable(scheme: scheme, theme: theme),
                const SizedBox(height: 32),
                _PricingButton(
                  label: 'Yearly',
                  price: '\$1.99',
                  period: '/year',
                  gradientColors: const [Color(0xFF5B4DFF), Color(0xFF7C6FFF)],
                ),
                const SizedBox(height: 14),
                _PricingButton(
                  label: 'Lifetime',
                  price: '\$4.99',
                  period: ' one-time',
                  gradientColors: const [Color(0xFFE64A19), Color(0xFFFF7043)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

class _PremiumHero extends StatelessWidget {
  const _PremiumHero({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1F45), Color(0xFF4338CA), Color(0xFF0F9D9A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x221C2459),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/icons/icon.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Upgrade to Pro',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Get rid of Ads and get unlimited features',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.scheme, required this.theme});

  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Feature',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Free',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Pro',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(PremiumScreen._features.length, (i) {
            final feature = PremiumScreen._features[i];
            final isLast = i == PremiumScreen._features.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      feature.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      feature.free,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      feature.pro,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: const Color(0xFF15803D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PricingButton extends StatelessWidget {
  const _PricingButton({
    required this.label,
    required this.price,
    required this.period,
    required this.gradientColors,
  });

  final String label;
  final String price;
  final String period;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label plan selected. Coming soon.')),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: gradientColors,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              height: 24,
              width: 1,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 16),
            Text(
              price,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              period,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow {
  const _FeatureRow(this.label, this.free, this.pro);

  final String label;
  final String free;
  final String pro;
}

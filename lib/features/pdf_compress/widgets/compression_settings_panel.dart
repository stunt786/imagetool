import 'package:flutter/material.dart';

import '../models/pdf_compress_state.dart';

class CompressionSettingsPanel extends StatelessWidget {
  const CompressionSettingsPanel({
    super.key,
    required this.level,
    required this.onLevelChanged,
    required this.colorQuality,
    required this.onColorQualityChanged,
    required this.greyQuality,
    required this.onGreyQualityChanged,
    required this.monoQuality,
    required this.onMonoQualityChanged,
    required this.compressStreams,
    required this.onCompressStreamsChanged,
    required this.unembedSimpleFonts,
    required this.onUnembedSimpleFontsChanged,
    required this.unembedComplexFonts,
    required this.onUnembedComplexFontsChanged,
    required this.unembedUnusualFonts,
    required this.onUnembedUnusualFontsChanged,
    required this.flattenLayers,
    required this.onFlattenLayersChanged,
    required this.isAdvancedExpanded,
    required this.onToggleAdvanced,
  });

  final CompressionLevel level;
  final ValueChanged<CompressionLevel> onLevelChanged;
  final int colorQuality;
  final ValueChanged<int> onColorQualityChanged;
  final int greyQuality;
  final ValueChanged<int> onGreyQualityChanged;
  final int monoQuality;
  final ValueChanged<int> onMonoQualityChanged;
  final bool compressStreams;
  final ValueChanged<bool> onCompressStreamsChanged;
  final bool unembedSimpleFonts;
  final ValueChanged<bool> onUnembedSimpleFontsChanged;
  final bool unembedComplexFonts;
  final ValueChanged<bool> onUnembedComplexFontsChanged;
  final bool unembedUnusualFonts;
  final ValueChanged<bool> onUnembedUnusualFontsChanged;
  final bool flattenLayers;
  final ValueChanged<bool> onFlattenLayersChanged;
  final bool isAdvancedExpanded;
  final VoidCallback onToggleAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Flexible(
              child: Text(
                'Compression Level',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                level.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2x2 Preset Grid
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3.0,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: CompressionLevel.values.length,
          itemBuilder: (context, index) {
            final lvl = CompressionLevel.values[index];
            final isSelected = lvl == level;
            return GestureDetector(
              onTap: () => onLevelChanged(lvl),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primary.withValues(alpha: 0.15)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.compress_rounded,
                          size: 16,
                          color: isSelected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          lvl.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Advanced Options Collapsible Card
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAdvancedExpanded
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onToggleAdvanced,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isAdvancedExpanded
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 20,
                          color: isAdvancedExpanded
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Advanced Options',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              isAdvancedExpanded
                                  ? 'Tune image qualities, streams, fonts, & layers'
                                  : 'Tap to configure custom compression parameters',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isAdvancedExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),

              if (isAdvancedExpanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Image Qualities
                      Row(
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Image Quality',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Color Image Quality
                      _QualitySlider(
                        title: 'Color Image Quality',
                        icon: Icons.palette_outlined,
                        value: colorQuality,
                        onChanged: onColorQualityChanged,
                      ),
                      const SizedBox(height: 12),

                      // Grey Images Quality
                      _QualitySlider(
                        title: 'Grey Images Quality',
                        icon: Icons.filter_b_and_w_outlined,
                        value: greyQuality,
                        onChanged: onGreyQualityChanged,
                      ),
                      const SizedBox(height: 12),

                      // Mono Image Quality
                      _QualitySlider(
                        title: 'Mono Image Quality',
                        icon: Icons.contrast_outlined,
                        value: monoQuality,
                        onChanged: onMonoQualityChanged,
                      ),

                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Section 2: Other Options
                      Row(
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Other Options',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Compress Streams
                      _OptionSwitchTile(
                        icon: Icons.compress_rounded,
                        title: 'Compress Streams',
                        subtitle:
                            'Flate/DEFLATE compress uncompressed contents & metadata',
                        value: compressStreams,
                        onChanged: onCompressStreamsChanged,
                      ),

                      // Unembed Simple Fonts
                      _OptionSwitchTile(
                        icon: Icons.font_download_outlined,
                        title: 'Unembed Simple Fonts',
                        subtitle:
                            'Remove embedded standard TrueType/Type 1 font programs',
                        value: unembedSimpleFonts,
                        onChanged: onUnembedSimpleFontsChanged,
                      ),

                      // Unembed Complex Fonts
                      _OptionSwitchTile(
                        icon: Icons.translate_outlined,
                        title: 'Unembed Complex Fonts',
                        subtitle:
                            'Remove composite CID / Unicode font programs',
                        value: unembedComplexFonts,
                        onChanged: onUnembedComplexFontsChanged,
                      ),

                      // Unembed Unusual Fonts
                      _OptionSwitchTile(
                        icon: Icons.text_fields_outlined,
                        title: 'Unembed Unusual Fonts',
                        subtitle:
                            'Remove Type 3 and custom glyph font programs',
                        value: unembedUnusualFonts,
                        onChanged: onUnembedUnusualFontsChanged,
                      ),

                      // Flatten (will remove layers)
                      _OptionSwitchTile(
                        icon: Icons.layers_clear_outlined,
                        title: 'Flatten (will remove layers)',
                        subtitle:
                            'Merge optional content layers and bake annotations/forms',
                        value: flattenLayers,
                        onChanged: onFlattenLayersChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QualitySlider extends StatelessWidget {
  const _QualitySlider({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$value%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 7,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 14,
              ),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              label: '$value%',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionSwitchTile extends StatelessWidget {
  const _OptionSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: value
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: value ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: value ? scheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

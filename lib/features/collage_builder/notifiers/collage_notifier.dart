import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/settings/app_settings.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/watermark_helper.dart';
import '../models/collage_state.dart';

final collageProvider = NotifierProvider<CollageNotifier, CollageState>(
  CollageNotifier.new,
);

class CollageNotifier extends Notifier<CollageState> {
  static const int maxCollageImages = 9;
  final List<CollageImageSlot> _cachedSlots = [];
  @override
  CollageState build() {
    return CollageState(
      images: List.generate(
        CollageLayout.all[0].slotCount,
        (i) => CollageImageSlot(index: i),
      ),
      layout: CollageLayout.all[0],
      gap: 4.0,
      cornerRadius: 8.0,
      backgroundColor: const Color(0xFFE8EAF6),
      canvasWidth: 1080,
      canvasHeight: 1080,
    );
  }

  void _syncCachedSlots(List<CollageImageSlot> slots) {
    for (final slot in slots) {
      if (slot.hasImage) {
        final existingIdx =
            _cachedSlots.indexWhere((c) => c.imageName == slot.imageName);
        if (existingIdx != -1) {
          _cachedSlots[existingIdx] = slot;
        } else {
          _cachedSlots.add(slot);
        }
      }
    }
  }

  Future<void> pickImages(BuildContext context) async {
    // Guard: enforce 9-image maximum for 3x3 support
    if (state.imageCount >= maxCollageImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 9 photos allowed in a collage.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.images,
      allowMultiple: true,
    );

    if (picked.isEmpty) return;

    final bytesList = <Uint8List>[];
    final names = <String>[];

    for (final file in picked) {
      if (file.bytes != null) {
        bytesList.add(file.bytes!);
        names.add(file.name);
      }
    }

    if (bytesList.isEmpty) return;

    // Cap total images to maxCollageImages (9)
    final maxNew = maxCollageImages - state.imageCount;
    if (bytesList.length > maxNew) {
      final overflow = bytesList.length - maxNew;
      bytesList.removeRange(maxNew, bytesList.length);
      names.removeRange(maxNew, names.length);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Only $maxNew image(s) added (9 max). $overflow photo(s) skipped.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    final emptySlots = <int>[];
    for (int i = 0; i < state.images.length; i++) {
      if (!state.images[i].hasImage) {
        emptySlots.add(i);
      }
    }

    final slotsNeeded = bytesList.length;
    final slotsAvailable = emptySlots.length;

    if (slotsNeeded <= slotsAvailable) {
      final newImages = List<CollageImageSlot>.from(state.images);
      for (int i = 0; i < bytesList.length; i++) {
        newImages[emptySlots[i]] = CollageImageSlot(
          index: emptySlots[i],
          imageBytes: bytesList[i],
          imageName: names[i],
        );
      }
      _syncCachedSlots(newImages);
      state = state.copyWith(images: newImages);
    } else {
      final newLayout = CollageLayout.getLayoutForImageCount(
        state.imageCount + bytesList.length,
      );
      final newImages = <CollageImageSlot>[];

      for (int i = 0; i < state.images.length; i++) {
        newImages.add(CollageImageSlot(
          index: i,
          imageBytes: state.images[i].imageBytes,
          imageName: state.images[i].imageName,
          scale: state.images[i].scale,
          offsetX: state.images[i].offsetX,
          offsetY: state.images[i].offsetY,
          fitMode: state.images[i].fitMode,
        ));
      }

      for (int i = state.images.length; i < newLayout.slotCount; i++) {
        newImages.add(CollageImageSlot(index: i));
      }

      int imageIndex = 0;
      for (int i = 0; i < newImages.length && imageIndex < bytesList.length; i++) {
        if (!newImages[i].hasImage) {
          newImages[i] = CollageImageSlot(
            index: i,
            imageBytes: bytesList[imageIndex],
            imageName: names[imageIndex],
          );
          imageIndex++;
        }
      }

      if (imageIndex < bytesList.length) {
        for (int i = newImages.length - 1; i >= 0 && imageIndex < bytesList.length; i--) {
          newImages[i] = CollageImageSlot(
            index: i,
            imageBytes: bytesList[imageIndex],
            imageName: names[imageIndex],
          );
          imageIndex++;
        }
      }

      _syncCachedSlots(newImages);
      state = state.copyWith(
        images: newImages,
        layout: newLayout,
      );
    }
  }

  /// Loads images directly from file paths into the collage.
  Future<void> loadFromPaths(List<String> paths) async {
    final bytesList = <Uint8List>[];
    final names = <String>[];
    for (final path in paths.take(maxCollageImages)) {
      try {
        final file = File(path);
        if (await file.exists()) {
          bytesList.add(await file.readAsBytes());
          names.add(p.basename(path));
        }
      } catch (_) {}
    }
    if (bytesList.isEmpty) return;

    final count = bytesList.length;
    final layout = CollageLayout.getLayoutForImageCount(count);
    final slots = <CollageImageSlot>[];
    for (int i = 0; i < layout.slotCount; i++) {
      if (i < count) {
        slots.add(CollageImageSlot(
          index: i,
          imageBytes: bytesList[i],
          imageName: names[i],
        ));
      } else {
        slots.add(CollageImageSlot(index: i));
      }
    }
    _syncCachedSlots(slots);
    state = state.copyWith(
      images: slots,
      layout: layout,
    );
  }

  Future<void> addImageToSlot(BuildContext context, int slotIndex) async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.images,
      allowMultiple: false,
    );

    if (picked.isEmpty || picked.first.bytes == null) return;

    final bytes = picked.first.bytes!;

    final newImages = List<CollageImageSlot>.from(state.images);
    newImages[slotIndex] = CollageImageSlot(
      index: slotIndex,
      imageBytes: bytes,
      imageName: picked.first.name,
    );

    _syncCachedSlots(newImages);
    state = state.copyWith(images: newImages);
  }

  void setSlotImage(int slotIndex, Uint8List bytes, String name) {
    if (slotIndex < 0 || slotIndex >= state.images.length) return;
    final newImages = List<CollageImageSlot>.from(state.images);
    newImages[slotIndex] = CollageImageSlot(
      index: slotIndex,
      imageBytes: bytes,
      imageName: name,
    );
    _syncCachedSlots(newImages);
    state = state.copyWith(images: newImages);
  }

  void removeImageFromSlot(int slotIndex) {
    final newImages = List<CollageImageSlot>.from(state.images);
    final removed = newImages[slotIndex];
    if (removed.hasImage) {
      _cachedSlots.removeWhere((c) => c.imageName == removed.imageName);
    }
    newImages[slotIndex] = newImages[slotIndex].clear();
    state = state.copyWith(images: newImages);
  }

  void swapImages(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    if (fromIndex < 0 || toIndex < 0) return;
    if (fromIndex >= state.images.length || toIndex >= state.images.length) return;

    final newImages = List<CollageImageSlot>.from(state.images);
    final fromSlot = newImages[fromIndex];
    final toSlot = newImages[toIndex];

    newImages[fromIndex] = CollageImageSlot(
      index: fromIndex,
      imageBytes: toSlot.imageBytes,
      imageName: toSlot.imageName,
      scale: toSlot.scale,
      offsetX: toSlot.offsetX,
      offsetY: toSlot.offsetY,
      fitMode: toSlot.fitMode,
    );
    newImages[toIndex] = CollageImageSlot(
      index: toIndex,
      imageBytes: fromSlot.imageBytes,
      imageName: fromSlot.imageName,
      scale: fromSlot.scale,
      offsetX: fromSlot.offsetX,
      offsetY: fromSlot.offsetY,
      fitMode: fromSlot.fitMode,
    );

    _syncCachedSlots(newImages);
    state = state.copyWith(images: newImages);
  }

  void changeLayout(CollageLayout newLayout) {
    _syncCachedSlots(state.images);

    final newImages = <CollageImageSlot>[];
    final activeImages = state.images.where((s) => s.hasImage).toList();
    final allAvailable = <CollageImageSlot>[
      ...activeImages,
      for (final cached in _cachedSlots)
        if (!activeImages.any((a) => a.imageName == cached.imageName)) cached,
    ];

    for (int i = 0; i < newLayout.slotCount; i++) {
      if (i < state.images.length && state.images[i].hasImage) {
        newImages.add(CollageImageSlot(
          index: i,
          imageBytes: state.images[i].imageBytes,
          imageName: state.images[i].imageName,
          scale: state.images[i].scale,
          offsetX: state.images[i].offsetX,
          offsetY: state.images[i].offsetY,
          fitMode: state.images[i].fitMode,
        ));
      } else if (i < allAvailable.length) {
        final src = allAvailable[i];
        newImages.add(CollageImageSlot(
          index: i,
          imageBytes: src.imageBytes,
          imageName: src.imageName,
          scale: src.scale,
          offsetX: src.offsetX,
          offsetY: src.offsetY,
          fitMode: src.fitMode,
        ));
      } else {
        newImages.add(CollageImageSlot(index: i));
      }
    }

    state = state.copyWith(
      images: newImages,
      layout: newLayout,
    );
  }

  void setScale(int slotIndex, double scale) {
    final newImages = List<CollageImageSlot>.from(state.images);
    newImages[slotIndex] = newImages[slotIndex].copyWith(scale: scale);
    state = state.copyWith(images: newImages);
  }

  void setOffset(int slotIndex, double offsetX, double offsetY) {
    final newImages = List<CollageImageSlot>.from(state.images);
    newImages[slotIndex] = newImages[slotIndex].copyWith(
      offsetX: offsetX,
      offsetY: offsetY,
    );
    state = state.copyWith(images: newImages);
  }

  void cycleFitMode(int slotIndex) {
    final newImages = List<CollageImageSlot>.from(state.images);
    final current = newImages[slotIndex].fitMode;
    ImageFitMode next;
    switch (current) {
      case ImageFitMode.cover:
        next = ImageFitMode.contain;
        break;
      case ImageFitMode.contain:
        next = ImageFitMode.fill;
        break;
      case ImageFitMode.fill:
        next = ImageFitMode.cover;
        break;
    }
    newImages[slotIndex] = newImages[slotIndex].copyWith(fitMode: next);
    state = state.copyWith(images: newImages);
  }

  void setGap(double gap) {
    state = state.copyWith(gap: gap);
  }

  void setCornerRadius(double radius) {
    state = state.copyWith(cornerRadius: radius);
  }

  void setBackgroundColor(Color color) {
    state = state.copyWith(backgroundColor: color);
  }

  void setCaptionText(String text) {
    state = state.copyWith(captionText: text);
  }

  void setCaptionColor(Color color) {
    state = state.copyWith(captionColor: color);
  }

  void setCaptionSize(double size) {
    state = state.copyWith(captionSize: size);
  }

  void setCaptionAlignment(Alignment alignment) {
    state = state.copyWith(captionAlignment: alignment);
  }

  void setCaptionNormalizedOffset(Offset offset) {
    state = state.copyWith(captionNormalizedOffset: offset);
  }

  void setCaptionScale(double scale) {
    state = state.copyWith(captionScale: scale);
  }

  void setCaptionFontFamily(String fontFamily) {
    state = state.copyWith(captionFontFamily: fontFamily);
  }

  void addTextLayer() {
    final id = 'layer_${DateTime.now().millisecondsSinceEpoch}';
    final layers = List<CollageTextLayer>.from(state.textLayers);
    layers.add(CollageTextLayer(id: id));
    state = state.copyWith(textLayers: layers);
  }

  void removeTextLayer(String id) {
    final layers = state.textLayers.where((l) => l.id != id).toList();
    state = state.copyWith(textLayers: layers);
  }

  void updateTextLayer(
    String id, {
    String? text,
    Color? color,
    double? fontSize,
    String? fontFamily,
    bool? bold,
    bool? italic,
    double? opacity,
    TextAlign? alignment,
  }) {
    final layers = <CollageTextLayer>[];
    for (final layer in state.textLayers) {
      if (layer.id == id) {
        layers.add(layer.copyWith(
          text: text,
          color: color,
          fontSize: fontSize,
          fontFamily: fontFamily,
          bold: bold,
          italic: italic,
          opacity: opacity,
          alignment: alignment,
        ));
      } else {
        layers.add(layer);
      }
    }
    state = state.copyWith(textLayers: layers);
  }

  void setTextLayerOffset(String id, Offset offset) {
    final layers = <CollageTextLayer>[];
    for (final layer in state.textLayers) {
      if (layer.id == id) {
        layers.add(layer.copyWith(normalizedOffset: offset));
      } else {
        layers.add(layer);
      }
    }
    state = state.copyWith(textLayers: layers);
  }

  void setTextLayerScale(String id, double scale) {
    final layers = <CollageTextLayer>[];
    for (final layer in state.textLayers) {
      if (layer.id == id) {
        layers.add(layer.copyWith(scale: scale));
      } else {
        layers.add(layer);
      }
    }
    state = state.copyWith(textLayers: layers);
  }

  void setTextLayerRotation(String id, double rotation) {
    final layers = <CollageTextLayer>[];
    for (final layer in state.textLayers) {
      if (layer.id == id) {
        layers.add(layer.copyWith(rotation: rotation));
      } else {
        layers.add(layer);
      }
    }
    state = state.copyWith(textLayers: layers);
  }

  Future<Uint8List?> exportCollage() async {
    state = state.copyWith(isExporting: true, exportProgress: 0.0);

    try {
      final canvasWidth = state.canvasWidth;
      final canvasHeight = state.canvasHeight;
      // Logical preview reference scale (canvas is nominally previewed at 360 logical px)
      final scaleFactor = canvasWidth / 360.0;
      final gapPx = (state.gap * scaleFactor).round();
      final radiusPx = (state.cornerRadius * scaleFactor).round();

      final bgR = (state.backgroundColor.r * 255).round().clamp(0, 255);
      final bgG = (state.backgroundColor.g * 255).round().clamp(0, 255);
      final bgB = (state.backgroundColor.b * 255).round().clamp(0, 255);

      final canvas = img.Image(
        width: canvasWidth,
        height: canvasHeight,
      );

      img.fill(canvas, color: img.ColorRgb8(bgR, bgG, bgB));

      for (int i = 0; i < state.layout.slotCount; i++) {
        final slot = state.images[i];
        if (!slot.hasImage) continue;

        final rect = state.layout.slotRects[i];
        final x = (rect.left * canvasWidth + gapPx).toInt();
        final y = (rect.top * canvasHeight + gapPx).toInt();
        final w = ((rect.width) * canvasWidth - gapPx * 2).toInt();
        final h = ((rect.height) * canvasHeight - gapPx * 2).toInt();

        if (w <= 0 || h <= 0) continue;

        final decoded = img.decodeImage(slot.imageBytes!);
        if (decoded == null) continue;

        img.Image resized;
        switch (slot.fitMode) {
          case ImageFitMode.cover:
            final srcW = decoded.width;
            final srcH = decoded.height;
            final dstAspect = w / h;
            final srcAspect = srcW / srcH;

            int cropW, cropH, cropX, cropY;
            if (srcAspect > dstAspect) {
              cropH = srcH;
              cropW = (srcH * dstAspect).toInt();
              cropX = ((srcW - cropW) / 2).toInt() + (slot.offsetX * srcW * 0.1).toInt();
              cropY = 0;
            } else {
              cropW = srcW;
              cropH = (srcW / dstAspect).toInt();
              cropX = 0;
              cropY = ((srcH - cropH) / 2).toInt() + (slot.offsetY * srcH * 0.1).toInt();
            }

            cropX = cropX.clamp(0, srcW - 1);
            cropY = cropY.clamp(0, srcH - 1);
            cropW = cropW.clamp(1, srcW - cropX);
            cropH = cropH.clamp(1, srcH - cropY);

            final cropped = img.copyCrop(decoded, x: cropX, y: cropY, width: cropW, height: cropH);
            resized = img.copyResize(cropped, width: w, height: h);
            break;
          case ImageFitMode.contain:
            resized = img.copyResize(decoded, width: w, height: h, maintainAspect: true);
            break;
          case ImageFitMode.fill:
            resized = img.copyResize(decoded, width: w, height: h);
            break;
        }

        final slotImage = img.Image(width: w, height: h);
        img.fill(slotImage, color: img.ColorRgb8(bgR, bgG, bgB));

        if (slot.fitMode == ImageFitMode.contain) {
          final offsetX = ((w - resized.width) / 2).toInt();
          final offsetY = ((h - resized.height) / 2).toInt();
          img.compositeImage(slotImage, resized, dstX: offsetX, dstY: offsetY);
        } else {
          img.compositeImage(slotImage, resized);
        }

        if (radiusPx > 0) {
          _applyRoundedCorners(slotImage, radiusPx, bgR, bgG, bgB);
        }

        img.compositeImage(canvas, slotImage, dstX: x, dstY: y);

        state = state.copyWith(exportProgress: (i + 1) / state.layout.slotCount);
      }

      for (final layer in state.textLayers) {
        if (layer.isEmpty) continue;

        final text = layer.text.trim();
        final effectiveFontSize = layer.fontSize * layer.scale;
        final canvasFontSize = effectiveFontSize * (state.canvasWidth / 360.0);
        final fontFamily = layer.fontFamily == 'Roboto' ? null : layer.fontFamily;
        final FontWeight fontWeight = layer.bold
            ? (layer.fontFamily == 'Impact' ||
                    layer.fontFamily == 'sans-serif'
                ? FontWeight.w900
                : FontWeight.bold)
            : FontWeight.w400;

        final uiTextAlign = layer.alignment;
        final uiFontWeight = fontWeight;
        final uiFontFamily = fontFamily;
        final uiFontStyle =
            layer.italic ? FontStyle.italic : FontStyle.normal;
        final alpha = (layer.opacity.clamp(0.05, 1.0) * 255).round();

        final measureBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: canvasFontSize,
            fontWeight: uiFontWeight,
            fontStyle: uiFontStyle,
            fontFamily: uiFontFamily,
            textAlign: uiTextAlign,
          ),
        )..pushStyle(ui.TextStyle(
            color: ui.Color(0xFFFFFFFF),
            fontSize: canvasFontSize,
            fontWeight: uiFontWeight,
            fontStyle: uiFontStyle,
            fontFamily: uiFontFamily,
          ))
          ..addText(text);

        final measureParagraph = measureBuilder.build();
        measureParagraph.layout(ui.ParagraphConstraints(width: state.canvasWidth.toDouble()));

        final textWidth = measureParagraph.width;
        final textHeight = measureParagraph.height;

        double textX = layer.normalizedOffset.dx * state.canvasWidth - textWidth / 2;
        double textY = layer.normalizedOffset.dy * state.canvasHeight - textHeight / 2;

        textX = textX.clamp(10.0, (state.canvasWidth - textWidth - 10).clamp(10.0, state.canvasWidth.toDouble()));
        textY = textY.clamp(10.0, (state.canvasHeight - textHeight - 10).clamp(10.0, state.canvasHeight.toDouble()));

        final mainColor = ui.Color.fromARGB(
          alpha,
          (layer.color.r * 255).round().clamp(0, 255),
          (layer.color.g * 255).round().clamp(0, 255),
          (layer.color.b * 255).round().clamp(0, 255),
        );

        final shadowOffsets = [
          const Offset(1, 1),
          const Offset(-1, -1),
          const Offset(1, -1),
          const Offset(-1, 1),
        ];

        final pictureRecorder = ui.PictureRecorder();
        final drawCanvas = Canvas(pictureRecorder);

        if (layer.rotation != 0.0) {
          final center = Offset(state.canvasWidth / 2, state.canvasHeight / 2);
          drawCanvas.translate(center.dx, center.dy);
          drawCanvas.rotate(layer.rotation);
          drawCanvas.translate(-center.dx, -center.dy);
        }

        for (final offset in shadowOffsets) {
          final shadowBuilder = ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: canvasFontSize,
              fontWeight: uiFontWeight,
              fontStyle: uiFontStyle,
              fontFamily: uiFontFamily,
              textAlign: uiTextAlign,
            ),
          )..pushStyle(ui.TextStyle(
              color: ui.Color(0xCC000000),
              fontSize: canvasFontSize,
              fontWeight: uiFontWeight,
              fontStyle: uiFontStyle,
              fontFamily: uiFontFamily,
            ))
            ..addText(text);

          final shadowParagraph = shadowBuilder.build();
          shadowParagraph.layout(ui.ParagraphConstraints(width: state.canvasWidth.toDouble()));
          drawCanvas.drawParagraph(shadowParagraph, Offset(textX + offset.dx * 2, textY + offset.dy * 2));
        }

        final mainBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: canvasFontSize,
            fontWeight: uiFontWeight,
            fontFamily: uiFontFamily,
            textAlign: uiTextAlign,
          ),
        )..pushStyle(ui.TextStyle(
            color: mainColor,
            fontSize: canvasFontSize,
            fontWeight: uiFontWeight,
            fontFamily: uiFontFamily,
          ))
          ..addText(text);

        final mainParagraph = mainBuilder.build();
        mainParagraph.layout(ui.ParagraphConstraints(width: state.canvasWidth.toDouble()));
        drawCanvas.drawParagraph(mainParagraph, Offset(textX, textY));

        final picture = pictureRecorder.endRecording();
        final textImage = await picture.toImage(state.canvasWidth, state.canvasHeight);

        final byteData = await textImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final textBytes = byteData.buffer.asUint8List();
          final decodedText = img.decodeImage(textBytes);
          if (decodedText != null) {
            img.compositeImage(canvas, decodedText);
          }
        }

        textImage.dispose();
      }

      final watermarked = WatermarkHelper.applyToImage(canvas, ref.read(appSettingsProvider));
      final encoded = img.encodeJpg(watermarked, quality: 95);
      state = state.copyWith(isExporting: false, exportProgress: 1.0);
      return Uint8List.fromList(encoded);
    } catch (e) {
      state = state.copyWith(isExporting: false);
      rethrow;
    }
  }

  void _applyRoundedCorners(img.Image image, int radius, int bgR, int bgG, int bgB) {
    final w = image.width;
    final h = image.height;
    final r = radius.clamp(0, w ~/ 2).clamp(0, h ~/ 2);
    if (r <= 0) return;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double dist = -1.0;

        if (x < r && y < r) {
          final dx = r - x - 1;
          final dy = r - y - 1;
          dist = math.sqrt(dx * dx + dy * dy) - r;
        } else if (x >= w - r && y < r) {
          final dx = x - (w - r);
          final dy = r - y - 1;
          dist = math.sqrt(dx * dx + dy * dy) - r;
        } else if (x < r && y >= h - r) {
          final dx = r - x - 1;
          final dy = y - (h - r);
          dist = math.sqrt(dx * dx + dy * dy) - r;
        } else if (x >= w - r && y >= h - r) {
          final dx = x - (w - r);
          final dy = y - (h - r);
          dist = math.sqrt(dx * dx + dy * dy) - r;
        }

        if (dist >= 0.5) {
          image.setPixel(x, y, img.ColorRgb8(bgR, bgG, bgB));
        } else if (dist > -0.5) {
          final t = (dist + 0.5).clamp(0.0, 1.0);
          final p = image.getPixel(x, y);
          final blendedR = (p.r * (1.0 - t) + bgR * t).round().clamp(0, 255);
          final blendedG = (p.g * (1.0 - t) + bgG * t).round().clamp(0, 255);
          final blendedB = (p.b * (1.0 - t) + bgB * t).round().clamp(0, 255);
          image.setPixel(x, y, img.ColorRgb8(blendedR, blendedG, blendedB));
        }
      }
    }
  }

  void reset() {
    _cachedSlots.clear();
    state = CollageState(
      images: List.generate(
        CollageLayout.all[0].slotCount,
        (i) => CollageImageSlot(index: i),
      ),
      layout: CollageLayout.all[0],
      gap: 4.0,
      cornerRadius: 8.0,
      backgroundColor: const Color(0xFFE8EAF6),
      canvasWidth: 1080,
      canvasHeight: 1080,
    );
  }
}

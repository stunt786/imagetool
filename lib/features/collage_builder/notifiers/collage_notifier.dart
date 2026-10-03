import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/settings/app_settings.dart';
import '../../../core/utils/file_type_detector.dart';
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
    final maxNew = maxCollageImages - state.imageCount;
    if (maxNew <= 0) {
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
      maxAssets: maxNew,
    );

    if (picked.isEmpty) return;

    final bytesList = <Uint8List>[];
    final names = <String>[];
    int unsupportedCount = 0;

    for (final file in picked) {
      if (file.bytes != null) {
        if (!FileTypeDetector.isSupportedImage(file.bytes!)) {
          unsupportedCount++;
          continue;
        }
        bytesList.add(file.bytes!);
        names.add(file.name);
      }
    }

    if (unsupportedCount > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$unsupportedCount unsupported file(s) skipped. Only JPG, PNG, WebP, GIF, BMP are supported.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (bytesList.isEmpty) return;

    // Cap total images to maxCollageImages (9)
    if (bytesList.length > maxNew) {
      final overflow = bytesList.length - maxNew;
      bytesList.removeRange(maxNew, bytesList.length);
      names.removeRange(maxNew, names.length);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Only $maxNew image(s) added (9 max). $overflow photo(s) skipped.'),
            duration: const Duration(seconds: 2),
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
          rotation: state.images[i].rotation,
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

    if (!FileTypeDetector.isSupportedImage(picked.first.bytes!)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unsupported file format. Please select a valid image.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

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
      rotation: toSlot.rotation,
      fitMode: toSlot.fitMode,
    );
    newImages[toIndex] = CollageImageSlot(
      index: toIndex,
      imageBytes: fromSlot.imageBytes,
      imageName: fromSlot.imageName,
      scale: fromSlot.scale,
      offsetX: fromSlot.offsetX,
      offsetY: fromSlot.offsetY,
      rotation: fromSlot.rotation,
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
          rotation: state.images[i].rotation,
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
          rotation: src.rotation,
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

  void rotateSlot(int slotIndex, [double degrees = 90.0]) {
    if (slotIndex < 0 || slotIndex >= state.images.length) return;
    final newImages = List<CollageImageSlot>.from(state.images);
    final currentRotation = newImages[slotIndex].rotation;
    final newRotation = (currentRotation + degrees) % 360.0;
    newImages[slotIndex] = newImages[slotIndex].copyWith(rotation: newRotation);
    _syncCachedSlots(newImages);
    state = state.copyWith(images: newImages);
  }

  void setPreviewSize(double width, double height) {
    if (state.previewWidth == width && state.previewHeight == height) return;
    state = state.copyWith(previewWidth: width, previewHeight: height);
  }

  void setScale(int slotIndex, double scale) {
    if (slotIndex < 0 || slotIndex >= state.images.length) return;
    final newImages = List<CollageImageSlot>.from(state.images);
    final clampedScale = scale.clamp(1.0, 5.0);
    newImages[slotIndex] = newImages[slotIndex].copyWith(
      scale: clampedScale,
      offsetX: clampedScale <= 1.0 ? 0.0 : newImages[slotIndex].offsetX,
      offsetY: clampedScale <= 1.0 ? 0.0 : newImages[slotIndex].offsetY,
    );
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
    if (state.isExporting) return null;
    state = state.copyWith(isExporting: true, exportProgress: 0.0);
    // Yield to the event loop so listeners update before image processing
    await Future<void>.delayed(Duration.zero);

    try {
      final canvasWidth = state.canvasWidth;
      final canvasHeight = state.canvasHeight;
      final previewWidth = (state.previewWidth != null && state.previewWidth! > 0)
          ? state.previewWidth!
          : 360.0;
      final scaleFactor = canvasWidth / previewWidth;
      final gapPx = (state.gap * scaleFactor).round();
      final radiusPx = (state.cornerRadius * scaleFactor).round();

      final bgR = (state.backgroundColor.r * 255).round().clamp(0, 255);
      final bgG = (state.backgroundColor.g * 255).round().clamp(0, 255);
      final bgB = (state.backgroundColor.b * 255).round().clamp(0, 255);

      final slotCount = state.layout.slotCount;
      final slots = <_CollageSlotData>[];
      for (int i = 0; i < slotCount; i++) {
        if (i >= state.images.length) continue;
        final slot = state.images[i];
        if (!slot.hasImage || slot.imageBytes == null || slot.imageBytes!.isEmpty) continue;
        if (i >= state.layout.slotRects.length) continue;
        final rect = state.layout.slotRects[i];
        slots.add(_CollageSlotData(
          imageBytes: slot.imageBytes!,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          rotation: slot.rotation,
          fitModeIndex: slot.fitMode.index,
          offsetX: slot.offsetX,
          offsetY: slot.offsetY,
          scale: slot.scale,
        ));
      }

      final allTextLayers = [
        ...state.textLayers,
        if (state.captionText != null && state.captionText!.trim().isNotEmpty)
          CollageTextLayer(
            id: '__legacy_caption__',
            text: state.captionText!,
            color: state.captionColor,
            fontSize: state.captionSize,
            fontFamily: state.captionFontFamily,
            normalizedOffset: state.captionNormalizedOffset,
            scale: state.captionScale,
          ),
      ];

      Uint8List? textOverlayPngBytes;
      final activeTextLayers = allTextLayers
          .where((l) => !l.isEmpty && l.text.trim().isNotEmpty)
          .toList();
      if (activeTextLayers.isNotEmpty) {
        final pictureRecorder = ui.PictureRecorder();
        final drawCanvas = Canvas(pictureRecorder);

        for (final layer in activeTextLayers) {
          final text = layer.text.trim();
          final effectiveFontSize = layer.fontSize * layer.scale;
          final canvasFontSize = effectiveFontSize * scaleFactor;
          final fontFamily =
              layer.fontFamily == 'Roboto' ? null : layer.fontFamily;
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
          )
            ..pushStyle(ui.TextStyle(
              color: const ui.Color(0xFFFFFFFF),
              fontSize: canvasFontSize,
              fontWeight: uiFontWeight,
              fontStyle: uiFontStyle,
              fontFamily: uiFontFamily,
            ))
            ..addText(text);

          final measureParagraph = measureBuilder.build();
          measureParagraph
              .layout(ui.ParagraphConstraints(width: canvasWidth.toDouble()));

          final textWidth = measureParagraph.width;
          final textHeight = measureParagraph.height;

          double textX =
              layer.normalizedOffset.dx * canvasWidth - textWidth / 2;
          double textY =
              layer.normalizedOffset.dy * canvasHeight - textHeight / 2;

          textX = textX.clamp(
              10.0,
              (canvasWidth - textWidth - 10)
                  .clamp(10.0, canvasWidth.toDouble()));
          textY = textY.clamp(
              10.0,
              (canvasHeight - textHeight - 10)
                  .clamp(10.0, canvasHeight.toDouble()));

          final mainColor = ui.Color.fromARGB(
            alpha,
            (layer.color.r * 255).round().clamp(0, 255),
            (layer.color.g * 255).round().clamp(0, 255),
            (layer.color.b * 255).round().clamp(0, 255),
          );

          final textCenterX = textX + textWidth / 2;
          final textCenterY = textY + textHeight / 2;

          drawCanvas.save();
          if (layer.rotation != 0.0) {
            drawCanvas.translate(textCenterX, textCenterY);
            drawCanvas.rotate(layer.rotation);
            drawCanvas.translate(-textCenterX, -textCenterY);
          }

          final shadowOffsets = const [
            Offset(1, 1),
            Offset(-1, -1),
            Offset(1, -1),
            Offset(-1, 1),
          ];

          for (final offset in shadowOffsets) {
            final shadowBuilder = ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontSize: canvasFontSize,
                fontWeight: uiFontWeight,
                fontStyle: uiFontStyle,
                fontFamily: uiFontFamily,
                textAlign: uiTextAlign,
              ),
            )
              ..pushStyle(ui.TextStyle(
                color: const ui.Color(0xCC000000),
                fontSize: canvasFontSize,
                fontWeight: uiFontWeight,
                fontStyle: uiFontStyle,
                fontFamily: uiFontFamily,
              ))
              ..addText(text);

            final shadowParagraph = shadowBuilder.build();
            shadowParagraph.layout(
                ui.ParagraphConstraints(width: canvasWidth.toDouble()));
            drawCanvas.drawParagraph(shadowParagraph,
                Offset(textX + offset.dx * 2, textY + offset.dy * 2));
          }

          final mainBuilder = ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: canvasFontSize,
              fontWeight: uiFontWeight,
              fontFamily: uiFontFamily,
              textAlign: uiTextAlign,
            ),
          )
            ..pushStyle(ui.TextStyle(
              color: mainColor,
              fontSize: canvasFontSize,
              fontWeight: uiFontWeight,
              fontFamily: uiFontFamily,
            ))
            ..addText(text);

          final mainParagraph = mainBuilder.build();
          mainParagraph
              .layout(ui.ParagraphConstraints(width: canvasWidth.toDouble()));
          drawCanvas.drawParagraph(mainParagraph, Offset(textX, textY));
          drawCanvas.restore();
        }

        final picture = pictureRecorder.endRecording();
        final textImage =
            await picture.toImage(canvasWidth, canvasHeight);
        final byteData =
            await textImage.toByteData(format: ui.ImageByteFormat.png);
        textImage.dispose();
        picture.dispose();
        if (byteData != null) {
          textOverlayPngBytes = byteData.buffer.asUint8List();
        }
      }

      final iconBytes = await WatermarkHelper.loadIconBytes();
      final appSettings = ref.read(appSettingsProvider);

      final params = _CollageExportParams(
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        gapPx: gapPx,
        radiusPx: radiusPx,
        bgR: bgR,
        bgG: bgG,
        bgB: bgB,
        slots: slots,
        textOverlayPngBytes: textOverlayPngBytes,
        watermarkIconBytes: iconBytes.isNotEmpty ? iconBytes : null,
        appSettings: appSettings,
      );

      final encoded = Platform.environment.containsKey('FLUTTER_TEST')
          ? _renderCollageWorker(params)
          : await compute(_renderCollageWorker, params);
      state = state.copyWith(isExporting: false, exportProgress: 1.0);
      return encoded;
    } catch (e) {
      state = state.copyWith(isExporting: false, exportProgress: 0.0);
      rethrow;
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
      previewWidth: state.previewWidth,
      previewHeight: state.previewHeight,
    );
  }
}

class _CollageSlotData {
  final Uint8List imageBytes;
  final double left;
  final double top;
  final double width;
  final double height;
  final double rotation;
  final int fitModeIndex;
  final double offsetX;
  final double offsetY;
  final double scale;

  const _CollageSlotData({
    required this.imageBytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.rotation,
    required this.fitModeIndex,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
  });
}

class _CollageExportParams {
  final int canvasWidth;
  final int canvasHeight;
  final int gapPx;
  final int radiusPx;
  final int bgR;
  final int bgG;
  final int bgB;
  final List<_CollageSlotData> slots;
  final Uint8List? textOverlayPngBytes;
  final Uint8List? watermarkIconBytes;
  final AppSettingsState appSettings;

  const _CollageExportParams({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.gapPx,
    required this.radiusPx,
    required this.bgR,
    required this.bgG,
    required this.bgB,
    required this.slots,
    required this.textOverlayPngBytes,
    required this.watermarkIconBytes,
    required this.appSettings,
  });
}

void _applyRoundedCornersToSlot(img.Image image, int radius, int bgR, int bgG, int bgB) {
  final w = image.width;
  final h = image.height;
  final r = radius.clamp(0, w ~/ 2).clamp(0, h ~/ 2);
  if (r <= 0) return;

  void blendCornerPixel(int x, int y, double dist) {
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

  // Top-Left corner
  for (int y = 0; y < r; y++) {
    final dy = r - y - 1;
    final dySq = dy * dy;
    for (int x = 0; x < r; x++) {
      final dx = r - x - 1;
      final dist = math.sqrt(dx * dx + dySq) - r;
      blendCornerPixel(x, y, dist);
    }
  }

  // Top-Right corner
  for (int y = 0; y < r; y++) {
    final dy = r - y - 1;
    final dySq = dy * dy;
    for (int x = w - r; x < w; x++) {
      final dx = x - (w - r);
      final dist = math.sqrt(dx * dx + dySq) - r;
      blendCornerPixel(x, y, dist);
    }
  }

  // Bottom-Left corner
  for (int y = h - r; y < h; y++) {
    final dy = y - (h - r);
    final dySq = dy * dy;
    for (int x = 0; x < r; x++) {
      final dx = r - x - 1;
      final dist = math.sqrt(dx * dx + dySq) - r;
      blendCornerPixel(x, y, dist);
    }
  }

  // Bottom-Right corner
  for (int y = h - r; y < h; y++) {
    final dy = y - (h - r);
    final dySq = dy * dy;
    for (int x = w - r; x < w; x++) {
      final dx = x - (w - r);
      final dist = math.sqrt(dx * dx + dySq) - r;
      blendCornerPixel(x, y, dist);
    }
  }
}

Uint8List? _renderCollageWorker(_CollageExportParams params) {
  final canvasWidth = params.canvasWidth;
  final canvasHeight = params.canvasHeight;
  final gapPx = params.gapPx;
  final radiusPx = params.radiusPx;
  final bgR = params.bgR;
  final bgG = params.bgG;
  final bgB = params.bgB;

  final canvas = img.Image(
    width: canvasWidth,
    height: canvasHeight,
  );
  img.fill(canvas, color: img.ColorRgb8(bgR, bgG, bgB));

  for (final slot in params.slots) {
    final x = (slot.left * canvasWidth + gapPx).toInt().clamp(0, canvasWidth - 1);
    final y = (slot.top * canvasHeight + gapPx).toInt().clamp(0, canvasHeight - 1);
    final w = math.max(1, math.min(canvasWidth - x, (slot.width * canvasWidth - gapPx * 2).toInt()));
    final h = math.max(1, math.min(canvasHeight - y, (slot.height * canvasHeight - gapPx * 2).toInt()));

    var decoded = img.decodeImage(slot.imageBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) continue;

    decoded = img.bakeOrientation(decoded);

    if (slot.rotation != 0.0) {
      decoded = img.copyRotate(decoded, angle: slot.rotation.toInt());
    }

    final fitMode = ImageFitMode.values[slot.fitModeIndex];
    img.Image resized;

    final srcW = decoded.width.toDouble();
    final srcH = decoded.height.toDouble();
    final scale = slot.scale.clamp(1.0, 5.0);

    final maxOffsetX = scale > 1.0 ? (w * (scale - 1.0)) / 2 : 0.0;
    final maxOffsetY = scale > 1.0 ? (h * (scale - 1.0)) / 2 : 0.0;
    final clampedOffsetX = (slot.offsetX * w).clamp(-maxOffsetX, maxOffsetX);
    final clampedOffsetY = (slot.offsetY * h).clamp(-maxOffsetY, maxOffsetY);

    switch (fitMode) {
      case ImageFitMode.cover:
        final s0 = math.max(w / srcW, h / srcH);
        final sTotal = s0 * scale;

        final cropW = (w / sTotal).clamp(1.0, srcW);
        final cropH = (h / sTotal).clamp(1.0, srcH);

        final cropX = ((srcW - cropW) / 2.0 - clampedOffsetX / sTotal)
            .clamp(0.0, srcW - cropW);
        final cropY = ((srcH - cropH) / 2.0 - clampedOffsetY / sTotal)
            .clamp(0.0, srcH - cropH);

        final cropped = img.copyCrop(
          decoded,
          x: cropX.round(),
          y: cropY.round(),
          width: cropW.round().clamp(1, decoded.width),
          height: cropH.round().clamp(1, decoded.height),
        );
        resized = img.copyResize(cropped, width: w, height: h);
        break;

      case ImageFitMode.contain:
        final s0 = math.min(w / srcW, h / srcH);
        final sTotal = s0 * scale;

        final scaledW = math.max(1, (srcW * sTotal).round());
        final scaledH = math.max(1, (srcH * sTotal).round());

        final tempResized = img.copyResize(decoded, width: scaledW, height: scaledH);

        final slotImage = img.Image(width: w, height: h);
        img.fill(slotImage, color: img.ColorRgb8(bgR, bgG, bgB));

        final dstX = ((w - scaledW) / 2.0 + clampedOffsetX).round();
        final dstY = ((h - scaledH) / 2.0 + clampedOffsetY).round();

        img.compositeImage(slotImage, tempResized, dstX: dstX, dstY: dstY);
        resized = slotImage;
        break;

      case ImageFitMode.fill:
        final scaledW = math.max(1, (w * scale).round());
        final scaledH = math.max(1, (h * scale).round());

        final tempResized = img.copyResize(decoded, width: scaledW, height: scaledH);

        final slotImage = img.Image(width: w, height: h);
        img.fill(slotImage, color: img.ColorRgb8(bgR, bgG, bgB));

        final dstX = ((w - scaledW) / 2.0 + clampedOffsetX).round();
        final dstY = ((h - scaledH) / 2.0 + clampedOffsetY).round();

        img.compositeImage(slotImage, tempResized, dstX: dstX, dstY: dstY);
        resized = slotImage;
        break;
    }

    final slotImage = img.Image(width: w, height: h);
    img.fill(slotImage, color: img.ColorRgb8(bgR, bgG, bgB));
    img.compositeImage(slotImage, resized);

    if (radiusPx > 0) {
      _applyRoundedCornersToSlot(slotImage, radiusPx, bgR, bgG, bgB);
    }

    img.compositeImage(canvas, slotImage, dstX: x, dstY: y);
  }

  if (params.textOverlayPngBytes != null && params.textOverlayPngBytes!.isNotEmpty) {
    final decodedText = img.decodeImage(params.textOverlayPngBytes!);
    if (decodedText != null) {
      img.compositeImage(canvas, decodedText);
    }
  }

  if (params.watermarkIconBytes != null && params.watermarkIconBytes!.isNotEmpty) {
    WatermarkHelper.setIconBytes(params.watermarkIconBytes!);
  }

  final watermarked = WatermarkHelper.applyToImage(canvas, params.appSettings);
  return Uint8List.fromList(img.encodeJpg(watermarked, quality: 95));
}

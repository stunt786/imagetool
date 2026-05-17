import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../shared/services/file_picker_service.dart';
import '../models/collage_state.dart';

final collageProvider = NotifierProvider<CollageNotifier, CollageState>(
  CollageNotifier.new,
);

class CollageNotifier extends Notifier<CollageState> {
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

  Future<void> pickImages() async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      target: PickTarget.images,
      allowMultiple: true,
    );

    if (picked.isEmpty) return;

    final bytesList = <Uint8List>[];
    final names = <String>[];

    for (final file in picked) {
      if (file.path != null) {
        final bytes = await File(file.path!).readAsBytes();
        bytesList.add(bytes);
        names.add(file.name);
      }
    }

    if (bytesList.isEmpty) return;

    final newLayout = CollageLayout.getLayoutForImageCount(bytesList.length);
    final newImages = <CollageImageSlot>[];

    for (int i = 0; i < newLayout.slotCount; i++) {
      if (i < bytesList.length) {
        newImages.add(CollageImageSlot(
          index: i,
          imageBytes: bytesList[i],
          imageName: names[i],
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

  Future<void> addImageToSlot(int slotIndex) async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      target: PickTarget.images,
      allowMultiple: false,
    );

    if (picked.isEmpty || picked.first.path == null) return;

    final bytes = await File(picked.first.path!).readAsBytes();

    final newImages = List<CollageImageSlot>.from(state.images);
    newImages[slotIndex] = CollageImageSlot(
      index: slotIndex,
      imageBytes: bytes,
      imageName: picked.first.name,
    );

    state = state.copyWith(images: newImages);
  }

  void removeImageFromSlot(int slotIndex) {
    final newImages = List<CollageImageSlot>.from(state.images);
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

    state = state.copyWith(images: newImages);
  }

  void changeLayout(CollageLayout newLayout) {
    final newImages = <CollageImageSlot>[];
    for (int i = 0; i < newLayout.slotCount; i++) {
      if (i < state.images.length) {
        newImages.add(CollageImageSlot(
          index: i,
          imageBytes: state.images[i].imageBytes,
          imageName: state.images[i].imageName,
          scale: state.images[i].scale,
          offsetX: state.images[i].offsetX,
          offsetY: state.images[i].offsetY,
          fitMode: state.images[i].fitMode,
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

  Future<Uint8List?> exportCollage() async {
    state = state.copyWith(isExporting: true, exportProgress: 0.0);

    try {
      final canvas = img.Image(
        width: state.canvasWidth,
        height: state.canvasHeight,
      );

      img.fill(canvas, color: img.ColorRgb8(
        (state.backgroundColor.r * 255).round().clamp(0, 255),
        (state.backgroundColor.g * 255).round().clamp(0, 255),
        (state.backgroundColor.b * 255).round().clamp(0, 255),
      ));

      final gapPx = state.gap.toInt();
      final radiusPx = state.cornerRadius.toInt();

      for (int i = 0; i < state.layout.slotCount; i++) {
        final slot = state.images[i];
        if (!slot.hasImage) continue;

        final rect = state.layout.slotRects[i];
        final x = (rect.left * state.canvasWidth + gapPx).toInt();
        final y = (rect.top * state.canvasHeight + gapPx).toInt();
        final w = ((rect.width) * state.canvasWidth - gapPx * 2).toInt();
        final h = ((rect.height) * state.canvasHeight - gapPx * 2).toInt();

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

        if (slot.fitMode == ImageFitMode.contain) {
          img.fill(slotImage, color: img.ColorRgb8(
            (state.backgroundColor.r * 255).round().clamp(0, 255),
            (state.backgroundColor.g * 255).round().clamp(0, 255),
            (state.backgroundColor.b * 255).round().clamp(0, 255),
          ));
          final offsetX = ((w - resized.width) / 2).toInt();
          final offsetY = ((h - resized.height) / 2).toInt();
          img.compositeImage(slotImage, resized, dstX: offsetX, dstY: offsetY);
        } else {
          img.compositeImage(slotImage, resized);
        }

        if (radiusPx > 0) {
          _applyRoundedCorners(slotImage, radiusPx);
        }

        img.compositeImage(canvas, slotImage, dstX: x, dstY: y);

        state = state.copyWith(exportProgress: (i + 1) / state.layout.slotCount);
      }

      final encoded = img.encodeJpg(canvas, quality: 95);
      state = state.copyWith(isExporting: false, exportProgress: 1.0);
      return Uint8List.fromList(encoded);
    } catch (e) {
      state = state.copyWith(isExporting: false);
      rethrow;
    }
  }

  void _applyRoundedCorners(img.Image image, int radius) {
    final w = image.width;
    final h = image.height;
    final r = radius.clamp(0, w ~/ 2).clamp(0, h ~/ 2);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool shouldClear = false;

        if (x < r && y < r) {
          final dx = x - r + 1;
          final dy = y - r + 1;
          if (dx * dx + dy * dy > r * r) shouldClear = true;
        } else if (x >= w - r && y < r) {
          final dx = x - (w - r);
          final dy = y - r + 1;
          if (dx * dx + dy * dy > r * r) shouldClear = true;
        } else if (x < r && y >= h - r) {
          final dx = x - r + 1;
          final dy = y - (h - r);
          if (dx * dx + dy * dy > r * r) shouldClear = true;
        } else if (x >= w - r && y >= h - r) {
          final dx = x - (w - r);
          final dy = y - (h - r);
          if (dx * dx + dy * dy > r * r) shouldClear = true;
        }

        if (shouldClear) {
          image.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        }
      }
    }
  }

  void reset() {
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

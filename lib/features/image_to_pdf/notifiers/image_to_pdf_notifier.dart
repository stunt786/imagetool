import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/services/file_picker_service.dart';
import '../models/image_to_pdf_state.dart';

final imageToPdfProvider = NotifierProvider<ImageToPdfNotifier, ImageToPdfState>(
  ImageToPdfNotifier.new,
);

class ImageToPdfNotifier extends Notifier<ImageToPdfState> {
  @override
  ImageToPdfState build() {
    return const ImageToPdfState(
      images: [],
      pageSettings: PdfPageSettings.defaults,
    );
  }

  Future<void> pickImages(BuildContext context) async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.images,
      allowMultiple: true,
    );

    if (picked.isEmpty) return;

    final newImages = <ImageToPdfItem>[];
    for (final file in picked) {
      if (file.bytes == null) continue;

      int? width;
      int? height;
      try {
        final decoded = await compute(_decodeImageDimensions, file.bytes!);
        if (decoded != null) {
          width = decoded[0];
          height = decoded[1];
        }
      } catch (_) {}

      newImages.add(ImageToPdfItem(
        path: file.path ?? '',
        name: file.name,
        sizeBytes: file.sizeBytes,
        imageBytes: file.bytes,
        width: width,
        height: height,
      ));
    }

    if (newImages.isEmpty) return;

    state = state.copyWith(
      images: [...state.images, ...newImages],
      errorMessage: null,
      generatedPdfPath: null,
    );
  }

  Future<void> addImageFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final name = path.split(Platform.pathSeparator).last;
    final sizeBytes = await file.length();

    final newItem = ImageToPdfItem(
      path: path,
      name: name,
      sizeBytes: sizeBytes,
    );

    state = state.copyWith(
      images: [...state.images, newItem],
      errorMessage: null,
      generatedPdfPath: null,
    );

    await _loadImage(state.images.length - 1);
  }

  Future<void> _loadImage(int index) async {
    if (index < 0 || index >= state.images.length) return;
    
    final item = state.images[index];
    if (item.isLoaded) return;

    try {
      final file = File(item.path);
      final bytes = await file.readAsBytes();
      
      int? width;
      int? height;
      try {
        final decoded = await compute(_decodeImageDimensions, bytes);
        if (decoded != null) {
          width = decoded[0];
          height = decoded[1];
        }
      } catch (_) {
      }

      final updatedItem = item.copyWith(
        imageBytes: bytes,
        width: width,
        height: height,
      );
      state = state.updateImage(index, updatedItem);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load image: ${item.name}');
    }
  }

  static List<int>? _decodeImageDimensions(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image != null) {
        return [image.width, image.height];
      }
    } catch (_) {
    }
    return null;
  }

  void removeImage(int index) {
    state = state.removeImage(index);
  }

  void swapImage(int index1, int index2) {
    state = state.swapImages(index1, index2);
  }

  void reorderImages(int oldIndex, int newIndex) {
    state = state.reorderImages(oldIndex, newIndex);
  }

  void updatePageSettings(PdfPageSettings settings) {
    state = state.copyWith(pageSettings: settings);
  }

  void clearAll() {
    state = const ImageToPdfState(
      images: [],
      pageSettings: PdfPageSettings.defaults,
    );
  }

  Future<String?> generatePdf() async {
    if (state.images.isEmpty) {
      state = state.copyWith(errorMessage: 'No images selected');
      return null;
    }

    state = state.copyWith(
      isGenerating: true,
      progress: 0.0,
      errorMessage: null,
      generatedPdfPath: null,
    );

    try {
      final pdf = pw.Document();
      final settings = state.pageSettings;

      for (int i = 0; i < state.images.length; i++) {
        final item = state.images[i];
        
        if (!item.isLoaded) {
          await _loadImage(i);
        }

        final currentItem = state.images[i];
        if (!currentItem.isLoaded || currentItem.imageBytes == null) {
          continue;
        }

        final imageBytes = currentItem.imageBytes!;
        img.Image? decodedImage;
        try {
          decodedImage = img.decodeImage(imageBytes);
        } catch (_) {
          continue;
        }

        if (decodedImage == null) continue;

        final imageWidth = decodedImage.width;
        final imageHeight = decodedImage.height;
        final isImageLandscape = imageWidth > imageHeight;

        PdfPageFormat pageFormat;
        switch (settings.pageSize) {
          case PdfPageSize.a4:
            pageFormat = PdfPageFormat.a4;
            break;
          case PdfPageSize.a3:
            pageFormat = PdfPageFormat.a3;
            break;
          case PdfPageSize.usLetter:
            pageFormat = PdfPageFormat.letter;
            break;
          case PdfPageSize.usLegal:
            pageFormat = PdfPageFormat.legal;
            break;
          case PdfPageSize.matchImage:
            final pointsPerPixel = 72.0 / 150.0;
            pageFormat = PdfPageFormat(
              imageWidth * pointsPerPixel,
              imageHeight * pointsPerPixel,
            );
            break;
        }

        if (settings.orientation == PdfOrientation.auto) {
          final isPagePortrait = pageFormat.width < pageFormat.height;
          if (isImageLandscape && isPagePortrait) {
            pageFormat = pageFormat.landscape;
          } else if (!isImageLandscape && !isPagePortrait) {
            pageFormat = pageFormat.portrait;
          }
        } else if (settings.orientation == PdfOrientation.landscape) {
          pageFormat = pageFormat.landscape;
        } else {
          pageFormat = pageFormat.portrait;
        }

        final marginLeft = settings.marginLeft * PdfPageFormat.inch;
        final marginRight = settings.marginRight * PdfPageFormat.inch;
        final marginTop = settings.marginTop * PdfPageFormat.inch;
        final marginBottom = settings.marginBottom * PdfPageFormat.inch;
        final availableFormat = PdfPageFormat(
          pageFormat.width - marginLeft - marginRight,
          pageFormat.height - marginTop - marginBottom,
        );

        Uint8List processedBytes;
        if (settings.quality == PdfQuality.optimized) {
          final jpegBytes = img.encodeJpg(decodedImage, quality: 90);
          processedBytes = Uint8List.fromList(jpegBytes);
        } else {
          if (decodedImage.hasAlpha) {
            final flattened = img.Image(width: decodedImage.width, height: decodedImage.height);
            img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
            img.compositeImage(flattened, decodedImage);
            final pngBytes = img.encodePng(flattened);
            processedBytes = Uint8List.fromList(pngBytes);
          } else {
            processedBytes = imageBytes;
          }
        }

        final pdfImage = pw.MemoryImage(processedBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (context) {
              return pw.Container(
                padding: pw.EdgeInsets.only(
                  left: marginLeft,
                  top: marginTop,
                  right: marginRight,
                  bottom: marginBottom,
                ),
                child: _buildImageWidget(pdfImage, settings.fitMode, availableFormat, imageWidth, imageHeight),
              );
            },
          ),
        );

        state = state.copyWith(progress: (i + 1) / state.images.length);
      }

      final pdfBytes = await pdf.save();

      Directory saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download/PixelTools/PDFs');
        try {
          if (!await saveDir.exists()) {
            await saveDir.create(recursive: true);
          }
        } catch (_) {
          final base = await getApplicationDocumentsDirectory();
          saveDir = Directory(path.join(base.path, 'PixelTools', 'PDFs'));
          if (!await saveDir.exists()) {
            await saveDir.create(recursive: true);
          }
        }
      } else {
        final base = await getApplicationDocumentsDirectory();
        saveDir = Directory(path.join(base.path, 'PixelTools', 'PDFs'));
        if (!await saveDir.exists()) {
          await saveDir.create(recursive: true);
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'pixeltools_$timestamp.pdf';
      final outputPath = path.join(saveDir.path, fileName);
      
      final file = File(outputPath);
      await file.writeAsBytes(pdfBytes, flush: true);
      
      final fileSize = await file.length();
      if (!await file.exists() || fileSize == 0) {
        throw Exception('PDF file was not created or is empty');
      }

      state = state.copyWith(
        isGenerating: false,
        progress: 1.0,
        generatedPdfPath: outputPath,
      );

      return outputPath;
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        errorMessage: 'Failed to generate PDF: $e',
      );
      return null;
    }
  }

  pw.Widget _buildImageWidget(
    pw.MemoryImage image,
    ImageFitMode fitMode,
    PdfPageFormat availableFormat,
    int imageWidth,
    int imageHeight,
  ) {
    switch (fitMode) {
      case ImageFitMode.fit:
        return pw.Image(
          image,
          fit: pw.BoxFit.contain,
          width: availableFormat.width,
          height: availableFormat.height,
        );
      case ImageFitMode.fill:
        return pw.Image(
          image,
          fit: pw.BoxFit.cover,
          width: availableFormat.width,
          height: availableFormat.height,
        );
      case ImageFitMode.center:
        final scaleX = availableFormat.width / imageWidth;
        final scaleY = availableFormat.height / imageHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final displayScale = scale < 1.0 ? scale : 1.0;
        return pw.Center(
          child: pw.Image(
            image,
            width: imageWidth * displayScale,
            height: imageHeight * displayScale,
          ),
        );
      case ImageFitMode.stretch:
        return pw.Image(
          image,
          fit: pw.BoxFit.fill,
          width: availableFormat.width,
          height: availableFormat.height,
        );
    }
  }
}

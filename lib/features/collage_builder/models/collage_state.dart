import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ImageFitMode { cover, contain, fill }

@immutable
class CollageImageSlot {
  const CollageImageSlot({
    required this.index,
    this.imageBytes,
    this.imageName,
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.fitMode = ImageFitMode.cover,
  });

  final int index;
  final Uint8List? imageBytes;
  final String? imageName;
  final double scale;
  final double offsetX;
  final double offsetY;
  final ImageFitMode fitMode;

  bool get hasImage => imageBytes != null;

  CollageImageSlot copyWith({
    Uint8List? imageBytes,
    String? imageName,
    double? scale,
    double? offsetX,
    double? offsetY,
    ImageFitMode? fitMode,
  }) {
    return CollageImageSlot(
      index: index,
      imageBytes: imageBytes ?? this.imageBytes,
      imageName: imageName ?? this.imageName,
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      fitMode: fitMode ?? this.fitMode,
    );
  }

  CollageImageSlot clear() {
    return CollageImageSlot(
      index: index,
      imageBytes: null,
      imageName: null,
      scale: 1.0,
      offsetX: 0.0,
      offsetY: 0.0,
      fitMode: ImageFitMode.cover,
    );
  }
}

@immutable
class CollageLayout {
  const CollageLayout({
    required this.id,
    required this.name,
    required this.slotCount,
    required this.slotRects,
  });

  final String id;
  final String name;
  final int slotCount;
  final List<Rect> slotRects;

  static List<CollageLayout> get all => [
    CollageLayout(
      id: 'single',
      name: 'Single',
      slotCount: 1,
      slotRects: [Rect.fromLTRB(0, 0, 1, 1)],
    ),
    CollageLayout(
      id: 'horizontal_2',
      name: '2 Horizontal',
      slotCount: 2,
      slotRects: [
        Rect.fromLTRB(0, 0, 0.5, 1),
        Rect.fromLTRB(0.5, 0, 1, 1),
      ],
    ),
    CollageLayout(
      id: 'vertical_2',
      name: '2 Vertical',
      slotCount: 2,
      slotRects: [
        Rect.fromLTRB(0, 0, 1, 0.5),
        Rect.fromLTRB(0, 0.5, 1, 1),
      ],
    ),
    CollageLayout(
      id: 'grid_2x2',
      name: '2x2 Grid',
      slotCount: 4,
      slotRects: [
        Rect.fromLTRB(0, 0, 0.5, 0.5),
        Rect.fromLTRB(0.5, 0, 1, 0.5),
        Rect.fromLTRB(0, 0.5, 0.5, 1),
        Rect.fromLTRB(0.5, 0.5, 1, 1),
      ],
    ),
    CollageLayout(
      id: 'featured_top',
      name: 'Featured Top',
      slotCount: 3,
      slotRects: [
        Rect.fromLTRB(0, 0, 1, 0.6),
        Rect.fromLTRB(0, 0.6, 0.5, 1),
        Rect.fromLTRB(0.5, 0.6, 1, 1),
      ],
    ),
    CollageLayout(
      id: 'featured_left',
      name: 'Featured Left',
      slotCount: 3,
      slotRects: [
        Rect.fromLTRB(0, 0, 0.6, 1),
        Rect.fromLTRB(0.6, 0, 1, 0.5),
        Rect.fromLTRB(0.6, 0.5, 1, 1),
      ],
    ),
    CollageLayout(
      id: 'grid_2x3',
      name: '2x3 Grid',
      slotCount: 6,
      slotRects: [
        Rect.fromLTRB(0, 0, 0.5, 0.333),
        Rect.fromLTRB(0.5, 0, 1, 0.333),
        Rect.fromLTRB(0, 0.333, 0.5, 0.666),
        Rect.fromLTRB(0.5, 0.333, 1, 0.666),
        Rect.fromLTRB(0, 0.666, 0.5, 1),
        Rect.fromLTRB(0.5, 0.666, 1, 1),
      ],
    ),
    CollageLayout(
      id: 'mosaic',
      name: 'Mosaic',
      slotCount: 5,
      slotRects: [
        Rect.fromLTRB(0, 0, 0.5, 0.5),
        Rect.fromLTRB(0.5, 0, 1, 0.5),
        Rect.fromLTRB(0, 0.5, 0.333, 1),
        Rect.fromLTRB(0.333, 0.5, 0.666, 1),
        Rect.fromLTRB(0.666, 0.5, 1, 1),
      ],
    ),
    CollageLayout(
      id: 't_layout',
      name: 'T-Layout',
      slotCount: 4,
      slotRects: [
        Rect.fromLTRB(0, 0, 1, 0.5),
        Rect.fromLTRB(0, 0.5, 0.333, 1),
        Rect.fromLTRB(0.333, 0.5, 0.666, 1),
        Rect.fromLTRB(0.666, 0.5, 1, 1),
      ],
    ),
  ];

  static CollageLayout getLayoutForImageCount(int count) {
    if (count <= 0) return all[0];
    if (count == 1) return all[0];
    if (count == 2) return all[2];
    if (count == 3) return all[4];
    if (count == 4) return all[3];
    if (count == 5) return all[7];
    return all[6];
  }
}

@immutable
class CollageState {
  const CollageState({
    required this.images,
    required this.layout,
    required this.gap,
    required this.cornerRadius,
    required this.backgroundColor,
    required this.canvasWidth,
    required this.canvasHeight,
    this.isExporting = false,
    this.exportProgress = 0.0,
  });

  final List<CollageImageSlot> images;
  final CollageLayout layout;
  final double gap;
  final double cornerRadius;
  final Color backgroundColor;
  final int canvasWidth;
  final int canvasHeight;
  final bool isExporting;
  final double exportProgress;

  int get imageCount => images.where((s) => s.hasImage).length;

  CollageState copyWith({
    List<CollageImageSlot>? images,
    CollageLayout? layout,
    double? gap,
    double? cornerRadius,
    Color? backgroundColor,
    int? canvasWidth,
    int? canvasHeight,
    bool? isExporting,
    double? exportProgress,
  }) {
    return CollageState(
      images: images ?? this.images,
      layout: layout ?? this.layout,
      gap: gap ?? this.gap,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      isExporting: isExporting ?? this.isExporting,
      exportProgress: exportProgress ?? this.exportProgress,
    );
  }
}
